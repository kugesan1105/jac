"""Discover user Jac packages and report them as PyInstaller data entries.

PyInstaller's modulegraph analyzer treats anything we get past
``_jac_source_finder`` as a Python ``SourceModule`` — which compiles to bytecode
and lands in ``PYZ-00.pyz``, *discarding the original `.jac` source*. That's
not what we want: at runtime ``JacMetaImporter`` (registered when ``jaclang``
is imported) needs the actual ``.jac`` files reachable on ``sys.path`` so it
can compile them with the real Jac compiler.

This module provides the helpers that locate Jac packages on disk and emit
PyInstaller-style ``(src, dest)`` data tuples that copy each ``.jac`` file
into the frozen app's ``_internal/`` tree, preserving its package layout.
"""

from __future__ import annotations

import os
from typing import Iterable


_INIT_JAC = "__init__.jac"
_JAC_SUFFIX = ".jac"


def find_jac_package_roots(search_dirs: Iterable[str]) -> list[tuple[str, str]]:
    """Return ``(package_dir, package_name)`` for every top-level Jac package found.

    A "top-level Jac package" is a directory that:

    * is an immediate child of one of ``search_dirs``;
    * contains an ``__init__.jac`` file;
    * does **not** itself live inside another directory whose own
      ``__init__.jac`` we already collected (so nested subpackages aren't
      reported twice).

    Search-dir order is honored, and the same directory is never reported
    twice even if it appears under multiple roots.
    """
    found: list[tuple[str, str]] = []
    seen: set[str] = set()

    for raw_dir in search_dirs:
        if not raw_dir or not os.path.isdir(raw_dir):
            continue
        search_dir = os.path.abspath(raw_dir)

        try:
            entries = os.listdir(search_dir)
        except OSError:
            continue

        for entry in entries:
            full = os.path.join(search_dir, entry)
            if not os.path.isdir(full):
                continue
            if entry.startswith(".") or entry.startswith("_"):
                continue
            if not os.path.isfile(os.path.join(full, _INIT_JAC)):
                continue
            if full in seen:
                continue
            seen.add(full)
            found.append((full, entry))

    return found


def collect_jac_files(package_dir: str, package_name: str) -> list[tuple[str, str]]:
    """Return PyInstaller ``(src, dest_dir)`` tuples for every ``.jac`` file in a package.

    The destination preserves the package's directory layout so that the
    files end up at ``_internal/<pkg_name>/<...>/<file>.jac`` in the frozen
    app, exactly where ``JacMetaImporter`` will look for them at runtime.
    """
    package_dir = os.path.abspath(package_dir)
    parent_dir = os.path.dirname(package_dir)

    files: list[tuple[str, str]] = []
    for root, dirs, filenames in os.walk(package_dir):
        # Skip cache / hidden dirs (e.g. ``.jac/cache/``).
        dirs[:] = [d for d in dirs if not d.startswith(".")]

        rel_dir = os.path.relpath(root, parent_dir)
        for fname in filenames:
            if fname.endswith(_JAC_SUFFIX):
                files.append((os.path.join(root, fname), rel_dir))

    return files


def collect_user_jac_packages(search_dirs: Iterable[str]) -> list[tuple[str, str]]:
    """Convenience: find every top-level Jac package and emit data entries for all .jac files."""
    datas: list[tuple[str, str]] = []
    for pkg_dir, pkg_name in find_jac_package_roots(search_dirs):
        datas.extend(collect_jac_files(pkg_dir, pkg_name))
    return datas
