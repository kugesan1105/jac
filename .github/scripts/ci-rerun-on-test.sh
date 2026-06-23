#!/usr/bin/env bash
# Handles a `/test ...` PR comment: authorize, react, and re-run the affected
# workflow's latest pull_request run so its plan job re-reads the request (see
# ci-requested-suites.sh). The re-run is the trigger -- this posts no comments
# and creates no status rows; the only feedback is an emoji reaction.
#
# Reactions:  eyes = help/ack   -1 = not a collaborator   confused = nothing to
# run / couldn't re-run   rocket = re-run started.
#
# Almost everything is orchestrated by ci.yml, so a /test re-runs that single
# workflow. `contrib` is the exception: it has its own always-on workflow
# (contribution-checks.yml), re-run directly here.
#
# Invoked by ci-command.yml on issue_comment. Requires gh + jq.
set -euo pipefail

repo="${GITHUB_REPOSITORY:?}"
event="${GITHUB_EVENT_PATH:?}"
comment_id="$(jq -r '.comment.id' "$event")"
pr="$(jq -r '.issue.number' "$event")"
commenter="$(jq -r '.comment.user.login' "$event")"
body="$(jq -r '.comment.body' "$event")"

react() { gh api -X POST "repos/$repo/issues/comments/$comment_id/reactions" -f "content=$1" >/dev/null 2>&1 || true; }

ORCHESTRATED="core client scale mcp byllm docs desktop macos pypi k8s check installer"
ALL="$ORCHESTRATED contrib"

# Tokens after `/test`, lowercased.
read -ra toks <<< "${body#*/test}"
args=()
for t in "${toks[@]}"; do args+=("${t,,}"); done

# Bare `/test` or `/test help`: just acknowledge.
if [[ ${#args[@]} -eq 0 || "${args[0]}" == help ]]; then react eyes; exit 0; fi

# Authoritative auth: read+ collaborator. (ci-command.yml already blocks obvious
# outsiders via author_association before the runner starts; this is the precise
# check that also covers read/triage roles.)
perm="$(gh api "repos/$repo/collaborators/$commenter/permission" --jq '.permission' 2>/dev/null || echo none)"
case "$perm" in admin|maintain|write|triage|read) ;; *) react "-1"; exit 0 ;; esac

# Resolve the requested suites.
requested=""
for a in "${args[@]}"; do
  [[ "$a" == all ]] && { requested="$ALL"; break; }
  [[ " $ALL " == *" $a "* && " $requested " != *" $a "* ]] && requested="$requested $a"
done
requested="${requested## }"
[[ -n "$requested" ]] || { react confused; exit 0; }

# Map suites -> workflow files to re-run (ci.yml covers all orchestrated suites).
workflows=""
for s in $requested; do
  if [[ " $ORCHESTRATED " == *" $s "* ]]; then wf="ci.yml"
  elif [[ "$s" == contrib ]]; then wf="contribution-checks.yml"
  else continue; fi
  [[ " $workflows " == *" $wf "* ]] || workflows="$workflows $wf"
done

sha="$(gh api "repos/$repo/pulls/$pr" --jq '.head.sha')"

# Re-run each affected workflow's latest pull_request run for this commit. A run
# still in progress can't be re-run, so wait briefly for it to finish.
any_rerun=false
for wf in $workflows; do
  for _ in $(seq 1 12); do
    read -r run_id status < <(
      gh api "repos/$repo/actions/workflows/$wf/runs?head_sha=$sha&event=pull_request&per_page=1" \
        --jq '.workflow_runs[0] | "\(.id // "") \(.status // "")"' 2>/dev/null || echo " "
    )
    [[ -z "$run_id" || "$status" != "completed" ]] && { sleep 5; continue; }
    gh api -X POST "repos/$repo/actions/runs/$run_id/rerun" >/dev/null 2>&1 && { any_rerun=true; break; }
    sleep 5
  done
  $any_rerun || echo "::warning::could not re-run $wf for ${sha:0:7} (no completed run yet)"
done

# React only after we know the outcome: rocket if something started, else
# confused (the API only adds reactions, so we must not react early).
$any_rerun && react rocket || react confused
