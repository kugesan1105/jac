"""Teach PyInstaller's analyzer that ``.jac`` is a source file extension.

This module is imported (for its side effects) by ``hook-jaclang.py`` at
PyInstaller hook-load time, which runs before the analyzer walks the user's
import graph.

Background
----------
PyInstaller decides what to bundle by statically analyzing imports. It uses
``importlib`` machinery — specifically ``FileFinder`` instances built from
``importlib.machinery.SOURCE_SUFFIXES`` — to locate modules on disk. By
default that list contains only ``.py``, so a ``from myapp.core.greeter
import greet`` statement looks for ``greeter.py``, never finds ``greeter.jac``,
and the whole ``myapp`` package gets excluded from the bundle. At runtime
the frozen app then crashes with ``ModuleNotFoundError`` because the files
were never copied in.

Strategy
--------
1. Define a ``_JacAnalysisLoader`` (subclass of ``SourceFileLoader``) that
   PyInstaller can use to "load" a ``.jac`` file at analysis time. We never
   actually execute Jac source as Python — instead, ``source_to_code`` returns
   a synthetic Python code object whose only purpose is to advertise the
   module's transitive Jac imports so PyInstaller's modulegraph follows them.
2. Register that loader against the ``.jac`` suffix by patching
   ``importlib._bootstrap_external._get_supported_file_loaders``.
3. Replace the existing ``FileFinder`` path hook in ``sys.path_hooks`` with
   a new one constructed from the patched loader list, and flush the
   importer cache so cached finders are rebuilt.

At runtime, the analysis-time loader is irrelevant: the runtime hook
imports ``jaclang``, which installs ``JacMetaImporter`` on
``sys.meta_path`` ahead of the user's ``main`` script. ``JacMetaImporter``
then handles the real compile-and-load using the ``.jac`` files we
arranged to be bundled.
"""

from __future__ import annotations

import importlib._bootstrap_external as _bs_ext
import importlib.machinery
import os
import sys
from importlib.machinery import FileFinder, SourceFileLoader


_JAC_SUFFIX = ".jac"


class _JacAnalysisLoader(SourceFileLoader):
    """SourceFileLoader specialization that fakes Python source for ``.jac`` files.

    PyInstaller's modulegraph reads each module's source via
    ``loader.get_source(name)`` and then ``compile()``s the result directly
    (see ``_load_module`` in PyInstaller's modulegraph.py). Jac syntax
    obviously won't compile as Python, so we override ``get_source`` to
    return synthetic Python whose import graph mirrors the Jac module's
    real dependencies. The synthetic code is never executed; at runtime
    the real ``.jac`` file is handled by ``JacMetaImporter``.
    """

    def get_source(self, fullname: str) -> str | None:  # type: ignore[override]
        path = self.get_filename(fullname)
        if not path.endswith(_JAC_SUFFIX):
            return super().get_source(fullname)
        return self._synthesize_python_for(path)

    # ------------------------------------------------------------------ helpers

    def _synthesize_python_for(self, path: str) -> str:
        """Return Python source whose import graph mirrors this .jac file's needs.

        For now we use a coarse but reliable strategy: when the loader is
        asked about a package's ``__init__.jac``, we walk the package
        directory and emit one ``import`` statement per ``.jac`` module we
        find. That guarantees every ``.jac`` file in the package ends up
        in the bundle, without us needing a real Jac import parser.

        For non-``__init__`` ``.jac`` files we emit nothing — the
        package-level walk has already covered them.
        """
        basename = os.path.basename(path)
        if basename != "__init__" + _JAC_SUFFIX:
            return ""

        pkg_name = self.name  # SourceFileLoader stores fullname here
        pkg_dir = os.path.dirname(path)

        lines: list[str] = []
        for root, dirs, files in os.walk(pkg_dir):
            # Skip hidden caches like .jac/cache/
            dirs[:] = [d for d in dirs if not d.startswith(".")]

            rel = os.path.relpath(root, pkg_dir)
            if rel == ".":
                mod_prefix = pkg_name
            else:
                mod_prefix = pkg_name + "." + rel.replace(os.sep, ".")

            for fname in files:
                if not fname.endswith(_JAC_SUFFIX):
                    continue
                if fname == "__init__" + _JAC_SUFFIX:
                    # __init__ for the current dir — only register subpackages,
                    # which we handle via the directory walk itself, not by
                    # importing __init__.
                    continue
                stem = fname[: -len(_JAC_SUFFIX)]
                lines.append(f"import {mod_prefix}.{stem}")

        return "\n".join(lines) + ("\n" if lines else "")


_JAC_LOADER_DETAILS = (_JacAnalysisLoader, [_JAC_SUFFIX])


def install() -> None:
    """Idempotently install the .jac analysis loader into importlib + sys.path_hooks."""
    _patch_get_supported_file_loaders()
    _replace_filefinder_path_hook()
    sys.path_importer_cache.clear()


# ---------------------------------------------------------------- internals


def _patch_get_supported_file_loaders() -> None:
    """Make ``_get_supported_file_loaders`` include our Jac loader.

    PyInstaller and importlib both call this private function whenever they
    construct a fresh ``FileFinder``. By inserting our entry, every new
    finder gains the ability to recognize ``.jac`` files.
    """
    original = getattr(_bs_ext, "_get_supported_file_loaders")
    if getattr(original, "_jaclang_patched", False):
        return

    def patched() -> list[tuple[type, list[str]]]:
        loaders = original()
        if not any(cls is _JacAnalysisLoader for cls, _ in loaders):
            # Put .jac handling ahead of the standard SourceFileLoader so
            # there is never any ambiguity about who claims a .jac suffix.
            loaders.insert(0, _JAC_LOADER_DETAILS)
        return loaders

    patched._jaclang_patched = True  # type: ignore[attr-defined]
    _bs_ext._get_supported_file_loaders = patched  # type: ignore[assignment]


def _replace_filefinder_path_hook() -> None:
    """Swap the cached ``FileFinder.path_hook`` for one built from the patched loaders.

    The default path hook captures its loader list at construction time, so
    appending to ``SOURCE_SUFFIXES`` after Python startup has no effect on it.
    We rebuild the hook from scratch and substitute it in place inside
    ``sys.path_hooks``.
    """
    new_hook = FileFinder.path_hook(*_bs_ext._get_supported_file_loaders())

    replaced = False
    for i, hook in enumerate(list(sys.path_hooks)):
        if getattr(hook, "__name__", "") == "path_hook_for_FileFinder":
            sys.path_hooks[i] = new_hook
            replaced = True
            break

    if not replaced:
        sys.path_hooks.insert(0, new_hook)

    # Also keep ``importlib.machinery.SOURCE_SUFFIXES`` in sync. Some tools
    # (including parts of PyInstaller's introspection) read it directly.
    if _JAC_SUFFIX not in importlib.machinery.SOURCE_SUFFIXES:
        importlib.machinery.SOURCE_SUFFIXES.append(_JAC_SUFFIX)
