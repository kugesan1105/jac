"""PyInstaller adapter — bundling translator only.

Discovery of Jac packages is handled *sovereignly* by ``_jac_finder`` via
``jaclang.pth`` at Python startup: ``.jac`` becomes a first-class source
suffix on ``importlib.machinery.SOURCE_SUFFIXES``, so PyInstaller's analyzer
finds Jac packages automatically with no hook-side help.

What this file still does, and only because bundling is a PyInstaller
invention (not a Python concept), is translate each discovered ``JacSource``
into a PyInstaller ``(src, dest_dir)`` data tuple so the ``.jac`` files are
physically copied into the frozen app's ``_internal/`` tree.
"""

import os
import sys

from PyInstaller.utils.hooks import collect_data_files, collect_submodules

from jaclang.packaging import find_packages

# ``_jac_finder`` must be in the graph so PyInstaller fires the rthook keyed
# on it (see rthooks.dat). It's a top-level py-module, not a jaclang submodule,
# so collect_submodules('jaclang') would not pick it up.
hiddenimports = ["_jac_finder"] + collect_submodules("jaclang")

datas: list[tuple[str, str]] = []

# Jaclang's own non-Python data files (.jac sources, .jir caches, grammars,
# .pyi stubs, precompiled manifest). We walk the package directly instead
# of using collect_data_files() because editable installs frequently fail
# to expose the full package-data globs via dist-info metadata.
import jaclang as _jaclang

_JACLANG_ROOT = os.path.dirname(_jaclang.__file__)
_DATA_EXTS = (".jac", ".jir", ".lark", ".pyi", ".json")
for _root, _, _files in os.walk(_JACLANG_ROOT):
    for _fname in _files:
        if _fname.endswith(_DATA_EXTS) or _fname == "manifest.json":
            _full = os.path.join(_root, _fname)
            _rel = os.path.relpath(_root, os.path.dirname(_JACLANG_ROOT))
            datas.append((_full, _rel))

# User Jac packages: any directory with __init__.jac reachable from cwd or
# sys.path. Sovereign discovery via jaclang.packaging — this adapter only
# does the (src, dest_dir) translation into PyInstaller's data-tuple format.
for _pkg in find_packages([os.getcwd()] + [p for p in sys.path if p and os.path.isdir(p)]):
    for _src in _pkg.iter_sources():
        datas.append((_src.path, os.path.dirname(_src.relative_path)))
