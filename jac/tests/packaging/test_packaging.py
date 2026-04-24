"""Tests for jaclang.packaging + the PyInstaller hook end-to-end.

Unit tests run unconditionally (~50 ms). The integration test requires
PyInstaller and is skipped otherwise (~30-60 s cold build).
"""

from __future__ import annotations

import os
import subprocess
import sys
import textwrap
from pathlib import Path

import pytest

from jaclang.packaging import iter_jaclang_data_files, iter_user_jac_sources


def _mk(path: Path, body: str = "") -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(body)


def test_iter_user_jac_sources_filters_correctly(tmp_path: Path) -> None:
    for rel in [
        "myapp/__init__.jac",
        "myapp/core/__init__.jac",
        "myapp/core/greeter.jac",
        "myapp/notes.txt",
        "myapp/.cache/stale.jac",
    ]:
        _mk(tmp_path / rel)
    _mk(tmp_path / ".hidden" / "__init__.jac")
    _mk(tmp_path / "_priv" / "__init__.jac")
    _mk(tmp_path / "pyonly" / "__init__.py")

    got = list(
        iter_user_jac_sources([str(tmp_path), str(tmp_path), "", "/nonexistent"])
    )
    srcs = [s for s, _ in got]

    assert len(got) == 3
    assert all(s.endswith(".jac") for s in srcs)
    assert not any(
        seg in s for s in srcs for seg in (".hidden", ".cache", "_priv", "pyonly")
    )


def test_iter_jaclang_data_files_includes_modresolver() -> None:
    """Regression guard: modresolver.jac is load-bearing for frozen-app bootstrap."""
    import jaclang

    root = os.path.dirname(jaclang.__file__)
    files = list(iter_jaclang_data_files())
    assert files
    assert all(p.startswith(root) for p, _ in files)
    assert all(rel.split(os.sep, 1)[0] == "jaclang" for _, rel in files)
    assert any(
        p.endswith(os.path.join("jac0core", "modresolver.jac")) for p, _ in files
    )


_FIXTURE = {
    "myapp/__init__.jac": "",
    "myapp/core/__init__.jac": "",
    "myapp/utils/__init__.jac": "",
    "myapp/utils/helpers.jac": 'def shout(msg: str) -> str { return msg + "!!!"; }\n',
    "myapp/core/greeter.jac": textwrap.dedent("""\
        import from myapp.utils.helpers { shout }
        def greet(name: str) -> str { return shout(f"Hello, {name}"); }
    """),
    "main.py": textwrap.dedent("""\
        import jaclang  # noqa: F401
        from myapp.core.greeter import greet
        if __name__ == "__main__":
            print(greet("world"))
    """),
}


def test_frozen_app_runs_jac_only_package(tmp_path: Path) -> None:
    pytest.importorskip("PyInstaller")

    for rel, body in _FIXTURE.items():
        _mk(tmp_path / rel, body)

    # Put tmp_path on PYTHONPATH so the hook's sys.path walk finds myapp even
    # in environments where os.getcwd() / sys.argv inside PyInstaller's
    # analyzer don't surface the project root reliably (seen under pytest-xdist).
    import os as _os

    env = {
        **_os.environ,
        "PYTHONPATH": str(tmp_path) + _os.pathsep + _os.environ.get("PYTHONPATH", ""),
    }

    build = subprocess.run(
        [
            sys.executable,
            "-m",
            "PyInstaller",
            "--noconfirm",
            "--onedir",
            "--collect-all",
            "jaclang",
            "--distpath",
            str(tmp_path / "dist"),
            "--workpath",
            str(tmp_path / "build"),
            "--specpath",
            str(tmp_path),
            str(tmp_path / "main.py"),
        ],
        cwd=tmp_path,
        capture_output=True,
        text=True,
        env=env,
    )
    assert build.returncode == 0, build.stderr

    internal = tmp_path / "dist/main/_internal"
    bundled = (
        list((internal / "myapp").rglob("*.jac"))
        if (internal / "myapp").exists()
        else []
    )
    diag = tmp_path / "_jac_pyi_hook_diag.txt"
    assert len(bundled) >= 5, (
        f"myapp not bundled (got {len(bundled)} .jac files).\n"
        f"tmp_path exists={tmp_path.exists()} "
        f"myapp exists={(tmp_path / 'myapp').exists()} "
        f"__init__.jac exists={(tmp_path / 'myapp/__init__.jac').exists()}\n"
        f"_internal contents: {sorted(p.name for p in internal.iterdir()) if internal.exists() else 'MISSING'}\n"
        f"hook diag: {diag.read_text() if diag.exists() else '<not written>'}\n"
        f"--- pyinstaller stderr tail ---\n{build.stderr[-4000:]}"
    )

    run = subprocess.run(
        [str(tmp_path / "dist/main/main")],
        cwd="/",
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert run.returncode == 0, run.stderr
    assert "Hello, world!!!" in run.stdout
