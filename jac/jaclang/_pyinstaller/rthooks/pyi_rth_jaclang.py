#
# PyInstaller runtime hook for jaclang.
#
# Runs at frozen-application startup, before the user's main script. Importing
# ``jaclang`` has the side effect of registering ``JacMetaImporter`` on
# ``sys.meta_path``, which is what allows subsequent ``import`` statements to
# resolve ``.jac`` modules bundled alongside the frozen app.
#
# Without this hook, a frozen app that imports a Jac module directly (without
# a preceding ``import jaclang`` in user code) would fail with
# ``ModuleNotFoundError`` — the runtime meta importer would never have been
# installed.
#
# Registration: this file is selected via ``jaclang/_pyinstaller/rthooks.dat``,
# which maps the ``jaclang`` module name to this script. Because the standard
# hook declares ``jaclang`` as a hidden import, the module is always present
# in the frozen app's module graph, and PyInstaller therefore always triggers
# this runtime hook at startup.
#

import jaclang  # noqa: F401  — side-effect import
