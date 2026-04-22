"""The Jac Programming Language."""

import sys

import _jac_finder

from jaclang.meta_importer import JacMetaImporter  # noqa: E402

# Register JacMetaImporter BEFORE loading plugins, so .jac modules can be imported
if not any(isinstance(f, JacMetaImporter) for f in sys.meta_path):
    sys.meta_path.insert(0, JacMetaImporter())

# Also activate the Python-level hijack: registers .jac as a first-class
# source suffix in importlib.machinery.SOURCE_SUFFIXES and installs a
# lightweight path-level loader. This makes every importlib-based tool
# (PyInstaller's analyzer, setuptools, Nuitka, IDE indexers) discover Jac
# packages with no per-tool adapters. Safe to call repeatedly — install()
# is idempotent and bails early if a Jac importer is already registered.
#
# Normally this runs at Python startup via jaclang.pth; we also call it
# from here so jaclang-triggered contexts (e.g. PyInstaller hook loading
# jaclang via an import) get the full hijack even when .pth hasn't fired
# (notably under PEP 660 editable installs).
_jac_finder.install()

# Import compiler first to ensure generated parsers exist before jac0core.parser is loaded
# Backwards-compatible import path for older plugins/tests.
# Prefer `jaclang.jac0core.runtime` going forward.
import jaclang.jac0core.runtime as _runtime_mod  # noqa: E402
from jaclang import compiler as _compiler  # noqa: E402, F401
from jaclang.jac0core.helpers import (  # noqa: E402
    get_disabled_plugins,
    load_plugins_with_disabling,
)
from jaclang.jac0core.runtime import (  # noqa: E402
    JacRuntime,
    JacRuntimeImpl,
    JacRuntimeInterface,
    plugin_manager,
)

sys.modules.setdefault("jaclang.runtimelib.runtime", _runtime_mod)

plugin_manager.register(JacRuntimeImpl)

# Load external plugins with disabling support
# Disabling can be configured via JAC_DISABLED_PLUGINS env var or jac.toml [plugins].disabled
# Use "*" to disable all external plugins, "package:*" for all from a package,
# or "package:plugin" for specific plugins
_disabled_list = get_disabled_plugins()
if _disabled_list:
    # Use qualified blocking for fine-grained control
    load_plugins_with_disabling(plugin_manager, _disabled_list)
else:
    # No disabling - load all plugins normally
    plugin_manager.load_setuptools_entrypoints("jac")

# Schedule deferred native acceleration if autonative is enabled in jac.toml
try:
    from jaclang.project.config import get_config as _get_jac_config

    _jac_cfg = _get_jac_config()
    if _jac_cfg and _jac_cfg.run.autonative:
        from jaclang.jac0core.native_accel import schedule_native_acceleration

        schedule_native_acceleration()
except Exception:
    pass  # Config not available or acceleration failed — continue normally

__all__ = ["JacRuntimeInterface", "JacRuntime"]
