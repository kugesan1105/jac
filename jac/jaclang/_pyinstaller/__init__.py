"""PyInstaller hook package for jaclang.

Advertised via the ``pyinstaller40`` entry point in jaclang's pyproject.toml,
so PyInstaller auto-discovers these hooks whenever jaclang is importable in
the build environment — no ``--additional-hooks-dir`` flag required.

The hooks here teach PyInstaller about ``.jac`` source files so that Jac
packages can be bundled without manually adding empty ``__init__.py`` files
to every directory that has an ``__init__.jac`` (the workaround currently
used by jac-client and jac-scale).
"""

import os


def get_hook_dirs() -> list[str]:
    """Return the directories containing PyInstaller hooks shipped with jaclang."""
    return [os.path.dirname(__file__)]
