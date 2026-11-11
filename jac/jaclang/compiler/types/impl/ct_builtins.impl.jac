impl ct_method_owner(v: CtValue) -> str {
    if isinstance(v, CtBool) {
        return "int";
    }
    if isinstance(v, CtSet) {
        return "frozenset" if v.frozen else "set";
    }
    return ct_type_name(v);
}

impl ct_has_method(v: CtValue, name: str) -> bool {
    owner = ct_method_owner(v);
    return owner in CT_METHODS and name in CT_METHODS[owner];
}

impl _arity(
    fname: str,
    args: list[CtValue],
    kwargs: dict[str, CtValue],
    names: list[str],
    required: int
) -> list[CtValue] {
    slots: list[CtValue] = [];
    for _ in names {
        slots.append(CT_ABSENT);
    }
    if len(args) > len(names) {
        raise ct_exc(
            "TypeError",
            f"{fname}() takes at most {len(names)} arguments ({len(args)} given)"
        );
    }
    for (i, a) in enumerate(args) {
        slots[i] = a;
    }
    for (k, v) in kwargs.items() {
        if k not in names {
            raise ct_exc(
                "TypeError", f"{fname}() got an unexpected keyword argument '{k}'"
            );
        }
        idx = names.index(k);
        if slots[idx] is not CT_ABSENT {
            raise ct_exc(
                "TypeError", f"{fname}() got multiple values for argument '{k}'"
            );
        }
        slots[idx] = v;
    }
    for i in range(required) {
        if slots[i] is CT_ABSENT {
            raise ct_exc(
                "TypeError",
                f"{fname}() missing required argument '{names[i]}' (pos {i + 1})"
            );
        }
    }
    return slots;
}

impl _one_arg(fname: str, args: list[CtValue], kwargs: dict[str, CtValue]) -> CtValue {
    if kwargs {
        raise ct_exc("TypeError", f"{fname}() takes no keyword arguments");
    }
    if len(args) != 1 {
        raise ct_exc(
            "TypeError", f"{fname}() takes exactly one argument ({len(args)} given)"
        );
    }
    return args[0];
}

impl _no_args(fname: str, args: list[CtValue], kwargs: dict[str, CtValue]) {
    if args or kwargs {
        raise ct_exc(
            "TypeError",
            f"{fname}() takes no arguments ({len(args) + len(kwargs)} given)"
        );
    }
}

impl _as_index(v: CtValue) -> CtInt {
    iv = as_ct_int(v);
    if iv is None {
        raise ct_exc(
            "TypeError",
            f"'{ct_type_name(v)}' object cannot be interpreted as an integer"
        );
    }
    return iv;
}

impl _as_small(v: CtValue) -> int {
    iv = _as_index(v);
    if iv.value > CT_INDEX_MAX or iv.value < -CT_INDEX_MAX - 1 {
        raise ct_exc("OverflowError", "Python int too large to convert to C ssize_t");
    }
    return iv.value;
}

impl _opt_small(v: CtValue) -> (int | None) {
    if isinstance(v, CtNone) {
        return None;
    }
    return _as_small(v);
}

impl _as_str(v: CtValue, prefix: str) -> str {
    if not isinstance(v, CtStr) {
        raise ct_exc("TypeError", prefix + ct_type_name(v));
    }
    return v.value;
}

impl _opt_str(v: CtValue, what: str) -> (str | None) {
    if isinstance(v, CtNone) {
        return None;
    }
    return _as_str(v, what);
}

impl _str_list(items: list[str]) -> CtList {
    return mk_list([mk_str(x) for x in items]);
}

impl ct_sort(
    ev: CtCaller, items: list[CtValue], key: (CtValue | None), reverse: bool
) -> list[CtValue] {
    keys: list[CtValue] = [];
    for item in items {
        if key is None or isinstance(key, CtNone) {
            keys.append(item);
        } else {
            keys.append(ev.call_value(key, [item], {}));
        }
    }
    idxs: list[int] = list(range(len(items)));
    if reverse {
        idxs.reverse();
    }
    n = len(idxs);
    if n >= 2 {
        run = 1;
        if ct_lt(keys[idxs[1]], keys[idxs[0]]) {
            run = 2;
            while run < n and ct_lt(keys[idxs[run]], keys[idxs[run - 1]]) {
                run += 1;
            }
            head = idxs[:run];
            head.reverse();
            idxs = head + idxs[run:];
        } else {
            run = 2;
            while run < n and not ct_lt(keys[idxs[run]], keys[idxs[run - 1]]) {
                run += 1;
            }
        }
        for start in range(run, n) {
            pivot = idxs[start];
            lo = 0;
            hi = start;
            while lo < hi {
                mid = lo + ((hi - lo) >> 1);
                if ct_lt(keys[pivot], keys[idxs[mid]]) {
                    hi = mid;
                } else {
                    lo = mid + 1;
                }
            }
            idxs.pop(start);
            idxs.insert(lo, pivot);
        }
    }
    if reverse {
        idxs.reverse();
    }
    return [items[i] for i in idxs];
}

impl _minmax(
    ev: CtCaller, fname: str, args: list[CtValue], kwargs: dict[str, CtValue]
) -> CtValue {
    key: (CtValue | None) = None;
    dflt: (CtValue | None) = None;
    for (k, v) in kwargs.items() {
        if k == "key" {
            key = v;
        } elif k == "default" {
            dflt = v;
        } else {
            raise ct_exc(
                "TypeError", f"{fname}() got an unexpected keyword argument '{k}'"
            );
        }
    }
    if not args {
        raise ct_exc("TypeError", f"{fname} expected at least 1 argument, got 0");
    }
    if len(args) > 1 and dflt is not None {
        raise ct_exc(
            "TypeError",
            f"Cannot specify a default for {fname}() with multiple positional arguments"
        );
    }
    seq = ct_iter(args[0]) if len(args) == 1 else args;
    best: (CtValue | None) = None;
    best_key: (CtValue | None) = None;
    op = "<" if fname == "min" else ">";
    for item in seq {
        kv = item
            if key is None or isinstance(key, CtNone)
            else ev.call_value(key, [item], {});
        if best_key is None {
            best = item;
            best_key = kv;
        } elif ct_order(op, kv, best_key) {
            best = item;
            best_key = kv;
        }
    }
    if best is None {
        if dflt is not None {
            return dflt;
        }
        raise ct_exc("ValueError", f"{fname}() iterable argument is empty");
    }
    return best;
}

impl _sum(args: list[CtValue], kwargs: dict[str, CtValue]) -> CtValue {
    slots = _arity("sum", args, kwargs, ["iterable", "start"], 1);
    items = ct_iter(slots[0]);
    result: CtValue = slots[1] if slots[1] is not CT_ABSENT else mk_int(0);
    if isinstance(result, CtStr) {
        raise ct_exc("TypeError", "sum() can't sum strings [use ''.join(seq) instead]");
    }
    if isinstance(result, CtBytes) {
        raise ct_exc("TypeError", "sum() can't sum bytes [use b''.join(seq) instead]");
    }
    i = 0;
    start = ct_py_number(result);
    if start is not None {
        nums: list[(bool | int | float)] = [];
        while i < len(items) {
            n = ct_py_number(items[i]);
            if n is None {
                break;
            }
            nums.append(n);
            i += 1;
        }
        result = ct_from_number(sum(nums, start));
    }
    while i < len(items) {
        result = ct_binop("+", result, items[i]);
        i += 1;
    }
    return result;
}

impl _range(args: list[CtValue], kwargs: dict[str, CtValue]) -> CtRange {
    if kwargs {
        raise ct_exc("TypeError", "range() takes no keyword arguments");
    }
    if not args or len(args) > 3 {
        raise ct_exc(
            "TypeError",
            f"range expected at least 1 argument, got {len(args)}"
                if not args
                else f"range expected at most 3 arguments, got {len(args)}"
        );
    }
    vals: list[int] = [];
    for a in args {
        vals.append(_as_index(a).value);
    }
    if len(vals) == 1 {
        return CtRange(start=0, stop=vals[0], step=1);
    }
    step = vals[2] if len(vals) == 3 else 1;
    if step == 0 {
        raise ct_exc("ValueError", "range() arg 3 must not be zero");
    }
    return CtRange(start=vals[0], stop=vals[1], step=step);
}

impl _round(args: list[CtValue], kwargs: dict[str, CtValue]) -> CtValue {
    slots = _arity("round", args, kwargs, ["number", "ndigits"], 1);
    num = ct_py_number(slots[0]);
    if num is None {
        raise ct_exc(
            "TypeError",
            f"type {ct_type_name(slots[0])} doesn't define __round__ method"
        );
    }
    nd = slots[1];
    try {
        if nd is CT_ABSENT or isinstance(nd, CtNone) {
            return ct_from_number(round(num));
        }
        return ct_from_number(round(num, _as_small(nd)));
    } except (ValueError, OverflowError) as e {
        raise ct_py_exc(e);
    }
}

impl _divmod(a: CtValue, b: CtValue) -> CtValue {
    x = ct_py_number(a);
    y = ct_py_number(b);
    if x is None or y is None {
        raise ct_exc(
            "TypeError",
            f"unsupported operand type(s) for divmod(): '{ct_type_name(a)}' and '{ct_type_name(
                b
            )}'"
        );
    }
    try {
        (q, r) = divmod(x, y);
    } except ArithmeticError as e {
        raise ct_py_exc(e);
    }
    return mk_tuple([ct_from_number(q), ct_from_number(r)]);
}

impl _reversed(v: CtValue) -> CtList {
    if isinstance(v, (CtList, CtTuple, CtStr, CtBytes, CtRange, CtDict, CtView)) {
        items = ct_iter(v);
        items.reverse();
        return mk_list(items);
    }
    raise ct_exc("TypeError", f"'{ct_type_name(v)}' object is not reversible");
}

impl ct_call_builtin(
    ev: CtCaller, name: str, args: list[CtValue], kwargs: dict[str, CtValue]
) -> CtValue {
    if name.startswith("math.") {
        return ct_call_math(name[5:], args, kwargs);
    }
    if name == "len" {
        return mk_int(ct_len(_one_arg("len", args, kwargs)));
    }
    if name == "repr" {
        return mk_str(ct_repr(_one_arg("repr", args, kwargs)));
    }
    if name == "hash" {
        return ct_hash(_one_arg("hash", args, kwargs));
    }
    if name == "abs" {
        v = _one_arg("abs", args, kwargs);
        av = ct_py_number(v);
        if av is not None {
            return ct_from_number(abs(av));
        }
        raise ct_exc("TypeError", f"bad operand type for abs(): '{ct_type_name(v)}'");
    }
    if name in ("any", "all") {
        v2 = _one_arg(name, args, kwargs);
        want = name == "any";
        for item in ct_iter(v2) {
            if ct_truthy(item) == want {
                return mk_bool(want);
            }
        }
        return mk_bool(not want);
    }
    if name == "format" {
        slots = _arity("format", args, kwargs, ["value", "format_spec"], 1);
        spec = "";
        if slots[1] is not CT_ABSENT {
            if not isinstance(slots[1], CtStr) {
                raise ct_exc(
                    "TypeError",
                    f"format() argument 2 must be str, not {ct_type_name(slots[1])}"
                );
            }
            spec = slots[1].value;
        }
        return mk_str(ct_format(slots[0], spec));
    }
    if name == "sorted" {
        if len(args) != 1 {
            raise ct_exc("TypeError", f"sorted expected 1 argument, got {len(args)}");
        }
        key: (CtValue | None) = None;
        rev = False;
        for (k, v3) in kwargs.items() {
            if k == "key" {
                key = v3;
            } elif k == "reverse" {
                rev = ct_truthy(v3);
            } else {
                raise ct_exc(
                    "TypeError", f"sort() got an unexpected keyword argument '{k}'"
                );
            }
        }
        return mk_list(ct_sort(ev, ct_iter(args[0]), key, rev));
    }
    if name == "range" {
        return _range(args, kwargs);
    }
    if name == "enumerate" {
        slots2 = _arity("enumerate", args, kwargs, ["iterable", "start"], 1);
        cur = _as_index(slots2[1]).value if slots2[1] is not CT_ABSENT else 0;
        out: list[CtValue] = [];
        for item in ct_iter(slots2[0]) {
            out.append(mk_tuple([mk_int(cur), item]));
            cur += 1;
        }
        return mk_list(out);
    }
    if name == "zip" {
        strict = False;
        for (k, v4) in kwargs.items() {
            if k != "strict" {
                raise ct_exc(
                    "TypeError", f"zip() got an unexpected keyword argument '{k}'"
                );
            }
            strict = ct_truthy(v4);
        }
        seqs = [ct_iter(a) for a in args];
        out2: list[CtValue] = [];
        if seqs {
            n = min([len(s) for s in seqs]);
            if strict and max([len(s) for s in seqs]) != n {
                raise ct_exc("ValueError", "zip() arguments have unequal lengths");
            }
            for i in range(n) {
                out2.append(mk_tuple([s[i] for s in seqs]));
            }
        }
        return mk_list(out2);
    }
    if name == "reversed" {
        return _reversed(_one_arg("reversed", args, kwargs));
    }
    if name in ("min", "max") {
        return _minmax(ev, name, args, kwargs);
    }
    if name == "sum" {
        return _sum(args, kwargs);
    }
    if name == "round" {
        return _round(args, kwargs);
    }
    if name == "divmod" {
        if len(args) != 2 or kwargs {
            raise ct_exc("TypeError", f"divmod expected 2 arguments, got {len(args)}");
        }
        return _divmod(args[0], args[1]);
    }
    if name == "ord" {
        c = _one_arg("ord", args, kwargs);
        if isinstance(c, CtStr) {
            if len(c.value) != 1 {
                raise ct_exc(
                    "TypeError",
                    f"ord() expected a character, but string of length {len(
                        c.value
                    )} found"
                );
            }
            return mk_int(ord(c.value));
        }
        if isinstance(c, CtBytes) {
            if len(c.value) != 1 {
                raise ct_exc(
                    "TypeError",
                    f"ord() expected a character, but string of length {len(
                        c.value
                    )} found"
                );
            }
            return mk_int(c.value[0]);
        }
        raise ct_exc(
            "TypeError",
            f"ord() expected string of length 1, but {ct_type_name(c)} found"
        );
    }
    if name == "chr" {
        ci = _as_index(_one_arg("chr", args, kwargs));
        try {
            return mk_str(chr(ci.value));
        } except (ValueError, OverflowError) as e {
            raise ct_py_exc(e);
        }
    }
    if name in ("hex", "oct", "bin") {
        hv = _as_index(_one_arg(name, args, kwargs)).value;
        if name == "hex" {
            return mk_str(hex(hv));
        }
        return mk_str(oct(hv) if name == "oct" else bin(hv));
    }
    if name == "map" {
        if len(args) < 2 {
            raise ct_exc("TypeError", "map() must have at least two arguments.");
        }
        fn = args[0];
        seqs2 = [ct_iter(a) for a in args[1:]];
        n2 = min([len(s) for s in seqs2]);
        out3: list[CtValue] = [];
        for i in range(n2) {
            out3.append(ev.call_value(fn, [s[i] for s in seqs2], {}));
        }
        return mk_list(out3);
    }
    if name == "filter" {
        if len(args) != 2 {
            raise ct_exc("TypeError", f"filter expected 2 arguments, got {len(args)}");
        }
        fn2 = args[0];
        out4: list[CtValue] = [];
        for item in ct_iter(args[1]) {
            keep = ct_truthy(item)
                if isinstance(fn2, CtNone)
                else ct_truthy(ev.call_value(fn2, [item], {}));
            if keep {
                out4.append(item);
            }
        }
        return mk_list(out4);
    }
    if name == "isinstance" {
        if len(args) != 2 {
            raise ct_exc(
                "TypeError", f"isinstance expected 2 arguments, got {len(args)}"
            );
        }
        return mk_bool(ev.ct_isinstance(args[0], args[1]));
    }
    raise CtError(f"builtin '{name}' is not supported in comptime code");
}

impl _pairs_into(d: CtDict, src: CtValue) {
    if isinstance(src, CtDict) {
        for (i, k) in enumerate(src.keys) {
            dict_set(d, k, src.vals[i]);
        }
        return;
    }
    for (idx, item) in enumerate(ct_iter(src)) {
        if not isinstance(
            item, (CtList, CtTuple, CtStr, CtBytes, CtSet, CtRange, CtDict, CtView)
        ) {
            raise ct_exc(
                "TypeError",
                f"cannot convert dictionary update sequence element #{idx} to a sequence"
            );
        }
        pair = ct_iter(item);
        if len(pair) != 2 {
            raise ct_exc(
                "ValueError",
                f"dictionary update sequence element #{idx} has length {len(
                    pair
                )}; 2 is required"
            );
        }
        dict_set(d, pair[0], pair[1]);
    }
}

impl ct_construct_builtin(
    name: str, args: list[CtValue], kwargs: dict[str, CtValue]
) -> CtValue {
    if name == "int" {
        slots = _arity("int", args, kwargs, ["x", "base"], 0);
        x = slots[0];
        if x is CT_ABSENT {
            if slots[1] is not CT_ABSENT {
                raise ct_exc("TypeError", "int() missing string argument");
            }
            return mk_int(0);
        }
        if not ct_is_scalar(x) {
            raise ct_exc(
                "TypeError",
                f"int() argument must be a string, a bytes-like object or a real number, not '{ct_type_name(
                    x
                )}'"
            );
        }
        xv: any = ct_host_scalar(x);
        try {
            if slots[1] is CT_ABSENT {
                return mk_int(int(xv));
            }
            return mk_int(int(xv, _as_small(slots[1])));
        } except (ValueError, TypeError, OverflowError) as e {
            raise ct_py_exc(e);
        }
    }
    if name == "float" {
        if kwargs or len(args) > 1 {
            raise ct_exc(
                "TypeError", f"float expected at most 1 argument, got {len(args)}"
            );
        }
        if not args {
            return mk_float(0.0);
        }
        fx = args[0];
        if not ct_is_scalar(fx) {
            raise ct_exc(
                "TypeError",
                f"float() argument must be a string or a real number, not '{ct_type_name(
                    fx
                )}'"
            );
        }
        fv: any = ct_host_scalar(fx);
        try {
            return mk_float(float(fv));
        } except (ValueError, TypeError, OverflowError) as e {
            raise ct_py_exc(e);
        }
    }
    if name == "str" {
        slots2 = _arity("str", args, kwargs, ["object", "encoding", "errors"], 0);
        if slots2[0] is CT_ABSENT {
            return mk_str("");
        }
        if slots2[1] is CT_ABSENT and slots2[2] is CT_ABSENT {
            return mk_str(ct_str(slots2[0]));
        }
        src = slots2[0];
        if not isinstance(src, CtBytes) {
            raise ct_exc(
                "TypeError",
                f"decoding to str: need a bytes-like object, {ct_type_name(src)} found"
            );
        }
        return _decode(
            src.value,
            _opt_str(slots2[1], "str() argument 'encoding' must be str, not ")
                or "utf-8",
            _opt_str(slots2[2], "str() argument 'errors' must be str, not ") or "strict"
        );
    }
    if name == "bool" {
        if kwargs or len(args) > 1 {
            raise ct_exc(
                "TypeError", f"bool expected at most 1 argument, got {len(args)}"
            );
        }
        return mk_bool(ct_truthy(args[0]) if args else False);
    }
    if name == "bytes" {
        slots3 = _arity("bytes", args, kwargs, ["source", "encoding", "errors"], 0);
        bsrc = slots3[0];
        if bsrc is None {
            return mk_bytes(b"");
        }
        if isinstance(bsrc, CtStr) {
            if slots3[1] is CT_ABSENT {
                raise ct_exc("TypeError", "string argument without an encoding");
            }
            return _encode(
                bsrc.value,
                _as_str(slots3[1], "bytes() argument 'encoding' must be str, not "),
                _opt_str(slots3[2], "bytes() argument 'errors' must be str, not ")
                    or "strict"
            );
        }
        if slots3[1] is not CT_ABSENT {
            raise ct_exc("TypeError", "encoding without a string argument");
        }
        if isinstance(bsrc, CtBytes) {
            return bsrc;
        }
        biv = as_ct_int(bsrc);
        if biv is not None {
            if biv.value < 0 {
                raise ct_exc("ValueError", "negative count");
            }
            if biv.value > 100000000 {
                raise CtError("comptime bytes() size is too large");
            }
            return mk_bytes(bytes(biv.value));
        }
        vals: list[int] = [];
        for item in ct_iter(bsrc) {
            bv = _as_index(item).value;
            if bv < 0 or bv > 255 {
                raise ct_exc("ValueError", "bytes must be in range(0, 256)");
            }
            vals.append(bv);
        }
        return mk_bytes(bytes(vals));
    }
    if name in ("list", "tuple", "set", "frozenset") {
        if kwargs {
            raise ct_exc("TypeError", f"{name}() takes no keyword arguments");
        }
        if len(args) > 1 {
            raise ct_exc(
                "TypeError", f"{name} expected at most 1 argument, got {len(args)}"
            );
        }
        items = ct_iter(args[0]) if args else [];
        if name == "list" {
            return mk_list(items);
        }
        if name == "tuple" {
            return mk_tuple(items);
        }
        return mk_set(items, frozen=name == "frozenset");
    }
    if name == "dict" {
        if len(args) > 1 {
            raise ct_exc(
                "TypeError", f"dict expected at most 1 argument, got {len(args)}"
            );
        }
        d = mk_dict();
        if args {
            _pairs_into(d, args[0]);
        }
        for (k, v) in kwargs.items() {
            dict_set(d, mk_str(k), v);
        }
        return d;
    }
    if name == "object" {
        raise CtError("object() cannot be constructed at compile time");
    }
    if name in CT_BUILTIN_EXCEPTIONS {
        if kwargs {
            raise ct_exc("TypeError", f"{name}() takes no keyword arguments");
        }
        return CtExc(kind=name, args=args.copy());
    }
    raise CtError(f"cannot construct builtin '{name}' at compile time");
}

impl _decode(data: bytes, encoding: str, errors: str) -> CtStr {
    enc = encoding.lower().replace("_", "-");
    if enc not in ("utf-8", "utf8", "ascii", "latin-1", "latin1", "iso-8859-1") {
        raise CtError(f"encoding '{encoding}' is not supported in comptime code");
    }
    if errors not in ("strict", "replace", "ignore") {
        raise CtError(f"error handler '{errors}' is not supported in comptime code");
    }
    try {
        return mk_str(data.decode(encoding, errors));
    } except UnicodeDecodeError as e {
        raise ct_exc("UnicodeDecodeError", str(e));
    }
}

impl _encode(text: str, encoding: str, errors: str) -> CtBytes {
    enc = encoding.lower().replace("_", "-");
    if enc not in ("utf-8", "utf8", "ascii", "latin-1", "latin1", "iso-8859-1") {
        raise CtError(f"encoding '{encoding}' is not supported in comptime code");
    }
    if errors not in ("strict", "replace", "ignore") {
        raise CtError(f"error handler '{errors}' is not supported in comptime code");
    }
    try {
        return mk_bytes(text.encode(encoding, errors));
    } except UnicodeEncodeError as e {
        raise ct_exc("UnicodeEncodeError", str(e));
    }
}

impl ct_value_attr(v: CtValue, name: str) -> CtValue {
    if ct_has_method(v, name) {
        return CtMethod(owner=ct_method_owner(v), name=name, recv=v);
    }
    iv = as_ct_int(v);
    if iv is not None {
        if name in ("real", "numerator") {
            return iv;
        }
        if name == "imag" {
            return mk_int(0);
        }
        if name == "denominator" {
            return mk_int(1);
        }
    }
    if isinstance(v, CtFloat) {
        if name == "real" {
            return v;
        }
        if name == "imag" {
            return mk_float(0.0);
        }
    }
    if isinstance(v, CtRange) {
        if name == "start" {
            return mk_int(v.start);
        }
        if name == "stop" {
            return mk_int(v.stop);
        }
        if name == "step" {
            return mk_int(v.step);
        }
    }
    if isinstance(v, CtExc) and name == "args" {
        return mk_tuple(v.args.copy());
    }
    if isinstance(v, CtModule) and v.name == "math" {
        if name in CT_MATH_CONSTS {
            return mk_float(CT_MATH_CONSTS[name]);
        }
        if name in CT_MATH_FUNCS {
            return CtBuiltin(name="math." + name);
        }
        raise CtError(f"math.{name} is not available in comptime code");
    }
    raise CtError(f"'{ct_type_name(v)}' has no attribute '{name}'");
}

impl ct_type_attr(type_name: str, attr: str) -> CtValue {
    if f"{type_name}.{attr}" in CT_STATIC_METHODS {
        return CtMethod(owner=type_name, name=attr, recv=None);
    }
    if type_name in CT_METHODS and attr in CT_METHODS[type_name] {
        return CtMethod(owner=type_name, name=attr, recv=None);
    }
    raise CtError(f"{type_name} has no comptime attribute '{attr}'");
}

impl ct_call_method_value(
    ev: CtCaller, m: CtMethod, args: list[CtValue], kwargs: dict[str, CtValue]
) -> CtValue {
    if m.recv is not None {
        return ct_call_method(ev, m.recv, m.name, args, kwargs);
    }
    qual = f"{m.owner}.{m.name}";
    if qual == "dict.fromkeys" {
        slots = _arity("fromkeys", args, kwargs, ["iterable", "value"], 1);
        d = mk_dict();
        fill = slots[1] if slots[1] is not CT_ABSENT else CT_NONE;
        for k in ct_iter(slots[0]) {
            dict_set(d, k, fill);
        }
        return d;
    }
    if qual == "bytes.fromhex" {
        text = _as_str(
            _one_arg("fromhex", args, kwargs), "fromhex() argument must be str, not "
        );
        try {
            return mk_bytes(bytes.fromhex(text));
        } except ValueError as e {
            raise ct_exc("ValueError", str(e));
        }
    }
    if not args {
        raise ct_exc(
            "TypeError", f"unbound method {m.owner}.{m.name}() needs an argument"
        );
    }
    recv = args[0];
    if ct_method_owner(recv) != m.owner
        and not (m.owner == "frozenset" and isinstance(recv, CtSet)) {
        raise ct_exc(
            "TypeError",
            f"descriptor '{m.name}' for '{m.owner}' objects doesn't apply to a '{ct_type_name(
                recv
            )}' object"
        );
    }
    return ct_call_method(ev, recv, m.name, args[1:], kwargs);
}

impl ct_call_method(
    ev: CtCaller,
    recv: CtValue,
    name: str,
    args: list[CtValue],
    kwargs: dict[str, CtValue]
) -> CtValue {
    if not ct_has_method(recv, name) {
        raise CtError(f"'{ct_type_name(recv)}' has no callable attribute '{name}'");
    }
    try {
        if isinstance(recv, CtStr) {
            return _str_method(recv, name, args, kwargs);
        }
        if isinstance(recv, CtBytes) {
            return _bytes_method(recv, name, args, kwargs);
        }
        if isinstance(recv, CtList) {
            return _list_method(ev, recv, name, args, kwargs);
        }
        if isinstance(recv, CtTuple) {
            return _seq_index_count(recv.items, "tuple", name, args, kwargs);
        }
        if isinstance(recv, CtDict) {
            return _dict_method(recv, name, args, kwargs);
        }
        if isinstance(recv, CtSet) {
            return _set_method(recv, name, args, kwargs);
        }
        if isinstance(recv, CtRange) {
            return _seq_index_count(ct_iter(recv), "range", name, args, kwargs);
        }
        if isinstance(recv, CtFloat) {
            return _float_method(recv, name, args, kwargs);
        }
        iv = as_ct_int(recv);
        if iv is not None {
            return _int_method(iv, name, args, kwargs);
        }
    } except ValueError as e {
        raise ct_exc("ValueError", str(e));
    } except OverflowError as e {
        raise ct_exc("OverflowError", str(e));
    }
    raise CtError(f"'{ct_type_name(recv)}' has no callable attribute '{name}'");
}

impl _str_method(
    recv: CtStr, name: str, args: list[CtValue], kwargs: dict[str, CtValue]
) -> CtValue {
    s = recv.value;
    if name == "format" {
        return mk_str(ct_str_format(s, args, kwargs));
    }
    if name in ("upper", "lower", "casefold", "capitalize", "title", "swapcase") {
        _no_args(name, args, kwargs);
        if name == "upper" {
            return mk_str(s.upper());
        }
        if name == "lower" {
            return mk_str(s.lower());
        }
        if name == "casefold" {
            return mk_str(s.casefold());
        }
        if name == "capitalize" {
            return mk_str(s.capitalize());
        }
        if name == "title" {
            return mk_str(s.title());
        }
        return mk_str(s.swapcase());
    }
    if name
        in (
            "isdigit",
            "isalpha",
            "isalnum",
            "isspace",
            "isupper",
            "islower",
            "isidentifier",
            "isnumeric",
            "isdecimal",
            "istitle",
            "isascii",
            "isprintable"
        ) {
        _no_args(name, args, kwargs);
        if name == "isdigit" {
            return mk_bool(s.isdigit());
        }
        if name == "isalpha" {
            return mk_bool(s.isalpha());
        }
        if name == "isalnum" {
            return mk_bool(s.isalnum());
        }
        if name == "isspace" {
            return mk_bool(s.isspace());
        }
        if name == "isupper" {
            return mk_bool(s.isupper());
        }
        if name == "islower" {
            return mk_bool(s.islower());
        }
        if name == "isidentifier" {
            return mk_bool(s.isidentifier());
        }
        if name == "isnumeric" {
            return mk_bool(s.isnumeric());
        }
        if name == "isdecimal" {
            return mk_bool(s.isdecimal());
        }
        if name == "istitle" {
            return mk_bool(s.istitle());
        }
        if name == "isascii" {
            return mk_bool(s.isascii());
        }
        return mk_bool(s.isprintable());
    }
    if name in ("strip", "lstrip", "rstrip") {
        slots = _arity(name, args, kwargs, ["chars"], 0);
        chars = _opt_str(slots[0], f"{name} arg must be None or str, not ");
        if chars is None {
            if name == "strip" {
                return mk_str(s.strip());
            }
            if name == "lstrip" {
                return mk_str(s.lstrip());
            }
            return mk_str(s.rstrip());
        }
        if name == "strip" {
            return mk_str(s.strip(chars));
        }
        if name == "lstrip" {
            return mk_str(s.lstrip(chars));
        }
        return mk_str(s.rstrip(chars));
    }
    if name in ("split", "rsplit") {
        slots2 = _arity(name, args, kwargs, ["sep", "maxsplit"], 0);
        sep = _opt_str(slots2[0], "must be str or None, not ");
        maxsplit = _opt_small(slots2[1]);
        limit = maxsplit if maxsplit is not None else -1;
        if sep is None {
            return _str_list(str_split_ws(s, limit, name == "rsplit"));
        }
        if sep == "" {
            raise ct_exc("ValueError", "empty separator");
        }
        return _str_list(str_split_sep(s, sep, limit, name == "rsplit"));
    }
    if name == "splitlines" {
        slots3 = _arity(name, args, kwargs, ["keepends"], 0);
        keep = ct_truthy(slots3[0]) if slots3[0] is not CT_ABSENT else False;
        return _str_list(s.splitlines(keep));
    }
    if name == "join" {
        parts: list[str] = [];
        for (i, item) in enumerate(ct_iter(_one_arg("join", args, kwargs))) {
            if not isinstance(item, CtStr) {
                raise ct_exc(
                    "TypeError",
                    f"sequence item {i}: expected str instance, {ct_type_name(
                        item
                    )} found"
                );
            }
            parts.append(item.value);
        }
        return mk_str(s.join(parts));
    }
    if name == "replace" {
        slots4 = _arity(name, args, kwargs, ["old", "new", "count"], 2);
        old = _as_str(slots4[0], "replace() argument 1 must be str, not ");
        new = _as_str(slots4[1], "replace() argument 2 must be str, not ");
        count = _opt_small(slots4[2]);
        return mk_str(s.replace(old, new, count if count is not None else -1));
    }
    if name in ("startswith", "endswith") {
        slots5 = _arity(name, args, kwargs, ["prefix", "start", "end"], 1);
        start = _opt_small(slots5[1]);
        end = _opt_small(slots5[2]);
        cands: list[str] = [];
        probe = slots5[0];
        if isinstance(probe, CtTuple) {
            for p in probe.items {
                cands.append(
                    _as_str(p, f"tuple for {name} must only contain str, not ")
                );
            }
        } elif isinstance(probe, CtStr) {
            cands.append(probe.value);
        } else {
            raise ct_exc(
                "TypeError",
                f"{name} first arg must be str or a tuple of str, not {ct_type_name(
                    probe
                )}"
            );
        }
        for c in cands {
            if str_tailmatch(s, c, start, end, name == "endswith") {
                return CT_TRUE;
            }
        }
        return CT_FALSE;
    }
    if name in ("find", "rfind", "index", "rindex", "count") {
        slots6 = _arity(name, args, kwargs, ["sub", "start", "end"], 1);
        sub = _as_str(slots6[0], "must be str, not ");
        (lo, hi) = adjust_indices(len(s), _opt_small(slots6[1]), _opt_small(slots6[2]));
        if name == "count" {
            if hi - lo < len(sub) {
                return mk_int(0);
            }
            return mk_int(s[lo:hi].count(sub));
        }
        pos = -1;
        if hi - lo >= len(sub) {
            window = s[lo:hi];
            found = window.find(sub);
            if name in ("rfind", "rindex") {
                found = window.rfind(sub);
            }
            if found >= 0 {
                pos = found + lo;
            }
        }
        if pos < 0 and name in ("index", "rindex") {
            raise ct_exc("ValueError", "substring not found");
        }
        return mk_int(pos);
    }
    if name in ("center", "ljust", "rjust") {
        slots7 = _arity(name, args, kwargs, ["width", "fillchar"], 1);
        width = _as_small(slots7[0]);
        fill = _opt_str(
            slots7[1], "The fill character must be a unicode character, not "
        )
            or " ";
        if len(fill) != 1 {
            raise ct_exc(
                "TypeError", "The fill character must be exactly one character long"
            );
        }
        if name == "center" {
            return mk_str(s.center(width, fill));
        }
        if name == "ljust" {
            return mk_str(s.ljust(width, fill));
        }
        return mk_str(s.rjust(width, fill));
    }
    if name == "zfill" {
        return mk_str(s.zfill(_as_small(_one_arg("zfill", args, kwargs))));
    }
    if name in ("partition", "rpartition") {
        sep2 = _as_str(_one_arg(name, args, kwargs), "must be str, not ");
        if not sep2 {
            raise ct_exc("ValueError", "empty separator");
        }
        cut = s.partition(sep2) if name == "partition" else s.rpartition(sep2);
        return mk_tuple([mk_str(cut[0]), mk_str(cut[1]), mk_str(cut[2])]);
    }
    if name == "encode" {
        slots8 = _arity(name, args, kwargs, ["encoding", "errors"], 0);
        return _encode(
            s,
            _opt_str(slots8[0], "encode() argument 'encoding' must be str, not ")
                or "utf-8",
            _opt_str(slots8[1], "encode() argument 'errors' must be str, not ")
                or "strict"
        );
    }
    if name in ("removeprefix", "removesuffix") {
        affix = _as_str(
            _one_arg(name, args, kwargs), f"{name}() argument must be str, not "
        );
        if name == "removeprefix" {
            return mk_str(s.removeprefix(affix));
        }
        return mk_str(s.removesuffix(affix));
    }
    if name == "expandtabs" {
        slots9 = _arity(name, args, kwargs, ["tabsize"], 0);
        tabsize = _opt_small(slots9[0]);
        return mk_str(s.expandtabs(tabsize if tabsize is not None else 8));
    }
    raise CtError(f"'str' has no callable attribute '{name}'");
}

impl _as_bytes_arg(v: CtValue) -> bytes {
    if isinstance(v, CtBytes) {
        return v.value;
    }
    raise ct_exc(
        "TypeError", f"a bytes-like object is required, not '{ct_type_name(v)}'"
    );
}

impl _bytes_method(
    recv: CtBytes, name: str, args: list[CtValue], kwargs: dict[str, CtValue]
) -> CtValue {
    b = recv.value;
    if name == "decode" {
        slots = _arity(name, args, kwargs, ["encoding", "errors"], 0);
        return _decode(
            b,
            _opt_str(slots[0], "decode() argument 'encoding' must be str, not ")
                or "utf-8",
            _opt_str(slots[1], "decode() argument 'errors' must be str, not ")
                or "strict"
        );
    }
    if name == "hex" {
        _no_args(name, args, kwargs);
        return mk_str(b.hex());
    }
    if name in ("upper", "lower") {
        _no_args(name, args, kwargs);
        if name == "upper" {
            return mk_bytes(b.upper());
        }
        return mk_bytes(b.lower());
    }
    if name in ("startswith", "endswith") {
        probe = _as_bytes_arg(_one_arg(name, args, kwargs));
        if name == "startswith" {
            return mk_bool(b.startswith(probe));
        }
        return mk_bool(b.endswith(probe));
    }
    if name in ("find", "rfind", "index", "count") {
        sub = _as_bytes_arg(_one_arg(name, args, kwargs));
        if name == "count" {
            return mk_int(b.count(sub));
        }
        pos = bytes_find(b, sub, name == "rfind");
        if name == "index" and pos < 0 {
            raise ct_exc("ValueError", "subsection not found");
        }
        return mk_int(pos);
    }
    if name == "replace" {
        slots2 = _arity(name, args, kwargs, ["old", "new", "count"], 2);
        cnt = _opt_small(slots2[2]);
        return mk_bytes(
            b.replace(
                _as_bytes_arg(slots2[0]),
                _as_bytes_arg(slots2[1]),
                cnt if cnt is not None else -1
            )
        );
    }
    if name in ("strip", "lstrip", "rstrip") {
        slots3 = _arity(name, args, kwargs, ["bytes"], 0);
        chars: (bytes | None) = None;
        if slots3[0] is not CT_ABSENT and not isinstance(slots3[0], CtNone) {
            chars = _as_bytes_arg(slots3[0]);
        }
        if name == "strip" {
            return mk_bytes(b.strip(chars));
        }
        if name == "lstrip" {
            return mk_bytes(b.lstrip(chars));
        }
        return mk_bytes(b.rstrip(chars));
    }
    if name == "split" {
        slots4 = _arity(name, args, kwargs, ["sep", "maxsplit"], 0);
        sep: (bytes | None) = None;
        if slots4[0] is not CT_ABSENT and not isinstance(slots4[0], CtNone) {
            sep = _as_bytes_arg(slots4[0]);
            if not sep {
                raise ct_exc("ValueError", "empty separator");
            }
        }
        ms = _opt_small(slots4[1]);
        return mk_list(
            [mk_bytes(x) for x in b.split(sep, ms if ms is not None else -1)]
        );
    }
    if name == "join" {
        parts: list[bytes] = [];
        for (i, item) in enumerate(ct_iter(_one_arg("join", args, kwargs))) {
            if not isinstance(item, CtBytes) {
                raise ct_exc(
                    "TypeError",
                    f"sequence item {i}: expected a bytes-like object, {ct_type_name(
                        item
                    )} found"
                );
            }
            parts.append(item.value);
        }
        return mk_bytes(b.join(parts));
    }
    raise CtError(f"'bytes' has no callable attribute '{name}'");
}

impl _seq_index_count(
    items: list[CtValue],
    owner: str,
    name: str,
    args: list[CtValue],
    kwargs: dict[str, CtValue]
) -> CtValue {
    if name == "count" {
        target = _one_arg("count", args, kwargs);
        n = 0;
        for x in items {
            if ct_same_or_eq(x, target) {
                n += 1;
            }
        }
        return mk_int(n);
    }
    slots = _arity("index", args, kwargs, ["value", "start", "stop"], 1);
    (start, stop, _, _) = slice_indices(len(items), slots[1], slots[2], None);
    for i in range(start, stop) {
        if ct_same_or_eq(items[i], slots[0]) {
            return mk_int(i);
        }
    }
    if owner == "range" {
        raise ct_exc("ValueError", f"{ct_repr(slots[0])} is not in range");
    }
    raise ct_exc("ValueError", f"{owner}.index(x): x not in {owner}");
}

impl _list_method(
    ev: CtCaller,
    recv: CtList,
    name: str,
    args: list[CtValue],
    kwargs: dict[str, CtValue]
) -> CtValue {
    items = recv.items;
    if name == "append" {
        items.append(_one_arg("append", args, kwargs));
        return CT_NONE;
    }
    if name == "extend" {
        items.extend(ct_iter(_one_arg("extend", args, kwargs)));
        return CT_NONE;
    }
    if name == "insert" {
        if len(args) != 2 or kwargs {
            raise ct_exc("TypeError", f"insert expected 2 arguments, got {len(args)}");
        }
        items.insert(_as_small(args[0]), args[1]);
        return CT_NONE;
    }
    if name == "pop" {
        slots = _arity("pop", args, kwargs, ["index"], 0);
        if not items {
            raise ct_exc("IndexError", "pop from empty list");
        }
        idx = _as_small(slots[0]) if slots[0] is not CT_ABSENT else -1;
        if idx < 0 {
            idx += len(items);
        }
        if idx < 0 or idx >= len(items) {
            raise ct_exc("IndexError", "pop index out of range");
        }
        return items.pop(idx);
    }
    if name == "remove" {
        target = _one_arg("remove", args, kwargs);
        for (i, x) in enumerate(items) {
            if ct_same_or_eq(x, target) {
                items.pop(i);
                return CT_NONE;
            }
        }
        raise ct_exc("ValueError", "list.remove(x): x not in list");
    }
    if name in ("index", "count") {
        return _seq_index_count(items, "list", name, args, kwargs);
    }
    if name == "reverse" {
        _no_args(name, args, kwargs);
        items.reverse();
        return CT_NONE;
    }
    if name == "sort" {
        if args {
            raise ct_exc("TypeError", "sort() takes no positional arguments");
        }
        key: (CtValue | None) = None;
        rev = False;
        for (k, v) in kwargs.items() {
            if k == "key" {
                key = v;
            } elif k == "reverse" {
                rev = ct_truthy(v);
            } else {
                raise ct_exc(
                    "TypeError", f"sort() got an unexpected keyword argument '{k}'"
                );
            }
        }
        recv.items = ct_sort(ev, items.copy(), key, rev);
        return CT_NONE;
    }
    if name == "copy" {
        _no_args(name, args, kwargs);
        return mk_list(items.copy());
    }
    if name == "clear" {
        _no_args(name, args, kwargs);
        recv.items = [];
        return CT_NONE;
    }
    raise CtError(f"'list' has no callable attribute '{name}'");
}

impl _dict_method(
    recv: CtDict, name: str, args: list[CtValue], kwargs: dict[str, CtValue]
) -> CtValue {
    if name == "get" {
        slots = _arity("get", args, kwargs, ["key", "default"], 1);
        got = dict_get(recv, slots[0]);
        if got is not None {
            return got;
        }
        return slots[1] if slots[1] is not CT_ABSENT else CT_NONE;
    }
    if name in ("keys", "values", "items") {
        _no_args(name, args, kwargs);
        return CtView(kind=name, source=recv);
    }
    if name == "pop" {
        if kwargs or not args or len(args) > 2 {
            raise ct_exc(
                "TypeError", f"pop expected at least 1 argument, got {len(args)}"
            );
        }
        got2 = dict_get(recv, args[0]);
        if got2 is None {
            if len(args) == 2 {
                return args[1];
            }
            raise ct_exc_value("KeyError", args[0]);
        }
        dict_delete(recv, args[0]);
        return got2;
    }
    if name == "popitem" {
        _no_args(name, args, kwargs);
        if not recv.keys {
            raise ct_exc("KeyError", "popitem(): dictionary is empty");
        }
        k = recv.keys[-1];
        v = recv.vals[-1];
        dict_delete(recv, k);
        return mk_tuple([k, v]);
    }
    if name == "setdefault" {
        slots2 = _arity("setdefault", args, kwargs, ["key", "default"], 1);
        got3 = dict_get(recv, slots2[0]);
        if got3 is not None {
            return got3;
        }
        dflt = slots2[1] if slots2[1] is not CT_ABSENT else CT_NONE;
        dict_set(recv, slots2[0], dflt);
        return dflt;
    }
    if name == "update" {
        if len(args) > 1 {
            raise ct_exc(
                "TypeError", f"update expected at most 1 argument, got {len(args)}"
            );
        }
        if args {
            _pairs_into(recv, args[0]);
        }
        for (k2, v2) in kwargs.items() {
            dict_set(recv, mk_str(k2), v2);
        }
        return CT_NONE;
    }
    if name == "copy" {
        _no_args(name, args, kwargs);
        return dict_copy(recv);
    }
    if name == "clear" {
        _no_args(name, args, kwargs);
        recv.keys = [];
        recv.vals = [];
        recv.index = {};
        return CT_NONE;
    }
    raise CtError(f"'dict' has no callable attribute '{name}'");
}

impl _as_set(v: CtValue) -> CtSet {
    if isinstance(v, CtSet) {
        return v;
    }
    return mk_set(ct_iter(v));
}

impl _set_method(
    recv: CtSet, name: str, args: list[CtValue], kwargs: dict[str, CtValue]
) -> CtValue {
    if kwargs {
        raise ct_exc("TypeError", f"{name}() takes no keyword arguments");
    }
    if name == "add" {
        set_add(recv, _one_arg("add", args, kwargs));
        return CT_NONE;
    }
    if name == "discard" {
        set_discard(recv, _one_arg("discard", args, kwargs));
        return CT_NONE;
    }
    if name == "remove" {
        item = _one_arg("remove", args, kwargs);
        if not set_discard(recv, item) {
            raise ct_exc_value("KeyError", item);
        }
        return CT_NONE;
    }
    if name == "pop" {
        _no_args(name, args, kwargs);
        if not recv.items {
            raise ct_exc("KeyError", "pop from an empty set");
        }
        first = recv.items[0];
        set_discard(recv, first);
        return first;
    }
    if name == "clear" {
        _no_args(name, args, kwargs);
        recv.items = [];
        recv.index = {};
        return CT_NONE;
    }
    if name == "copy" {
        _no_args(name, args, kwargs);
        return mk_set(recv.items.copy(), frozen=recv.frozen);
    }
    if name in ("union", "intersection", "difference") {
        sym = "|" if name == "union" else ("&" if name == "intersection" else "-");
        acc = mk_set(recv.items.copy(), frozen=recv.frozen);
        for other in args {
            acc = set_algebra(sym, acc, _as_set(other), recv.frozen);
        }
        return acc;
    }
    if name == "symmetric_difference" {
        return set_algebra(
            "^", recv, _as_set(_one_arg(name, args, kwargs)), recv.frozen
        );
    }
    if name
        in (
            "update",
            "intersection_update",
            "difference_update",
            "symmetric_difference_update"
        ) {
        sym2 = "|";
        if name == "intersection_update" {
            sym2 = "&";
        } elif name == "difference_update" {
            sym2 = "-";
        } elif name == "symmetric_difference_update" {
            sym2 = "^";
        }
        cur = recv;
        for other in args {
            cur = set_algebra(sym2, cur, _as_set(other), False);
        }
        recv.items = cur.items;
        recv.index = cur.index;
        return CT_NONE;
    }
    other2 = _as_set(_one_arg(name, args, kwargs));
    if name == "issubset" {
        return mk_bool(ct_order("<=", recv, other2));
    }
    if name == "issuperset" {
        return mk_bool(ct_order(">=", recv, other2));
    }
    if name == "isdisjoint" {
        for item in recv.items {
            if set_has(other2, item) {
                return CT_FALSE;
            }
        }
        return CT_TRUE;
    }
    raise CtError(f"'set' has no callable attribute '{name}'");
}

impl _int_method(
    recv: CtInt, name: str, args: list[CtValue], kwargs: dict[str, CtValue]
) -> CtValue {
    _no_args(name, args, kwargs);
    return _from_math(getattr(recv.value, name)());
}

impl _float_method(
    recv: CtFloat, name: str, args: list[CtValue], kwargs: dict[str, CtValue]
) -> CtValue {
    _no_args(name, args, kwargs);
    try {
        return _from_math(getattr(recv.value, name)());
    } except (ValueError, OverflowError) as e {
        raise ct_py_exc(e);
    }
}

impl _math_arg(v: CtValue) -> object {
    if ct_is_scalar(v) {
        return ct_host_scalar(v);
    }
    if isinstance(v, CtRange) {
        return range(v.start, v.stop, v.step);
    }
    if isinstance(v, (CtList, CtTuple, CtSet)) {
        return [_math_arg(item) for item in v.items];
    }
    raise ct_exc("TypeError", f"must be real number, not {ct_type_name(v)}");
}

impl _from_math(out: object) -> CtValue {
    if isinstance(out, tuple) {
        return mk_tuple([ct_from_number(x) for x in out]);
    }
    return ct_from_number(out);
}

impl ct_call_math(
    name: str, args: list[CtValue], kwargs: dict[str, CtValue]
) -> CtValue {
    if name == "prod" {
        slots = _arity("prod", args, {}, ["iterable"], 1);
        acc: CtValue = mk_int(1);
        for (k, v) in kwargs.items() {
            if k != "start" {
                raise ct_exc(
                    "TypeError", f"prod() got an unexpected keyword argument '{k}'"
                );
            }
            acc = v;
        }
        for item in ct_iter(slots[0]) {
            acc = ct_binary("*", acc, item);
        }
        return acc;
    }
    py_args = [_math_arg(a) for a in args];
    py_kwargs = {k: _math_arg(v) for (k, v) in kwargs.items()};
    ints = [
        a
        for a in py_args
        if isinstance(a, int)
    ];
    if name == "factorial" or (name == "perm" and len(py_args) == 1) {
        if len(ints) == 1 and ints[0] > CT_FACTORIAL_LIMIT {
            raise CtError("comptime factorial argument is too large");
        }
    } elif name in ("comb", "perm") and len(ints) == 2 {
        (n, k) = (ints[0], ints[1]);
        if 0 <= k and k <= n {
            if (min(k, n - k) if name == "comb" else k) > CT_FACTORIAL_LIMIT {
                raise CtError("comptime comb/perm argument is too large");
            }
        }
    }
    try {
        return _from_math(getattr(math, name)(*py_args, **py_kwargs));
    } except (ArithmeticError, ValueError, TypeError) as e {
        raise ct_py_exc(e);
    }
}

impl adjust_indices(n: int, start: (int | None), end: (int | None)) -> tuple[int, int] {
    hi = n if end is None else end;
    if hi > n {
        hi = n;
    } elif hi < 0 {
        hi += n;
        if hi < 0 {
            hi = 0;
        }
    }
    lo = 0 if start is None else start;
    if lo < 0 {
        lo += n;
        if lo < 0 {
            lo = 0;
        }
    }
    return (lo, hi);
}

impl str_tailmatch(
    s: str, sub: str, start: (int | None), end: (int | None), suffix: bool
) -> bool {
    (lo, hi) = adjust_indices(len(s), start, end);
    if hi - len(sub) < lo {
        return False;
    }
    if suffix {
        return s[hi - len(sub):hi] == sub;
    }
    return s[lo:lo + len(sub)] == sub;
}

impl str_split_ws(s: str, maxsplit: int, from_right: bool) -> list[str] {
    out: list[str] = [];
    n = len(s);
    count = 0;
    if not from_right {
        i = 0;
        while maxsplit < 0 or count < maxsplit {
            while i < n and s[i].isspace() {
                i += 1;
            }
            if i == n {
                break;
            }
            j = i;
            i += 1;
            while i < n and not s[i].isspace() {
                i += 1;
            }
            out.append(s[j:i]);
            count += 1;
        }
        if i < n {
            while i < n and s[i].isspace() {
                i += 1;
            }
            if i != n {
                out.append(s[i:n]);
            }
        }
        return out;
    }
    k = n - 1;
    while maxsplit < 0 or count < maxsplit {
        while k >= 0 and s[k].isspace() {
            k -= 1;
        }
        if k < 0 {
            break;
        }
        j = k;
        k -= 1;
        while k >= 0 and not s[k].isspace() {
            k -= 1;
        }
        out.append(s[k + 1:j + 1]);
        count += 1;
    }
    if k >= 0 {
        while k >= 0 and s[k].isspace() {
            k -= 1;
        }
        if k >= 0 {
            out.append(s[0:k + 1]);
        }
    }
    out.reverse();
    return out;
}

impl str_split_sep(s: str, sep: str, maxsplit: int, from_right: bool) -> list[str] {
    out: list[str] = [];
    count = 0;
    if not from_right {
        i = 0;
        while maxsplit < 0 or count < maxsplit {
            pos = s[i:].find(sep);
            if pos < 0 {
                break;
            }
            out.append(s[i:i + pos]);
            i = i + pos + len(sep);
            count += 1;
        }
        out.append(s[i:]);
        return out;
    }
    j = len(s);
    while maxsplit < 0 or count < maxsplit {
        pos = s[:j].rfind(sep);
        if pos < 0 {
            break;
        }
        out.append(s[pos + len(sep):j]);
        j = pos;
        count += 1;
    }
    out.append(s[:j]);
    out.reverse();
    return out;
}

impl _bytes_match_at(b: bytes, sub: bytes, at: int) -> bool {
    for k in range(len(sub)) {
        if b[at + k] != sub[k] {
            return False;
        }
    }
    return True;
}

impl bytes_find(b: bytes, sub: bytes, from_right: bool) -> int {
    n = len(b);
    m = len(sub);
    if m > n {
        return -1;
    }
    if from_right {
        i = n - m;
        while i >= 0 {
            if _bytes_match_at(b, sub, i) {
                return i;
            }
            i -= 1;
        }
        return -1;
    }
    for j in range(n - m + 1) {
        if _bytes_match_at(b, sub, j) {
            return j;
        }
    }
    return -1;
}
