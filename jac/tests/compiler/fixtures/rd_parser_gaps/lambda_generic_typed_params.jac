"""Unparenthesized lambda params annotated with subscripted/generic types."""

import from typing { Optional }

with entry {
    a = lambda d: list[int] : d[0];
    print(a([1, 2]));

    b = lambda d: dict[str, int] : d["n"];
    print(b({"n": 2}));

    c = lambda x: int | str : x;
    print(c(3));

    d = lambda m: dict[str, list[int]], i: int : m["k"][i];
    print(d({"k": [4]}, 0));

    e = lambda x: list[int] = [5] : x[0];
    print(e());

    f = lambda t: tuple[int, ...] : t[0];
    print(f((6,)));

    g = lambda n: dict[str, dict[str, list[int]]] : n["a"]["b"][0];
    print(g({"a": {"b": [7]}}));

    h = lambda x: int | None : x;
    print(h(8));

    i = lambda x: Optional[int] : x;
    print(i(9));
}
