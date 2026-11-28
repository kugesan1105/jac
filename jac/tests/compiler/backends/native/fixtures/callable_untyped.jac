"""Calling function and class values whose type carries no call signature."""

obj Thing {
    has key: str = "",
        n: int = 1;
}

obj Formatter {
    has fmt: type = lambda (s: str) -> str { s.upper() + "!" };

    def apply(msg: str) -> str {
        return self.fmt(msg);
    }
}

def via_any(x: int) -> int {
    f: any = lambda (v: int) -> int { v + 1 };
    return f(x);
}

def via_bare(f: Callable, x: int) -> int {
    return f(x);
}

def via_default(x: int, f: type = lambda (v: int) -> int {
    y = v * 2;
    return y + 1;
}) -> int {
    return f(x);
}

def via_ellipsis(f: Callable[..., int], x: int) -> int {
    return f(x);
}

def adder(n: int) -> any {
    return lambda (v: int) -> int { v + n };
}

def make(factory: any, k: str) -> any {
    return factory(k);
}

def make_typed(factory: type, k: str, n: int) -> any {
    return factory(k, n);
}

def outcome(f: any, args: list[int]) -> str {
    try {
        if len(args) == 1 {
            return str(f(args[0]));
        }
        return str(f(args[0], args[1]));
    } except TypeError {
        return "TypeError";
    }
}

def main {
    total = 0;
    for i in range(20) {
        total += via_any(i) + via_default(i) + adder(i)(1);
        t: Thing = make(Thing, "k" + str(i));
        total += len(t.key);
    }
    u: Thing = make_typed(Thing, "u", 5);
    print(total, via_bare(lambda (v: int) -> int { v - 1 }, 5), via_ellipsis(lambda (v: int) -> int { v + 10 }, 1));
    print(Formatter().apply("hi"), u.key, u.n);
    inc: any = lambda (v: int) -> int { v + 1 };
    print(outcome(inc, [1]), outcome(inc, [1, 2]), outcome(None, [1]), outcome(5, [1]), outcome("Thing", [1]));
}

with entry {
    main();
    __rc_collect_cycles();
    __rc_debug_enable();
}
