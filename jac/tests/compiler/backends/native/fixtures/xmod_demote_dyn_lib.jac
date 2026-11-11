"""Fixture: a lowering failure only the backend's emitter discovers.

`from_code` invokes `Hue` as a constructor with a floating-point argument. No
AST-level capability check refuses it; native integer-enum construction does
not coerce floats to integers, so the emitter reports E5092 at the call.
"""

enum Hue { RED = 1, GREEN = 2 }

def from_code(x: str) -> int {
    h = Hue(float(x));
    return len(x) if h is not None else 0;
}

def double(x: int) -> int {
    return x * 2;
}

with entry {
    print(double(3));
}
