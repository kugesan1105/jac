# PyInstaller + `__init__.jac` reproduction

Minimal harness to reproduce the bug PR #5466 works around — and a sandbox to
develop the proper fix (a PyInstaller hook that teaches `collect_all()` about
`.jac` files).

## Layout

```
myapp/                        <-- no __init__.py anywhere, only __init__.jac
├── __init__.jac
├── core/
│   ├── __init__.jac
│   └── greeter.jac           imports myapp.utils.helpers.shout
└── utils/
    ├── __init__.jac
    └── helpers.jac           defines shout
main.py                       Python host: imports jaclang, then myapp.core.greeter
build.sh                      PyInstaller build
apply_workaround.sh           drops empty __init__.py files (mirrors PR #5466)
unapply_workaround.sh         removes them
```

## Setup

```bash
python -m venv .venv
source .venv/bin/activate
pip install jaclang pyinstaller
```

## Step 1 — confirm Jac runtime is fine

```bash
python main.py
# → Hello, world!!!
```

Works because `import jaclang` registers `JacMetaImporter` at runtime, so
`.jac` files are found and `__init__.jac` is honored.

## Step 2 — reproduce the frozen-build failure

```bash
./build.sh
./dist/main/main
```

Expected:

```
ModuleNotFoundError: No module named 'myapp'
```

(or an error pointing at `myapp.core.greeter`, depending on how far
PyInstaller's static analysis got). Cause: PyInstaller scans the source tree
at build time using Python's own package rules — it doesn't know `.jac`
files exist, so `myapp/` looks like an empty namespace package (or nothing
at all), and `collect_all myapp` contributes nothing to the bundle.

## Step 3 — confirm the PR #5466 workaround fixes it

```bash
./apply_workaround.sh      # drops empty __init__.py beside every __init__.jac
./build.sh
./dist/main/main
# → Hello, world!!!
```

Then undo:

```bash
./unapply_workaround.sh
```

## Step 4 — what the proper fix looks like

Write a PyInstaller hook for `jaclang` that:

1. Registers `.jac` as a source extension PyInstaller will collect.
2. For any package PyInstaller analyses, if the directory contains an
   `__init__.jac`, treat it as a package and recurse into it.
3. Pulls in transitive `.jac` imports (parse the AST or hook into jaclang's
   own module resolver).

Hook discovery docs: <https://pyinstaller.org/en/stable/hooks.html>

The hook should live in `jaclang` itself (e.g. `jaclang/__pyinstaller/`)
and be advertised via the `pyinstaller40` entry point in its `pyproject.toml`,
so downstream projects like `jac-client` get it for free.

Once the hook works against this repro (Step 2 starts passing without
running `apply_workaround.sh`), the manual `__init__.py` scaffolding in
`jac-client` and `jac-scale` can be deleted.
