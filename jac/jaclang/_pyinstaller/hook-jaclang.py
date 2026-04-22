"""PyInstaller adapter for jaclang.

Thin shim between PyInstaller's hook protocol and jaclang's sovereign
packaging API (``jaclang.packaging``). This file does two things only:

1. tell PyInstaller how to bundle jaclang itself (standard ``collect_*``);
2. translate ``JacPackage`` / ``JacSource`` objects from
   ``jaclang.packaging.find_packages`` into PyInstaller's ``datas`` tuple
   format ``(abs_src_path, relative_dest_dir)``.

All real logic — "what counts as a Jac package", "how do I walk its
sources" — lives in ``jaclang.packaging``. When the native ``jac build``
pipeline lands, it will consume the same API; this adapter then becomes a
compatibility layer for existing PyInstaller-based deployments.
"""

import os
import sys

from PyInstaller.utils.hooks import collect_data_files, collect_submodules

from jaclang.packaging import find_packages

hiddenimports = collect_submodules("jaclang")

datas = collect_data_files("jaclang", include_py_files=False)

# Discover user Jac packages via the Jac-native API, then translate each
# discovered source file into PyInstaller's (src, dest_dir) data tuple.
_search_dirs = [os.getcwd()] + [p for p in sys.path if p and os.path.isdir(p)]
for _pkg in find_packages(_search_dirs):
    for _src in _pkg.iter_sources():
        datas.append((_src.path, os.path.dirname(_src.relative_path)))
