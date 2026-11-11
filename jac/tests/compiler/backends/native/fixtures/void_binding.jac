"""Fixture: each `*_caller` uses the result of a call returning None as a value.

Native lowers that call to `void`, so the caller is a located E5092 error
instead of crashing or inventing a value (#7139).
"""

obj Sink {
    def annotated -> None {
        return;
    }
}

def sink(x: int) -> None {
    return;
}

def caller(x: int) -> int {
    y = sink(x);
    return x;
}

def method_caller(s: Sink) -> int {
    y = s.annotated();
    return 1;
}
