"""PyInstaller hooks for jaclang, wired via the ``pyinstaller40`` entry point."""

import os


def get_hook_dirs() -> list[str]:
    """Return the hook directory and activate ``.jac`` path-based discovery.

    PyInstaller calls this at startup. We install the ``FileFinder`` loader
    that makes ``__init__.jac`` a recognized package marker — this is what
    lets the analyzer see Jac subpackages of jaclang (and user projects)
    without needing empty ``__init__.py`` scaffolding.

    Note: PyInstaller snapshots its ``pathex`` from ``sys.path`` *before*
    this callback fires, so we cannot surface jaclang's source directory
    from here. Under a PEP 660 editable install (``pip install -e``),
    jaclang lives only on ``sys.meta_path`` and users must pass
    ``--paths <jaclang_parent>`` or set ``PYTHONPATH`` at the CLI.
    Wheel-installed jaclang is already on ``sys.path`` via site-packages
    and needs no extra flags.
    """
    import _jac_finder

    _jac_finder._install_jac_path_hook()

    return [os.path.dirname(__file__)]
