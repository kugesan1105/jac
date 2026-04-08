"""PyInstaller + Jac reproduction entry point.

This is the host Python program (same pattern as the jac-client sidecar).
It imports jaclang to register the .jac meta importer, then reaches into
a Jac-only package that has __init__.jac files but no __init__.py.
"""

import jaclang  # noqa: F401 — registers JacMetaImporter for .jac files

from myapp.core.greeter import greet


def main() -> None:
    print(greet("world"))


if __name__ == "__main__":
    main()
