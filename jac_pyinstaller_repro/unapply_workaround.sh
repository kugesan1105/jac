#!/usr/bin/env bash
# Remove the empty __init__.py markers added by apply_workaround.sh
# so we are back to the broken (pre-fix) state.
set -euo pipefail
cd "$(dirname "$0")"

find myapp -name '__init__.py' -print0 | while IFS= read -r -d '' f; do
    rm -v "$f"
done
