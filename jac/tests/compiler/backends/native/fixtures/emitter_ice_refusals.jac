"""String prefixes exercise a former emitter crash."""

obj Holder {
    has n: int = 0;
}


def tuple_startswith(s: str) -> int {
    if s.startswith(("'", '"')) {
        return 1;
    }
    return 0;
}


def plain_startswith(s: str) -> int {
    if s.startswith("r") {
        return 1;
    }
    return 0;
}


def takes_holder(h: Holder) -> int {
    return h.n;
}
