#!/usr/bin/env bash
# Drops empty __init__.py alongside every __init__.jac — this is what PR #5466
# does by hand. Use it to confirm the workaround unbreaks the frozen build,
# then run unapply_workaround.sh to get back to the broken state while you
# work on a proper PyInstaller hook.
set -euo pipefail
cd "$(dirname "$0")"

find myapp -name '__init__.jac' -print0 | while IFS= read -r -d '' f; do
    py="${f%.jac}.py"
    if [[ ! -e "$py" ]]; then
        printf '"""Auto-added for PyInstaller static analysis."""\n' > "$py"
        echo "created $py"
    fi
done
