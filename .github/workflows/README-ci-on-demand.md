# On-demand CI

CI no longer runs automatically on PR pushes. A repo collaborator (read access
or higher) runs suites by commenting on the PR:

```
/test all                  run every suite
/test core                 run one suite
/test core client scale    run several suites
/test help                 list the suites
```

The command acts on the PR's **latest** commit. A new push starts clean - old
`/test` comments do not carry over (their Check Runs were bound to the old SHA).
A newer `/test` cancels an in-flight one, and runs only what the newest comment
named.

## How it fits together

| File | Role |
| --- | --- |
| `ci-command.yml` | Front door. On `issue_comment`, free runner. Authorizes the commenter, parses the command, reacts 🚀, resolves the PR head SHA + metadata, dispatches `ci-suites.yml`. |
| `ci-suites.yml` | Router. One `start`/suite/`end` trio per suite. `start` opens a `CI / <suite>` Check Run on the head SHA; the suite reusable runs; `end` concludes the check from the suite's result. |
| `ci-checkrun.yml` / `ci-checkrun-finish.yml` | Tiny reusables that create / conclude a Check Run via the Checks API. |
| `ci-main.yml` | On push to `main`, runs every suite so merged code stays fully covered. |
| `test-binary.yml`, `test-jaseci.yml`, `jac-check.yml`, `contribution-checks.yml`, `test-installer.yml`, `k8s-microservice-real-e2e.yml` | The actual suites, now `workflow_call` reusables (no `pull_request` trigger). |

## Suites

| Suite | What it runs |
| --- | --- |
| `core` | binary build + compiler + runtime + solid jsdom |
| `client` | client runtime tests |
| `scale` | jac-scale matrix + pypi/jacpack build smokes |
| `mcp` | jac-mcp tests |
| `byllm` | jac-byllm tests |
| `docs` | docs build + validation + e2e code blocks |
| `desktop` | dependency-free desktop tests |
| `macos` | native Mach-O linker regression (premium runner) |
| `k8s` | scale k8s matrix + microk8s real-app e2e |
| `check` | jac format + jac check + jir registry |
| `contrib` | contribution checks (AI co-author, no-python, release notes) |
| `installer` | install.sh shellcheck + download/run/uninstall |

## Branch protection (manual, one-time)

Mark the suite checks you want to gate merges on as **required status checks**
on `main`. They report under these exact names:

```
CI / core
CI / client
CI / scale
CI / mcp
CI / byllm
CI / docs
CI / desktop
CI / macos
CI / k8s
CI / check
CI / contrib
CI / installer
```

Suggested required set: `CI / core`, `CI / client`, `CI / check`, `CI / contrib`.
A required check that has never reported shows as "Expected" and blocks merge
until someone runs the matching `/test` and it passes - that is the intended
gate.

## Cost

An idle PR triggers nothing past `ci-command.yml`'s `if` guard (a comment that
does not start with `/test` never starts a runner). The free `ubuntu-latest`
triage job runs only on a `/test` comment. Paid runners spin up only for the
suites a collaborator explicitly asked for.
