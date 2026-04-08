"""PyInstaller standard hook for jaclang itself.

Runs when PyInstaller's analyzer encounters ``import jaclang``. Its job is to
bundle jaclang's own runtime into the frozen application:

* All Python submodules (so ``collect_all``-style discovery works).
* The vendored ``.jac`` sources and pre-compiled ``.jir`` caches that
  jaclang compiles on first use — without these, the frozen app
  re-triggers the "Setting up Jac for first use" compile on every launch,
  and in some cases fails outright because source-only dirs are missing.
* Data files flagged via ``package-data`` in jaclang's pyproject.toml.
"""

import os
import sys

from PyInstaller.utils.hooks import collect_data_files, collect_submodules

# Side-effect import: register the .jac source loader inside importlib so the
# rest of PyInstaller's analysis can discover .jac files in user packages.
# This must run before modulegraph processes any user imports — hook-load time
# is the right moment.
from jaclang._pyinstaller import _jac_source_finder, jac_packages

_jac_source_finder.install()

# Python submodules that import-graph walking might miss (plugin entry points,
# lazy imports inside runtimelib, etc.).
hiddenimports = collect_submodules("jaclang")

# Everything that is NOT a .py file: .jac sources, .jir caches, .lark grammar,
# .pyi stubs, the precompiled manifest, sitecustomize.py, etc.
# include_py_files=False because hiddenimports already covers Python modules.
datas = collect_data_files("jaclang", include_py_files=False)

# Auto-discover the user's Jac packages by scanning the build cwd and sys.path
# for directories that contain ``__init__.jac``. Each such directory is the root
# of a Jac package whose entire ``.jac`` tree we copy verbatim into the bundle,
# preserving its layout under the package name. JacMetaImporter then finds the
# files at runtime via ``sys.path``.
#
# This is the load-bearing piece — without these data entries, the .jac files
# never reach the frozen app and ``JacMetaImporter`` has nothing to import.
_search_roots = [os.getcwd()] + [p for p in sys.path if p and os.path.isdir(p)]
datas += jac_packages.collect_user_jac_packages(_search_roots)
