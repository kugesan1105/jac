# Design: in-cluster `.jab` build Job (fixes #7243 at the architecture level)

Status: **proposal** - align before implementing.

## Problem

Issue #7243: production deploys via the **jacBuilder deploy operator** intermittently
fail with `[Errno 2] No such file or directory` for `redis.conf.template` and
`hpa_autoscaler.jac` under `.../rt/<hash>/site/jaclang/scale/deploy/...`.

### Root cause (confirmed by reading the code)

The failing files are **not** missing from the release binary - `skipJaclang` in
`launcher/payload.zig` bundles the whole `jaclang/` tree (only `__pycache__`,
`_precompiled`, `node_modules`, shims, `.pyc` are excluded), and the launcher's
extraction (`launcher/runtime.zig`) is **atomic** (temp dir + `.ok` marker +
rename) even in the reporter's 0.30.8.

The atomic guarantee is **per-process and at-startup**: every `jac` CLI process
calls `materialize()` once before running any code and blocks until the cache
tree is complete. Separate `jac` processes (app pods, CLI) are therefore safe.

The deploy **operator** breaks that assumption. It is a long-lived, multi-threaded
server that embeds jaclang and runs many deploys concurrently **in one process**,
sharing one `rt/<hash>/site/` cache. The single startup barrier does not protect
threads that read `site/` files while a cold extraction is still in flight. The
two failing files are the ones read **late / off the import-warmup path**
(`redis.conf.template` via a raw `__file__` read; `hpa_autoscaler` via a lazy
in-method import), so they are the ones caught in the extraction window.

The operator is a **downstream/product component** (not in this repo - `grep`
for `jacBuilder` finds nothing here), so the concurrency model itself cannot be
fixed in jaclang. What we can fix is **where the build runs**.

## Why the build lives on a "driver" at all

Producing a deploy artifact requires running `jac`: `download_release_binary`,
`_precompile_app` (which shells out to `jac ... --seal`), `pack_jab`, manifest
building, PVC seeding. Whoever triggers a deploy (laptop, CI runner, or the
in-cluster operator) needs `jac` to *build* the `.jab`. The init container + PVC
carry the **result** of the build to app pods; they cannot serve the builder
(chicken-and-egg: the builder produces what the PVC holds).

Today `KubernetesTarget.deploy()` does this on the driver:

1. `select_injector()` -> `pack_jab()` builds the `.jab` **on the driver**
   (`kubernetes_target.jac:1015`).
2. `injector.seed()` spins a one-shot **`{app}-bundle-loader`** pod and
   `kubectl cp`s the `.jab` onto the RWX bundle PVC (`pvc_injector.jac:126`).
3. `create_namespaced_deployment()` starts app pods; each init container
   `tar xzf`s the `.jab` from the PVC into `/app` (`kubernetes_target.jac:1116`).

The race is entirely in step 1 **when the driver is the long-lived operator**.

## Proposal: build the `.jab` in a one-shot Job, not on the driver

Move the build from the driver into a dedicated **pre-deploy build Job** (a fresh,
single-process, one-shot pod). This reuses the existing bundle-loader pattern -
the loader pod already mounts the PVC and writes to it; we extend it to **build**
the `.jab` rather than receive a pre-built one.

```
Driver (operator / CLI / CI) - now only ORCHESTRATES, never builds:
  1. create bundle PVC (RWX)
  2. create build Job:
        install jac (from PVC toolchain or downloaded) ->
        jac build --as jab (source -> sealed .jab) ->
        write .jab to the PVC (content-addressed key) ->
        exit
  3. wait for Job success
  4. create the Deployment; app pods' init containers cp the .jab from the PVC
```

### Why this fixes #7243

- The builder is a **fresh one-shot container**: it extracts `jac` once, builds,
  and exits. One process, no concurrent threads sharing a cold cache -> the
  per-process startup barrier the launcher already provides is sufficient. The
  race window closes structurally.
- The driver is reduced to a **control step** (create Job, wait, create
  Deployment). It never runs the racy `jac` extraction, so even a long-lived
  multi-threaded operator is safe: it issues Kubernetes API calls, not builds.

### Why it keeps the current architecture's wins

- **Build once, share many.** One Job seeds the content-addressed PVC; every app
  pod `cp`s the identical `.jab`. No per-pod seal cost, no on-pod OOM risk, no
  cold-compile-on-boot - exactly what #7288 established. (Contrast: building in
  each app pod's own init container would re-seal N times, risk nondeterministic
  images, and regress every one of those wins.)
- **Ordering is explicit.** The Deployment is created only after the Job reports
  success, so no app pod starts before the `.jab` is on the PVC. A Job (not a
  bare pod) gives us completion semantics + backoff for free.

## Trade-offs (eyes open)

1. **Something still orchestrates.** The driver/CLI must create the Job, wait,
   then create the Deployment. That control step is thin and does no `jac`
   extraction, so it carries none of the race - but it is still an in-cluster (or
   CLI) actor. Acceptable: orchestration is not the bug; concurrent cold builds
   were.
2. **The build runs in-cluster.** The Job pod needs enough CPU/mem for the seal
   (~1-2 min JIR precompile). It is **one** right-sized pod per deployment, not
   every app pod. Set resources on the Job template.
3. **Sequential latency.** Deploy = Job build time, then rollout. Today the driver
   builds in parallel with cluster setup, so this adds the build to the critical
   path. Mitigations: cache the toolchain on the PVC (already content-addressed),
   and the content-addressed `.jab` key means an unchanged app skips the rebuild.
4. **Failure surfacing.** A failed seal now fails the **Job**, not the driver
   call. Surface the Job's logs/exit in the deploy result so operators still see
   the seal error (mandatory-seal behaviour from #7306 must be preserved).

## Rough implementation shape (for the follow-up code PR)

- `pvc_injector` / a new `build_job` module: emit a K8s **`batchv1.Job`** whose
  container installs `jac` and runs `jac build --as jab <src> -o <pvc>/<key>`.
  Reuse `bundle_pvc_name` / `bundle_object_key` / the RWX mount.
- `KubernetesTarget.deploy()`: replace the driver-side `select_injector()` +
  `pack_jab()` + `injector.seed()` with "create Job -> wait for success", then
  proceed to `create_namespaced_deployment()` unchanged (app pods still
  `tar xzf` the `.jab` from the PVC).
- Preserve content-addressing (skip the Job if the `.jab` key is already present
  on the PVC) and mandatory-seal failure surfacing.
- The source still needs to reach the Job - ship it the same way the driver ships
  it today (loader `kubectl cp` of the source, or a git/source mount), then let
  the Job seal it in-cluster.

## Out of scope

- Fixing the operator's concurrency model directly (downstream, not this repo).
- The small alternative in-repo hardening for #7243 (move `hpa_autoscaler` to a
  top-level import + read `redis.conf.template` via `importlib.resources`, so the
  two files load on the already-barriered startup path). That is a valid
  smaller-scope mitigation and can land independently of this build-Job redesign.
