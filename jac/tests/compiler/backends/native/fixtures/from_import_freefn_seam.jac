"""Fixture: a `from`-import violation inside one free function, sibling clean.

`pyonly` names `collections.OrderedDict` through a body-scoped `from` import,
which is reported at that import; `clean` has no violation.
"""

def clean(x: int) -> int {
    return x + 1;
}

def pyonly(x: int) -> int {
    import from collections { OrderedDict }
    d = OrderedDict();
    return x + len(d);
}

with entry {
    print(clean(4));
}
