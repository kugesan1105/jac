"""A Python class defining BOTH `__init__` and an unrelated `init`.

The pyast loader rewrites Python `__init__` to Jac's `init`. Done
unconditionally it collapses these two distinct methods into one name and
trips the duplicate-method check. Python allows both, so importing this from
Jac must succeed. See run_py_dunder_init_and_init.jac.
"""


class PyCodec:
    def __init__(self, mode: str) -> None:
        self.mode = mode

    def init(self, args: list) -> None:
        self.args = args
