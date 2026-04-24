"""PyInstaller hooks for jaclang, wired via the ``pyinstaller40`` entry point."""

import os
import sys


def get_hook_dirs() -> list[str]:
    """Return hook dirs AND activate build-time .jac support.

    Runs at PyInstaller startup (before module graph analysis). Two side
    effects, both safe outside PyInstaller too:

    * install the ``.jac`` path-level loader so ``FileFinder`` recognizes
      ``__init__.jac`` as a package marker;
    * surface jaclang's source parent directory on ``sys.path`` — required
      under PEP 660 editable installs where jaclang is otherwise reachable
      only via ``sys.meta_path``.
    """
    import _jac_finder

    import jaclang

    _jac_finder._install_jac_path_hook()

    jaclang_parent = os.path.dirname(os.path.dirname(jaclang.__file__))
    if jaclang_parent and jaclang_parent not in sys.path:
        sys.path.insert(0, jaclang_parent)

    # One-line info log, mirrors what numpy/matplotlib hooks do. Makes CI
    # stderr prove whether this callback fired at all.
    print(
        f"jaclang._pyinstaller: get_hook_dirs ran "
        f"(jaclang={jaclang.__file__}, parent_on_path={jaclang_parent in sys.path})",
        file=sys.stderr,
        flush=True,
    )

    return [os.path.dirname(__file__)]
