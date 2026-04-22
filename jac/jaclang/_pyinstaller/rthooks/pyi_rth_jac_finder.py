#
# PyInstaller runtime hook for jaclang.
#
# Frozen apps don't process ``.pth`` files, so the sovereign Python-level
# hijack installed by ``jaclang.pth`` / ``_jac_finder.install()`` on a normal
# machine never fires at frozen-app startup on its own. This rthook calls
# ``_jac_finder.install()`` explicitly, giving the frozen app the same
# meta-path + path-hook setup that unfrozen jaclang users get for free.
#
# Registered via ``rthooks.dat`` on the ``_jac_finder`` module name, which
# is always in the frozen app's module graph because it is a top-level
# py-module declared in jaclang's pyproject.toml.
#
import _jac_finder

_jac_finder.install()
