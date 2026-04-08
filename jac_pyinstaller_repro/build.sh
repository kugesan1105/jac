#!/usr/bin/env bash
# Build the frozen app with PyInstaller.
# Expected result (current state of jaclang): ModuleNotFoundError when running the
# frozen binary, because PyInstaller cannot see .jac files without an __init__.py
# to mark each directory as a real Python package.
set -euo pipefail

cd "$(dirname "$0")"

rm -rf build dist main.spec

# NOTE: we intentionally do NOT pass --collect-all myapp or --paths .
# The whole point is that `pyinstaller main.py` should discover myapp on its
# own, the same way it does for any normal Python package — the jaclang
# hook is what must teach PyInstaller how to follow .jac imports.
pyinstaller \
    --noconfirm \
    --onedir \
    --collect-all jaclang \
    main.py

echo
echo "Built. Run it with:"
echo "    ./dist/main/main"
