"""PyInstaller + Jac reproduction entry point.

This is the host Python program (same pattern as the jac-client sidecar).
It reaches directly into a Jac-only package that has __init__.jac files but
no __init__.py — deliberately WITHOUT an explicit ``import jaclang`` — so
the runtime hook shipped by jaclang._pyinstaller is what has to register
JacMetaImporter before this import line executes.
"""

from myapp.core.greeter import greet


def main() -> None:
    print(greet("world"))


if __name__ == "__main__":
    main()
