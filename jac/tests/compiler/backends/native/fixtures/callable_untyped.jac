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

def note(seen: list[int], v: int) -> int {
    seen.append(v);
    return v;
}

def add(x: int, y: int = 3) -> int {
    return x + y;
}

def grow(x: int, acc: list[int] = []) -> int {
    acc.append(x);
    return len(acc);
}

def call_int(v: any) -> str {
    try {
        f: Callable = v;
        return str(f(1));
    } except TypeError {
        return "TypeError";
    }
}

def call_none_arg(seen: list[int]) -> str {
    f: any = None;
    try {
        f(note(seen, 7));
        return "called";
    } except TypeError {
        return "TypeError";
    }
}

def bad_arity -> int {
    fails = 0;
    for i in range(30) {
        try {
            adder(i)(1, 2);
        } except TypeError {
            fails += 1;
        }
    }
    return fails;
}

def nested_default(x: int, f: type = lambda (v: int, g: type = lambda (w: int) -> int { w + 100 }) -> int { g(v) }) -> int {
    return f(x);
}

def boom(x: int, acc: list[int] = []) -> int {
    acc.append(x);
    if x >= 0 {
        raise ValueError("no");
    }
    return len(acc);
}

def raising_default -> int {
    cb: any = boom;
    n = 0;
    for i in range(30) {
        try {
            cb(i);
        } except ValueError {
            n += 1;
        }
    }
    return n;
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
    seen: list[int] = [];
    print(via_bare(add, 4), via_bare(grow, 1), call_int(1), call_none_arg(seen), seen, bad_arity());
    print(nested_default(1), raising_default());
}

with entry {
    main();
    __rc_collect_cycles();
    __rc_debug_enable();
}
