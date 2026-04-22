"""PyInstaller adapter — pure translation into PyInstaller's datas/hiddenimports shape.

All real logic lives in ``jaclang.packaging``:

* ``iter_jaclang_data_files()`` — enumerate jaclang's own non-Python runtime
  assets (``.jac`` / ``.jir`` / ``.lark`` / ``.pyi``).
* ``find_packages(dirs)`` — discover user Jac packages (directories with
  ``__init__.jac``) under ``cwd`` + ``sys.path``.

This file's only job is to rename those sovereign concepts into the
PyInstaller-shaped tuples ``datas`` and ``hiddenimports``. Adding
``_jac_finder`` to hidden imports is what makes PyInstaller pull our
runtime hook (keyed on ``_jac_finder`` in ``rthooks.dat``) into the
frozen app's startup chain.
"""

import os
import sys

import _jac_finder
from PyInstaller.utils.hooks import collect_submodules

from jaclang.packaging import find_packages, iter_jaclang_data_files

# Activate the path-level .jac hook now, while PyInstaller's analyzer is
# about to start walking imports. Doing it here (rather than from
# jaclang/__init__.py or jaclang.pth) keeps the hook confined to the
# build-time process — pytest's assertion rewriter and similar tooling
# that iterate importlib suffixes never see ``.jac`` at runtime.
_jac_finder._install_jac_path_hook()

hiddenimports = ["_jac_finder"] + collect_submodules("jaclang")

datas = list(iter_jaclang_data_files())


def _user_project_search_dirs() -> list[str]:
    """Assemble every directory where the user's Jac packages might live.

    ``os.getcwd()`` alone isn't reliable inside PyInstaller's analyzer —
    some invocation styles (spec-file builds, CI wrappers) leave the
    subprocess CWD pointing at PyInstaller's own workdir, not the user's
    project root. We union in every non-flag entry of ``sys.argv`` (the
    main script / spec file) and every real directory on ``sys.path``, so
    we catch the project root regardless of how PyInstaller was launched.
    """
    dirs: list[str] = [os.getcwd()]

    for arg in sys.argv:
        if not arg or arg.startswith("-"):
            continue
        abs_arg = os.path.abspath(arg)
        if os.path.isfile(abs_arg):
            dirs.append(os.path.dirname(abs_arg))
        elif os.path.isdir(abs_arg):
            dirs.append(abs_arg)

    dirs.extend(p for p in sys.path if p and os.path.isdir(p))
    return dirs


for _pkg in find_packages(_user_project_search_dirs()):
    for _src in _pkg.iter_sources():
        datas.append((_src.path, os.path.dirname(_src.relative_path)))
