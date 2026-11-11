impl ct_symbol(opn: str) -> str {
    return CT_OP_SYMBOLS.get(opn, opn);
}

impl ct_py_number(v: CtValue) -> (bool | int | float | None) {
    if isinstance(v, (CtBool, CtInt, CtFloat)) {
        return v.value;
    }
    return None;
}

impl ct_from_number(x: object) -> CtValue {
    if isinstance(x, bool) {
        return mk_bool(x);
    }
    if isinstance(x, int) {
        return mk_int(x);
    }
    if isinstance(x, float) {
        return mk_float(x);
    }
    raise CtError(
        "a negative number raised to a fractional power is complex, which comptime code does not model"
    );
}

impl ct_num_op(sym: str, x: (bool | int | float), y: (bool | int | float)) -> CtValue {
    if isinstance(x, int) and isinstance(y, int) {
        if sym == "**" and y > 0 and abs(x) > 1 {
            if x.bit_length() * y > CT_POW_BITS_LIMIT {
                raise CtError("comptime integer power result is too large");
            }
        }
        if sym == "<<" and x != 0 and y > CT_SHIFT_LIMIT {
            raise CtError("comptime shift count is too large");
        }
    }
    if sym not in CT_PY_OPS {
        raise ct_exc(
            "TypeError",
            f"unsupported operand type(s) for {sym}: '{type(x).__name__}' and '{type(
                y
            ).__name__}'"
        );
    }
    try {
        out = CT_PY_OPS[sym](x, y);
    } except (ArithmeticError, ValueError, TypeError) as e {
        raise ct_py_exc(e);
    }
    return ct_from_number(out);
}

impl int_to_float(a: CtInt) -> float {
    try {
        return float(a.value);
    } except OverflowError as e {
        raise ct_py_exc(e);
    }
}

impl _unsupported(sym: str, l: CtValue, r: CtValue) -> CtRaise {
    return ct_exc(
        "TypeError",
        f"unsupported operand type(s) for {sym}: '{ct_type_name(l)}' and '{ct_type_name(
            r
        )}'"
    );
}

impl _repeat_count(n: CtInt) -> int {
    if n.value > CT_INDEX_MAX or n.value < -CT_INDEX_MAX - 1 {
        raise ct_exc("OverflowError", "cannot fit 'int' into an index-sized integer");
    }
    return max(n.value, 0);
}

impl ct_binop(sym: str, l: CtValue, r: CtValue) -> CtValue {
    if isinstance(l, CtDeferred) or isinstance(r, CtDeferred) {
        raise CtDeferredSignal();
    }
    x = ct_py_number(l);
    y = ct_py_number(r);
    if x is not None and y is not None {
        return ct_num_op(sym, x, y);
    }
    li = as_ct_int(l);
    ri = as_ct_int(r);
    if sym == "+" {
        if isinstance(l, CtStr) and isinstance(r, CtStr) {
            return mk_str(l.value + r.value);
        }
        if isinstance(l, CtBytes) and isinstance(r, CtBytes) {
            return mk_bytes(l.value + r.value);
        }
        if isinstance(l, CtList) and isinstance(r, CtList) {
            return mk_list(l.items + r.items);
        }
        if isinstance(l, CtTuple) and isinstance(r, CtTuple) {
            return mk_tuple(l.items + r.items);
        }
        if isinstance(l, CtStr) {
            raise ct_exc(
                "TypeError",
                f"can only concatenate str (not \"{ct_type_name(r)}\") to str"
            );
        }
        if isinstance(l, CtList) {
            raise ct_exc(
                "TypeError",
                f"can only concatenate list (not \"{ct_type_name(r)}\") to list"
            );
        }
        if isinstance(l, CtTuple) {
            raise ct_exc(
                "TypeError",
                f"can only concatenate tuple (not \"{ct_type_name(r)}\") to tuple"
            );
        }
        if isinstance(l, CtBytes) {
            raise ct_exc("TypeError", f"can't concat {ct_type_name(r)} to bytes");
        }
    }
    if sym == "*" {
        if isinstance(l, (CtStr, CtBytes, CtList, CtTuple)) and ri is not None {
            return _repeat(l, _repeat_count(ri));
        }
        if isinstance(r, (CtStr, CtBytes, CtList, CtTuple)) and li is not None {
            return _repeat(r, _repeat_count(li));
        }
        if isinstance(l, (CtStr, CtBytes, CtList, CtTuple))
            or isinstance(r, (CtStr, CtBytes, CtList, CtTuple)) {
            seq = l if isinstance(l, (CtStr, CtBytes, CtList, CtTuple)) else r;
            other = r if seq is l else l;
            raise ct_exc(
                "TypeError",
                f"can't multiply sequence by non-int of type '{ct_type_name(other)}'"
            );
        }
    }
    if sym == "|" and isinstance(l, CtDict) and isinstance(r, CtDict) {
        out = dict_copy(l);
        for (i, k) in enumerate(r.keys) {
            dict_set(out, k, r.vals[i]);
        }
        return out;
    }
    if sym in ("|", "&", "-", "^")
        and isinstance(l, (CtSet, CtView))
        and isinstance(r, (CtSet, CtView)) {
        if isinstance(l, CtView) or isinstance(r, CtView) {
            ls = l if isinstance(l, CtSet) else view_items_set(l);
            rs = r if isinstance(r, CtSet) else view_items_set(r);
            return set_algebra(sym, ls, rs, False);
        }
        return set_algebra(sym, l, r, l.frozen);
    }
    raise _unsupported(sym, l, r);
}

impl set_algebra(sym: str, l: CtSet, r: CtSet, frozen: bool) -> CtSet {
    out = mk_set([], frozen=frozen);
    if sym == "|" {
        for item in l.items {
            set_add(out, item);
        }
        for item in r.items {
            set_add(out, item);
        }
    } elif sym == "&" {
        (small, big) = (l, r) if len(l.items) <= len(r.items) else (r, l);
        for item in small.items {
            if set_has(big, item) {
                set_add(out, item);
            }
        }
    } elif sym == "-" {
        for item in l.items {
            if not set_has(r, item) {
                set_add(out, item);
            }
        }
    } else {
        for item in l.items {
            if not set_has(r, item) {
                set_add(out, item);
            }
        }
        for item in r.items {
            if not set_has(l, item) {
                set_add(out, item);
            }
        }
    }
    return out;
}

impl _repeat(seq: CtValue, n: int) -> CtValue {
    if isinstance(seq, CtStr) {
        if n and len(seq.value) * n > 100000000 {
            raise CtError("comptime sequence repetition is too large");
        }
        return mk_str(seq.value * n);
    }
    if isinstance(seq, CtBytes) {
        return mk_bytes(seq.value * n);
    }
    if isinstance(seq, CtList) {
        if n and len(seq.items) * n > 100000000 {
            raise CtError("comptime sequence repetition is too large");
        }
        return mk_list(seq.items * n);
    }
    if isinstance(seq, CtTuple) {
        return mk_tuple(seq.items * n);
    }
    return seq;
}

impl ct_unary(op: str, v: CtValue) -> CtValue {
    if isinstance(v, CtDeferred) {
        raise CtDeferredSignal();
    }
    if op == "not" {
        return mk_bool(not ct_truthy(v));
    }
    iv = as_ct_int(v);
    if iv is not None {
        if op == "-" {
            return mk_int(-iv.value);
        }
        if op == "+" {
            return iv;
        }
        if op == "~" {
            return mk_int(~iv.value);
        }
    }
    if isinstance(v, CtFloat) {
        if op == "-" {
            return mk_float(-v.value);
        }
        if op == "+" {
            return v;
        }
    }
    raise ct_exc("TypeError", f"bad operand type for unary {op}: '{ct_type_name(v)}'");
}

impl ct_order(sym: str, l: CtValue, r: CtValue) -> bool {
    if isinstance(l, CtDeferred) or isinstance(r, CtDeferred) {
        raise CtDeferredSignal();
    }
    if ct_is_scalar(l) and ct_is_scalar(r) {
        try {
            return CT_PY_OPS[sym](ct_host_scalar(l), ct_host_scalar(r));
        } except TypeError as e {
            raise ct_py_exc(e);
        }
    }
    if (isinstance(l, CtList) and isinstance(r, CtList))
        or (isinstance(l, CtTuple) and isinstance(r, CtTuple)) {
        n = min(len(l.items), len(r.items));
        for i in range(n) {
            if not ct_same_or_eq(l.items[i], r.items[i]) {
                return ct_order(sym, l.items[i], r.items[i]);
            }
        }
        return CT_PY_OPS[sym](len(l.items), len(r.items));
    }
    if isinstance(l, (CtSet, CtView))
        and isinstance(r, (CtSet, CtView))
        and not (isinstance(l, CtView) and l.kind == "values")
        and not (isinstance(r, CtView) and r.kind == "values") {
        ls = l if isinstance(l, CtSet) else view_items_set(l);
        rs = r if isinstance(r, CtSet) else view_items_set(r);
        if sym in ("<", "<=") {
            if sym == "<" and len(ls.items) >= len(rs.items) {
                return False;
            }
            return _subset(ls, rs);
        }
        if sym == ">" and len(ls.items) <= len(rs.items) {
            return False;
        }
        return _subset(rs, ls);
    }
    raise ct_exc(
        "TypeError",
        f"'{sym}' not supported between instances of '{ct_type_name(l)}' and '{ct_type_name(
            r
        )}'"
    );
}

impl _subset(a: CtSet, b: CtSet) -> bool {
    if len(a.items) > len(b.items) {
        return False;
    }
    for item in a.items {
        if not set_has(b, item) {
            return False;
        }
    }
    return True;
}

impl ct_lt(a: CtValue, b: CtValue) -> bool {
    return ct_order("<", a, b);
}

impl ct_contains(container: CtValue, item: CtValue) -> bool {
    if isinstance(container, CtDeferred) or isinstance(item, CtDeferred) {
        raise CtDeferredSignal();
    }
    if isinstance(container, CtStr) {
        if not isinstance(item, CtStr) {
            raise ct_exc(
                "TypeError",
                f"'in <string>' requires string as left operand, not {ct_type_name(
                    item
                )}"
            );
        }
        return item.value in container.value;
    }
    if isinstance(container, CtBytes) {
        if ct_is_scalar(item) {
            needle: any = ct_host_scalar(item);
            try {
                return needle in container.value;
            } except (TypeError, ValueError) as e {
                raise ct_py_exc(e);
            }
        }
        raise ct_exc(
            "TypeError", f"a bytes-like object is required, not '{ct_type_name(item)}'"
        );
    }
    if isinstance(container, (CtList, CtTuple)) {
        for x in container.items {
            if ct_same_or_eq(x, item) {
                return True;
            }
        }
        return False;
    }
    if isinstance(container, CtDict) {
        return dict_key_of(item) in container.index;
    }
    if isinstance(container, CtSet) {
        return set_key_of(item) in container.index;
    }
    if isinstance(container, CtRange) {
        iv2 = as_ct_int(item);
        if iv2 is not None {
            return iv2.value in range(container.start, container.stop, container.step);
        }
        for x in ct_iter(container) {
            if ct_eq(x, item) {
                return True;
            }
        }
        return False;
    }
    if isinstance(container, CtView) {
        if container.kind == "keys" {
            return dict_key_of(item) in container.source.index;
        }
        for x in ct_iter(container) {
            if ct_same_or_eq(x, item) {
                return True;
            }
        }
        return False;
    }
    raise ct_exc(
        "TypeError",
        f"argument of type '{ct_type_name(container)}' is not a container or iterable"
    );
}

impl ct_is(l: CtValue, r: CtValue) -> bool {
    if isinstance(l, CtNone) or isinstance(r, CtNone) {
        return isinstance(l, CtNone) and isinstance(r, CtNone);
    }
    if isinstance(l, CtBool) or isinstance(r, CtBool) {
        return isinstance(l, CtBool) and isinstance(r, CtBool) and l.value == r.value;
    }
    if isinstance(l, (CtType, CtEnumMember, CtFunc)) {
        return ct_eq(l, r);
    }
    if isinstance(l, CtInt) and isinstance(r, CtInt) {
        if -5 <= l.value and l.value <= 256 {
            return l.value == r.value;
        }
    }
    return l is r;
}

impl ct_compare(sym: str, l: CtValue, r: CtValue) -> bool {
    if sym == "==" {
        return ct_eq(l, r);
    }
    if sym == "!=" {
        return not ct_eq(l, r);
    }
    if sym == "in" {
        return ct_contains(r, l);
    }
    if sym == "not in" {
        return not ct_contains(r, l);
    }
    if sym == "is" {
        return ct_is(l, r);
    }
    if sym == "is not" {
        return not ct_is(l, r);
    }
    return ct_order(sym, l, r);
}

impl _index_of(base: CtValue, key: CtValue, what: str) -> int {
    kv = as_ct_int(key);
    if kv is None {
        tn = ct_type_name(base);
        if isinstance(base, CtStr) {
            raise ct_exc(
                "TypeError",
                f"string indices must be integers, not '{ct_type_name(key)}'"
            );
        }
        noun = "byte" if isinstance(base, CtBytes) else tn;
        raise ct_exc(
            "TypeError",
            f"{noun} indices must be integers or slices, not {ct_type_name(key)}"
        );
    }
    idx = kv.value;
    if idx > CT_INDEX_MAX or idx < -CT_INDEX_MAX - 1 {
        raise ct_exc("IndexError", "cannot fit 'int' into an index-sized integer");
    }
    n = ct_len(base);
    if idx < 0 {
        idx += n;
    }
    if idx < 0 or idx >= n {
        raise ct_exc("IndexError", what);
    }
    return idx;
}

impl ct_getitem(base: CtValue, key: CtValue) -> CtValue {
    if isinstance(base, CtDeferred) or isinstance(key, CtDeferred) {
        raise CtDeferredSignal();
    }
    if isinstance(base, CtList) {
        return base.items[_index_of(base, key, "list index out of range")];
    }
    if isinstance(base, CtTuple) {
        return base.items[_index_of(base, key, "tuple index out of range")];
    }
    if isinstance(base, CtStr) {
        return mk_str(base.value[_index_of(base, key, "string index out of range")]);
    }
    if isinstance(base, CtBytes) {
        return mk_int(base.value[_index_of(base, key, "index out of range")]);
    }
    if isinstance(base, CtRange) {
        i = _index_of(base, key, "range object index out of range");
        return mk_int(base.start + i * base.step);
    }
    if isinstance(base, CtDict) {
        got = dict_get(base, key);
        if got is None {
            raise ct_exc_value("KeyError", key);
        }
        return got;
    }
    raise ct_exc("TypeError", f"'{ct_type_name(base)}' object is not subscriptable");
}

impl _slice_bound(v: (CtValue | None)) -> (int | None) {
    if v is None or isinstance(v, CtNone) {
        return None;
    }
    iv = as_ct_int(v);
    if iv is None {
        raise ct_exc(
            "TypeError",
            "slice indices must be integers or None or have an __index__ method"
        );
    }
    return max(-CT_INDEX_MAX - 1, min(CT_INDEX_MAX, iv.value));
}

impl slice_indices(
    length: int, lo_v: (CtValue | None), hi_v: (CtValue | None), st_v: (CtValue | None)
) -> tuple[int, int, int, int] {
    step = _slice_bound(st_v);
    if step is None {
        step = 1;
    }
    if step == 0 {
        raise ct_exc("ValueError", "slice step cannot be zero");
    }
    lo = _slice_bound(lo_v);
    hi = _slice_bound(hi_v);
    if lo is None {
        start = length - 1 if step < 0 else 0;
    } else {
        start = lo;
        if start < 0 {
            start += length;
            if start < 0 {
                start = -1 if step < 0 else 0;
            }
        } elif start >= length {
            start = length - 1 if step < 0 else length;
        }
    }
    if hi is None {
        stop = -1 if step < 0 else length;
    } else {
        stop = hi;
        if stop < 0 {
            stop += length;
            if stop < 0 {
                stop = -1 if step < 0 else 0;
            }
        } elif stop >= length {
            stop = length - 1 if step < 0 else length;
        }
    }
    count = 0;
    if step < 0 {
        if stop < start {
            count = (start - stop - 1) // (-step) + 1;
        }
    } elif start < stop {
        count = (stop - start - 1) // step + 1;
    }
    return (start, stop, step, count);
}

impl ct_getslice(
    base: CtValue, lo: (CtValue | None), hi: (CtValue | None), st: (CtValue | None)
) -> CtValue {
    if isinstance(base, CtDeferred) {
        raise CtDeferredSignal();
    }
    if not isinstance(base, (CtList, CtTuple, CtStr, CtBytes, CtRange)) {
        raise ct_exc(
            "TypeError", f"'{ct_type_name(base)}' object is not subscriptable"
        );
    }
    (start, _, step, count) = slice_indices(ct_len(base), lo, hi, st);
    if isinstance(base, CtRange) {
        new_start = base.start + start * base.step;
        new_step = base.step * step;
        return CtRange(
            start=new_start, stop=new_start + count * new_step, step=new_step
        );
    }
    idxs: list[int] = [];
    cur = start;
    for _ in range(count) {
        idxs.append(cur);
        cur += step;
    }
    if isinstance(base, CtStr) {
        return mk_str("".join([base.value[i] for i in idxs]));
    }
    if isinstance(base, CtBytes) {
        return mk_bytes(bytes([base.value[i] for i in idxs]));
    }
    picked: list[CtValue] = [base.items[i] for i in idxs];
    return mk_list(picked) if isinstance(base, CtList) else mk_tuple(picked);
}

impl ct_setitem(base: CtValue, key: CtValue, val: CtValue) {
    if isinstance(base, CtList) {
        base.items[_index_of(base, key, "list assignment index out of range")] = val;
        return;
    }
    if isinstance(base, CtDict) {
        dict_set(base, key, val);
        return;
    }
    if isinstance(base, CtDeferred) {
        raise CtDeferredSignal();
    }
    raise ct_exc(
        "TypeError", f"'{ct_type_name(base)}' object does not support item assignment"
    );
}

impl ct_int_literal(text: str) -> CtInt {
    try {
        return mk_int(int(text, 0));
    } except ValueError as e {
        raise ct_py_exc(e);
    }
}

impl int_to_base_str(a: CtInt, base: int) -> str {
    return format(abs(a.value), {16: "x", 8: "o", 2: "b", 10: "d"}[base]);
}

impl _hashable_py(v: CtValue) -> object {
    if isinstance(v, (CtNone, CtBool, CtInt)) {
        return ct_host_scalar(v);
    }
    if isinstance(v, CtFloat) {
        if v.value != v.value {
            raise CtError(
                "hash() of NaN depends on object identity and is not reproducible at compile time"
            );
        }
        return v.value;
    }
    if isinstance(v, CtTuple) {
        return tuple([_hashable_py(item) for item in v.items]);
    }
    if ct_is_unhashable(v) {
        raise ct_exc("TypeError", f"unhashable type: '{ct_type_name(v)}'");
    }
    raise CtError(
        f"hash() of a '{ct_type_name(
            v
        )}' value is seeded per process and is not reproducible at compile time"
    );
}

impl ct_hash(v: CtValue) -> CtInt {
    return mk_int(hash(_hashable_py(v)));
}
