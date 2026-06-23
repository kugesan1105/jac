from __future__ import annotations
rows: list[dict] = [{'n': 2}, {'n': 1}]
a = sorted(rows, key=lambda d: d['n'])



f = lambda d: d.get("n", 0)
print(f(rows[0]))


# -- Lambda param inference: where the param type comes from --------------
from typing import Callable

nums: list[int] = [3, 1, 2]

# 1. Inferred from the call argument (iterable element -> key param).
by_neg = sorted(nums, key=lambda x: -x)

# 2. Operator / subscript / method bodies resolve on the inferred param.
rows2: list[dict[str, int]] = [{"n": 2}, {"n": 1}]
by_n_plus = sorted(rows2, key=lambda d: d["n"] + 1)   # d: dict[str, int]
words: list[str] = ["bb", "a"]
by_upper = sorted(words, key=lambda s: s.upper())     # s: str

# 3. Inferred from a Callable-typed variable (expected type flows in).
inc: Callable[[int], int] = lambda x: x + 1           # x: int

# 4. Python lambdas cannot annotate params (no `lambda x: int: ...` form);
#    Jac adds that. Use a def when you need an explicit annotation in Python.

# 5. No context: x stays Unknown to a type checker (no error; surfaces on use).
bare = lambda x: x

print(by_neg, by_n_plus, by_upper, inc(4), bare(9))

