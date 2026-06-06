# Contrib and Codebase Guide

## Checkout and push ready

**Fork the Repository**

1. Navigate to [https://github.com/jaseci-labs/jaseci](https://github.com/jaseci-labs/jaseci)
2. Click the **Fork** button in the top-right corner
3. Select your GitHub account to create the fork

**Clone and Set Up Upstream**

After forking, clone your fork and set up the upstream remote:

```bash
# Clone your fork (replace YOUR_USERNAME with your GitHub username)
git clone https://github.com/YOUR_USERNAME/jaseci.git
cd jaseci
git submodule update --init --recursive
git remote add upstream https://github.com/jaseci-labs/jaseci.git
git remote -v
```

**Setting Up Your Dev Envrionment**

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -e jac
jac install -e jac-byllm
jac install -e jac-scale
jac install -e jac-client
jac install -e jac-super
jac install -e jac-mcp
pip install pre-commit
pre-commit install
pip install pytest pytest-xdist pytest-asyncio
```

**Run Some Tests**

```bash
pytest jac -n auto
# See ci jobs in github actions for more stuff to run
```

**Build something awesome, or fix something that's broken**

See Rules below.
And check [`.pre-commit-config.yaml`](https://github.com/Jaseci-Labs/jaseci/blob/main/.pre-commit-config.yaml) to see our lint strategy.

**This is how we run the docs.**

```bash
pip install -e docs # <-- Not a real package more of a script
python docs/scripts/mkdocs_serve.py
```

**Pushing Your First PR**

1. **Create a branch, make changes, sync, and push**:

   ```bash
   git checkout -b your-feature-branch

   # Make your changes, then commit
   git add .
   git commit -m "Description of your changes"

   # Keep your fork synced with upstream
   git fetch upstream
   git merge upstream/main

   # Push to your fork
   git push origin your-feature-branch
   ```

2. **Create a Pull Request**:
   - Go to your fork on GitHub
   - Click **Compare & pull request**
   - Fill in the PR description with details about your changes
   - Submit the pull request to the `main` branch of `jaseci-labs/jaseci`

> **Tip: PR Best Practices**
>
> - Make sure all pre-commit checks pass before pushing
> - Run tests locally using the test script above
> - Keep your PR focused on a single feature or fix
> - Write clear commit messages and PR descriptions
> - Add a release note fragment (see below)

**Adding Release Notes**

Every PR that changes package code must include a release note fragment file:

1. Create a file at `docs/docs/community/release_notes/unreleased/<package>/<PR#>.<category>.md`
   - **Packages**: `jaclang`, `byllm`, `jac-client`, `jac-scale`, `jac-super`, `jac-mcp`
   - **Categories**: `feature`, `bugfix`, `breaking`, `refactor`, or `docs`
   - **Example**: `docs/docs/community/release_notes/unreleased/jaclang/1234.bugfix.md`

2. Add one or more bullet points:

   ```markdown
   - **Fix: Brief title**: Description of what changed.
   - **Fix: Another fix in same PR**: Description.
   ```

To skip this check, add the `skip-release-notes-check` label to your PR.

**Example PR with a release note fragment**: [#5573](https://github.com/jaseci-labs/jaseci/pull/5573)

## Code Rules and Guidelines

**Jac Style**

All Jac code must follow the project's established coding style. If you're using an AI assistant, prompt it to study the existing style before generating code. For example, when working in a specific area:

> "Can you study the jac coding style used in this code base (byllm/project folder), and make sure my change adheres to that style."

**No Scaffolding**

Never add code that only exists as scaffolding or infrastructure for future PRs. Every line in your PR should serve the change being made right now. The one exception is when two different authors have a producer-consumer dependency for a feature or fix and need to coordinate across PRs.

**Type Safety**

Write type-safe code. Avoid stringly-typed interfaces:

- Use **enums** instead of bare strings for option sets
- Create **named types or dataclasses** for complex return values instead of raw tuples like `-> tuple[str, str, dict, dict, dict]`

**Check for Bloat**

Before submitting, use an AI assistant to audit your diff for unnecessary code. A good prompt:

> "Can you look at the local changes to see if there is any bloat or inefficient implementation given what these changes are achieving."

**Issue Assignment**

Assignees on GitHub issues means the person is **committing to resolve** that issue, not that they "should" work on it. Keep as many issues unassigned as possible so contributors can pick them up.

**Documentation Updates**

The docs site has three tiers with different expectations for contributors:

- **Quick Guide** -- Get a quick experience with Jac. Most features don't need to touch this.
- **Full Reference** -- Must cover everything. **Every feature or change should update the reference docs.**

## Release Flow (for maintainers)

Releasing new versions to PyPI is a two-step process using GitHub Actions.

```
┌─────────────────────┐      ┌─────────────────────┐      ┌─────────────────────┐
│  Create Release PR  │ ───▶ │   Merge to main     │ ───▶ │  Approve & Publish  │
│  (manual trigger)   │      │   (triggers publish)│      │  (one-click)        │
└─────────────────────┘      └─────────────────────┘      └─────────────────────┘
```

### Step 1: Create the Release PR

1. Go to **GitHub Actions** → **Create Release PR**
2. Click **Run workflow**
3. For each package, select the version bump type (`skip`, `patch`, `minor`, or `major`):
   - `jaclang`, `jac-byllm`, `jac-client`, `jac-scale`, `jac-super`, `jac-mcp`, `jac-desktop`, `jaseci`
4. Click **Run workflow**
5. The workflow validates versions against PyPI, bumps them, creates a PR from a `release/*` branch, and triggers the CI workflows on it
6. Wait for CI tests to pass, then **approve and merge** the PR to main

### Step 2: Approve Publishing

After the release PR is merged, the **Publish Release** workflow triggers automatically:

1. It parses the packages and versions from the PR title
2. **Manual approval required** (only maintainers with `pypi` environment access can approve):
   - Go to **GitHub Actions** → find the running **Publish Release** workflow
   - The workflow will pause at the "approve-release" job waiting for approval
   - Click on the job, then click **Review deployments**
   - Select the `pypi` environment and click **Approve and deploy**
3. The workflow then handles everything automatically:
   - Builds all packages once (precompiling bytecode for packages that need it; see [Precompilation](#precompilation) below)
   - Publishes in dependency order (tiered):
     - **Tier 1**: `jaclang` (base package; everything depends on it)
     - **Tier 2**: `jac-byllm`, `jac-client`, `jac-scale`, `jac-super`, `jac-mcp` (depend only on `jaclang`)
     - **Tier 3**: `jac-desktop` (depends on a tier-2 plugin, `jac-client`)
     - **Tier 4**: `jaseci` (meta-package; depends on everything above)
   - Pushes git tags (`{package}-v{version}`, plus `v{version}` for jaseci)
   - Creates a GitHub Release with artifacts
   - Builds standalone binaries (if jaseci was released)

> **Note**: The workflow waits for each tier to be available on PyPI before publishing the next, so a package never lands before the dependency it pins.

**Tiers are ordered by dependency depth.** A package goes in the lowest tier above every package it depends on. When you add a new package, set its `tier` in `scripts/release_utils.jac` accordingly (and `extra_build_deps` if it depends on another plugin, see below).

### Precompilation

Plugins ship precompiled `.jir` bytecode (one set per supported Python version) baked into the wheel, so users skip first-run compilation. The publish workflow does this via `jac bundle --precompile`, which spins up a throwaway venv **per Python version** and installs the package's dependencies into it to generate bytecode.

Because the venv installs deps from PyPI, a dependency whose **new** version is being released in the *same* run wouldn't exist on PyPI yet. Two escape hatches install from local source instead:

- `JAC_PRECOMPILE_LOCAL_INSTALL`: path to local `jaclang` source (every plugin depends on jaclang).
- `JAC_PRECOMPILE_LOCAL_DEPS`: comma-separated local source dirs for **sibling plugins** (e.g. `jac-desktop` depends on `jac-client`). The workflow wires this from each package's `extra_build_deps`.

This is why `jac-desktop` can build and publish in the *same* combined release as `jac-client` rather than needing a separate run.

### Adding a new package to the release

Register it in `scripts/release_utils.jac`:

1. Add a `PackageInfo` entry to `PACKAGES` with its `dir`, `pypi` name, and **`tier`** (lowest tier above all its dependencies).
2. Set `precompile=True` if it ships `.jac` source, and `extra_build_deps="<sibling>"` if it depends on another plugin (so precompile installs that sibling from local source).
3. Add its internal dependencies to `INTERNAL_DEPS` so dependent version pins are kept in sync on release.
4. Add a `jac-desktop`-style input to the `Create Release PR` and `Publish Release` workflows.
5. Add its release-notes path under `docs/docs/community/release_notes/`.

### Troubleshooting

| Issue | Solution |
|-------|----------|
| CI tests not running on release PR | The `Create Release PR` workflow triggers them automatically; if they're missing, manually re-run `test-jaseci.yml` / `jac-check.yml` on the `release/*` branch |
| Publish workflow didn't trigger | Ensure the PR branch started with `release/` |
| A tier failed to publish | Re-run the failed job from GitHub Actions; already-published packages are skipped (`skip-existing`) |
| Need to re-publish after the release PR is already merged | Manually trigger **Publish Release** (`workflow_dispatch`): check the packages to publish; versions are read from each package's manifest on `main`, so there's nothing to type |
| `jac-client>=X not found` during a plugin's precompile | The sibling plugin's new version isn't on PyPI yet; ensure the plugin's `extra_build_deps` names that sibling so it's installed from local source |
| Version conflict on PyPI | The `Create Release PR` workflow validates this upfront - if you hit this, someone manually published |
