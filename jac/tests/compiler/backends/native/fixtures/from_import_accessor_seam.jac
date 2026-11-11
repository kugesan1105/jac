"""Fixture: a `from`-import violation inside a property accessor.

A `{ getter; }` body is a callable the native lane lowers as a method, so the
violation is reported at the import inside the accessor.
"""

obj Box {
    has head: int = 7;
    has tagged: int { getter; }

    def plain -> int {
        return self.head + 1;
    }
}


impl Box.tagged.getter -> int {
    import from collections { OrderedDict }
    return self.head + len(OrderedDict());
}


def run -> int {
    return Box().plain();
}
