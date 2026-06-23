#!/usr/bin/env bash
# Prints `requested=<space-separated suites>` to $GITHUB_OUTPUT for ci.yml's plan
# job, which gates each suite on it.
#
#   push        -> every orchestrated suite (full post-merge coverage)
#   PR attempt 1 -> nothing (the auto run on open/push requests nothing, so a
#                  fresh commit starts clean)
#   PR re-run   -> the suites named by the most recent `/test` comment from a
#                  read+ collaborator; `all` expands to every suite
#
# Only ci.yml's suites are emitted. `contrib` is a valid /test token but runs via
# its own always-on workflow, so it is not orchestrated here (see
# ci-rerun-on-test.sh). Requires gh + jq (preinstalled on GitHub runners).
set -euo pipefail

# Suites ci.yml orchestrates. Keep in sync with ci.yml and ci-rerun-on-test.sh.
SUITES="core client scale mcp byllm docs desktop macos pypi k8s check installer"
out="${GITHUB_OUTPUT:-/dev/stdout}"

emit() { echo "requested=$(echo "$1" | xargs || true)" >> "$out"; }

# Push: full coverage.
[[ "${GITHUB_EVENT_NAME:-}" == "push" ]] && { emit "$SUITES"; exit 0; }

# Only a /test re-run (attempt > 1) reads comments; otherwise request nothing.
attempt="${GITHUB_RUN_ATTEMPT:-0}"
[[ "$attempt" =~ ^[0-9]+$ ]] && (( attempt > 1 )) || { emit ""; exit 0; }

pr="$(jq -r '.pull_request.number // .issue.number // empty' "${GITHUB_EVENT_PATH:-/dev/null}" 2>/dev/null || true)"
[[ -n "$pr" ]] || { emit ""; exit 0; }
repo="${GITHUB_REPOSITORY:?}"

# All PR comments, oldest-first: "<login>\t<body-first-line>".
mapfile -t lines < <(
  gh api --paginate "repos/$repo/issues/$pr/comments" \
    --jq '.[] | [.user.login, (.body // "" | gsub("\r";"") | split("\n")[0])] | @tsv' \
  2>/dev/null || true
)

# Read+ access (read/triage/write/maintain/admin) on this repo.
is_collaborator() {
  local perm
  perm="$(gh api "repos/$repo/collaborators/$1/permission" --jq '.permission' 2>/dev/null || echo none)"
  case "$perm" in admin|maintain|write|triage|read) return 0;; *) return 1;; esac
}

# Newest-first: the first valid collaborator `/test` comment wins.
requested=""
for (( i=${#lines[@]}-1; i>=0; i-- )); do
  IFS=$'\t' read -r login body <<< "${lines[$i]}"
  body="${body#"${body%%[![:space:]]*}"}"   # ltrim
  [[ "$body" == /test* ]] || continue
  is_collaborator "$login" || continue

  read -ra toks <<< "${body#/test}"
  for t in "${toks[@]}"; do
    t="${t,,}"
    [[ "$t" == all ]] && { requested="$SUITES"; break; }
    for s in $SUITES; do
      [[ "$t" == "$s" && " $requested " != *" $s "* ]] && requested="$requested $s"
    done
  done
  break   # only the latest /test comment counts
done

emit "$requested"
