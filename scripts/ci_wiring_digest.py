"""Print archwire.jac's share of the compiler identity for the CI cache key.

Reads package-relative compiler input paths on stdin and prints
jac0.compiler_wiring_digest, the function jir.compiler_source_digest uses, so
the CI key and the compiler digest agree on which wire edits matter. jac0.py
is pure Python, so this runs before any jac binary exists.
"""

import importlib.util
import os
import sys


def main() -> int:
    pkg_dir = sys.argv[1]
    spec = importlib.util.spec_from_file_location(
        "jac0_ci_keys", os.path.join(pkg_dir, "jac0.py")
    )
    if spec is None or spec.loader is None:
        return 1
    jac0 = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = jac0
    spec.loader.exec_module(jac0)
    rels = [line.strip() for line in sys.stdin if line.strip()]
    sys.stdout.write(jac0.compiler_wiring_digest(pkg_dir, rels) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
