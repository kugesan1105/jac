"""Jac package discovery and (future) bundling — a sovereign jaclang capability.

Public API for locating Jac packages on disk and enumerating their ``.jac``
sources, independent of any specific bundler or packaging tool. Adapters
(e.g. ``jaclang._pyinstaller``) and the future ``jac build`` pipeline both
consume this module; neither one owns the logic.
"""

from jaclang.packaging.discovery import JacPackage, JacSource, find_packages

__all__ = ["JacPackage", "JacSource", "find_packages"]
