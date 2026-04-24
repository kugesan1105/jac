"""PyInstaller adapter — datas + hiddenimports for jaclang and user Jac packages.

The path-level ``.jac`` hook and the PEP 660 sys.path workaround are set up
earlier, in ``jaclang._pyinstaller.get_hook_dirs`` — by the time this hook
fires, jaclang is fully reachable via PyInstaller's path-based analyzer.
"""

import os
import sys

from PyInstaller.utils.hooks import collect_submodules

from jaclang.packaging import iter_jaclang_data_files, iter_user_jac_sources


def _search_dirs() -> list[str]:
    """cwd + sys.argv script/spec paths + sys.path dirs (existing dirs only)."""
    dirs = [os.getcwd()]
    for arg in sys.argv:
        if not arg or arg.startswith("-"):
            continue
        p = os.path.abspath(arg)
        if os.path.isfile(p):
            dirs.append(os.path.dirname(p))
        elif os.path.isdir(p):
            dirs.append(p)
    dirs.extend(p for p in sys.path if p and os.path.isdir(p))
    return dirs


_dirs = _search_dirs()
_user_datas = list(iter_user_jac_sources(_dirs))

_diag = (
    f"[jaclang._pyinstaller] hook: cwd={os.getcwd()!r} "
    f"search_dirs={_dirs} user_jac_sources={len(_user_datas)}"
)
print(_diag, file=sys.stderr, flush=True)
# Also drop a breadcrumb into cwd so tests (and users debugging in CI) can
# see what the hook saw without having to capture PyInstaller's full stderr.
try:
    with open(os.path.join(os.getcwd(), "_jac_pyi_hook_diag.txt"), "w") as _f:
        _f.write(_diag + "\n")
except OSError:
    pass

hiddenimports = ["_jac_finder"] + collect_submodules("jaclang")
datas = list(iter_jaclang_data_files()) + _user_datas
