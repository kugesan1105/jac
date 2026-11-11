impl CtValue.__repr__ -> str {
    return ct_repr(self);
}

impl CtRaise.__str__ -> str {
    return ct_str(self.exc);
}

impl ct_exc(kind: str, msg: str) -> CtRaise {
    return CtRaise(exc=CtExc(kind=kind, args=[mk_str(msg)]));
}

impl ct_exc_value(kind: str, arg: CtValue) -> CtRaise {
    return CtRaise(exc=CtExc(kind=kind, args=[arg]));
}

impl ct_exc_is(kind: str, ancestor: str) -> bool {
    k = getattr(builtins, kind, None);
    a = getattr(builtins, ancestor, None);
    if isinstance(k, type)
        and isinstance(a, type)
        and issubclass(k, BaseException)
        and issubclass(a, BaseException) {
        return issubclass(k, a);
    }
    return kind == ancestor;
}

impl mk_bool(b: bool) -> CtBool {
    return CT_TRUE if b else CT_FALSE;
}

impl mk_int(v: int) -> CtInt {
    return CtInt(value=v);
}

impl mk_float(f: float) -> CtFloat {
    return CtFloat(value=f);
}

impl mk_str(s: str) -> CtStr {
    return CtStr(value=s);
}

impl mk_bytes(b: bytes) -> CtBytes {
    return CtBytes(value=b);
}

impl mk_list(items: list[CtValue]) -> CtList {
    return CtList(items=items);
}

impl mk_tuple(items: list[CtValue]) -> CtTuple {
    return CtTuple(items=items);
}

impl mk_dict -> CtDict {
    return CtDict(keys=[], vals=[], index={});
}

impl mk_set(items: list[CtValue], frozen: bool = False) -> CtSet {
    out = CtSet(items=[], index={}, frozen=frozen);
    for item in items {
        set_add(out, item);
    }
    return out;
}

impl ct_py_exc(e: Exception) -> CtRaise {
    args: list[CtValue] = [];
    for a in e.args {
        if a is None {
            args.append(CT_NONE);
        } elif isinstance(a, bool) {
            args.append(mk_bool(a));
        } elif isinstance(a, int) {
            args.append(mk_int(a));
        } elif isinstance(a, str) {
            args.append(mk_str(a));
        } else {
            args.append(mk_str(str(a)));
        }
    }
    return CtRaise(exc=CtExc(kind=type(e).__name__, args=args));
}

impl int_wide_bytes(v: CtInt) -> (bytes | None) {
    mag = abs(v.value);
    if mag.bit_length() <= 63 {
        return None;
    }
    return mag.to_bytes((mag.bit_length() + 7) // 8, "little");
}

impl int_decimal(v: int) -> str {
    try {
        return str(v);
    } except ValueError as e {
        raise ct_py_exc(e);
    }
}

impl as_ct_int(v: CtValue) -> (CtInt | None) {
    if isinstance(v, CtInt) {
        return v;
    }
    if isinstance(v, CtBool) {
        return CtInt(value=1 if v.value else 0);
    }
    return None;
}

impl ct_is_unhashable(v: CtValue) -> bool {
    return _unhashable_name(v) != "";
}

impl _unhashable_name(v: CtValue) -> str {
    if isinstance(v, (CtList, CtDict, CtView, CtRecord)) {
        return ct_type_name(v);
    }
    if isinstance(v, CtSet) {
        return "" if v.frozen else "set";
    }
    if isinstance(v, CtTuple) {
        for item in v.items {
            inner = _unhashable_name(item);
            if inner {
                return inner;
            }
        }
    }
    return "";
}

impl _role_key(v: CtValue, role: str) -> str {
    inner = _unhashable_name(v);
    if inner {
        raise ct_exc(
            "TypeError",
            f"cannot use '{ct_type_name(v)}' as {role} (unhashable type: '{inner}')"
        );
    }
    return ct_key(v);
}

impl dict_key_of(v: CtValue) -> str {
    return _role_key(v, "a dict key");
}

impl set_key_of(v: CtValue) -> str {
    return _role_key(v, "a set element");
}

impl dict_get(d: CtDict, key: CtValue) -> (CtValue | None) {
    idx = d.index.get(dict_key_of(key));
    if idx is None {
        return None;
    }
    return d.vals[idx];
}

impl dict_set(d: CtDict, key: CtValue, val: CtValue) {
    k = dict_key_of(key);
    idx = d.index.get(k);
    if idx is None {
        d.index[k] = len(d.keys);
        d.keys.append(key);
        d.vals.append(val);
    } else {
        d.vals[idx] = val;
    }
}

impl dict_delete(d: CtDict, key: CtValue) -> bool {
    k = dict_key_of(key);
    idx = d.index.get(k);
    if idx is None {
        return False;
    }
    d.keys.pop(idx);
    d.vals.pop(idx);
    d.index = {};
    for (i, kk) in enumerate(d.keys) {
        d.index[ct_key(kk)] = i;
    }
    return True;
}

impl dict_copy(d: CtDict) -> CtDict {
    return CtDict(keys=d.keys.copy(), vals=d.vals.copy(), index=d.index.copy());
}

impl set_has(s: CtSet, item: CtValue) -> bool {
    return set_key_of(item) in s.index;
}

impl set_add(s: CtSet, item: CtValue) {
    k = set_key_of(item);
    if k not in s.index {
        s.index[k] = len(s.items);
        s.items.append(item);
    }
}

impl set_discard(s: CtSet, item: CtValue) -> bool {
    k = set_key_of(item);
    idx = s.index.get(k);
    if idx is None {
        return False;
    }
    s.items.pop(idx);
    s.index = {};
    for (i, it) in enumerate(s.items) {
        s.index[ct_key(it)] = i;
    }
    return True;
}

impl range_len(r: CtRange) -> int {
    if r.step > 0 {
        if r.start >= r.stop {
            return 0;
        }
        return (r.stop - r.start - 1) // r.step + 1;
    }
    if r.start <= r.stop {
        return 0;
    }
    return (r.start - r.stop - 1) // (-r.step) + 1;
}

impl ct_type_name(v: CtValue) -> str {
    if isinstance(v, CtNone) {
        return "NoneType";
    }
    if isinstance(v, CtBool) {
        return "bool";
    }
    if isinstance(v, CtInt) {
        return "int";
    }
    if isinstance(v, CtFloat) {
        return "float";
    }
    if isinstance(v, CtStr) {
        return "str";
    }
    if isinstance(v, CtBytes) {
        return "bytes";
    }
    if isinstance(v, CtTuple) {
        return "tuple";
    }
    if isinstance(v, CtList) {
        return "list";
    }
    if isinstance(v, CtDict) {
        return "dict";
    }
    if isinstance(v, CtSet) {
        return "frozenset" if v.frozen else "set";
    }
    if isinstance(v, CtRange) {
        return "range";
    }
    if isinstance(v, CtView) {
        return "dict_" + v.kind;
    }
    if isinstance(v, CtExc) {
        return v.kind;
    }
    if isinstance(v, (CtBuiltin, CtMethod)) {
        return "builtin_function_or_method";
    }
    if isinstance(v, CtModule) {
        return "module";
    }
    if isinstance(v, CtType) {
        return "CtType";
    }
    if isinstance(v, CtFunc) {
        return "CtFunc";
    }
    if isinstance(v, CtBound) {
        return "CtBound";
    }
    if isinstance(v, CtRecord) {
        return "CtRecord";
    }
    if isinstance(v, CtEnumMember) {
        return "CtEnumMember";
    }
    return "CtDeferred";
}

impl ct_truthy(v: CtValue) -> bool {
    if isinstance(v, CtNone) {
        return False;
    }
    if isinstance(v, CtBool) {
        return v.value;
    }
    if isinstance(v, CtInt) {
        return v.value != 0;
    }
    if isinstance(v, CtFloat) {
        return v.value != 0.0;
    }
    if isinstance(v, CtStr) {
        return len(v.value) > 0;
    }
    if isinstance(v, CtBytes) {
        return len(v.value) > 0;
    }
    if isinstance(v, (CtTuple, CtList)) {
        return len(v.items) > 0;
    }
    if isinstance(v, CtDict) {
        return len(v.keys) > 0;
    }
    if isinstance(v, CtSet) {
        return len(v.items) > 0;
    }
    if isinstance(v, CtRange) {
        return range_len(v) > 0;
    }
    if isinstance(v, CtView) {
        return len(v.source.keys) > 0;
    }
    return True;
}

impl _float_is_integral(f: float) -> bool {
    if f != f or f - f != 0.0 {
        return False;
    }
    if abs(f) >= 4503599627370496.0 {
        return True;
    }
    return float(int(f)) == f;
}

impl _len_prefixed(s: str) -> str {
    return str(len(s)) + ":" + s;
}

impl ct_key(v: CtValue) -> str {
    if isinstance(v, CtNone) {
        return "N";
    }
    if isinstance(v, CtBool) {
        return "i1" if v.value else "i0";
    }
    if isinstance(v, CtInt) {
        return "i" + format(v.value, "x");
    }
    if isinstance(v, CtFloat) {
        f = v.value;
        if f != f {
            return "fnan";
        }
        if _float_is_integral(f) {
            return "i" + format(int(f), "x");
        }
        return "f" + repr(f);
    }
    if isinstance(v, CtStr) {
        return "s" + _len_prefixed(v.value);
    }
    if isinstance(v, CtBytes) {
        return "b" + _len_prefixed(v.value.hex());
    }
    if isinstance(v, CtTuple) {
        parts: list[str] = [];
        for item in v.items {
            parts.append(_len_prefixed(ct_key(item)));
        }
        return "t" + "".join(parts);
    }
    if isinstance(v, CtSet) and v.frozen {
        parts2: list[str] = [];
        for item in v.items {
            parts2.append(_len_prefixed(ct_key(item)));
        }
        parts2.sort();
        return "F" + "".join(parts2);
    }
    if isinstance(v, CtRange) {
        n = range_len(v);
        if n == 0 {
            return "R0";
        }
        if n == 1 {
            return f"R1:{v.start}";
        }
        return f"R{n}:{v.start}:{v.step}";
    }
    if isinstance(v, CtType) {
        return "T" + _len_prefixed(v.module) + v.name;
    }
    if isinstance(v, CtEnumMember) {
        return "E" + _len_prefixed(v.enum_name) + v.member;
    }
    if isinstance(v, CtFunc) {
        return "C" + _len_prefixed(v.module) + v.qualname;
    }
    if isinstance(v, CtBuiltin) {
        return "B" + v.name;
    }
    if isinstance(v, CtModule) {
        return "M" + v.name;
    }
    if isinstance(v, (CtExc, CtBound, CtMethod, CtDeferred)) {
        raise CtError(
            f"a '{ct_type_name(
                v
            )}' value cannot be a dict key or set element in comptime code"
        );
    }
    raise ct_exc("TypeError", f"unhashable type: '{_unhashable_name(v)}'");
}

impl float_to_ct_int(f: float) -> CtInt {
    try {
        return CtInt(value=int(f));
    } except (ValueError, OverflowError) as e {
        raise ct_py_exc(e);
    }
}

impl ct_same_or_eq(a: CtValue, b: CtValue) -> bool {
    return a is b or ct_eq(a, b);
}

impl ct_eq(a: CtValue, b: CtValue) -> bool {
    if isinstance(a, (CtBool, CtInt, CtFloat))
        and isinstance(b, (CtBool, CtInt, CtFloat)) {
        return a.value == b.value;
    }
    if isinstance(a, CtFloat) or isinstance(b, CtFloat) {
        return False;
    }
    if isinstance(a, CtNone) or isinstance(b, CtNone) {
        return isinstance(a, CtNone) and isinstance(b, CtNone);
    }
    if isinstance(a, CtStr) {
        return isinstance(b, CtStr) and a.value == b.value;
    }
    if isinstance(a, CtBytes) {
        return isinstance(b, CtBytes) and a.value == b.value;
    }
    if isinstance(a, CtList) {
        return isinstance(b, CtList) and _items_eq(a.items, b.items);
    }
    if isinstance(a, CtTuple) {
        return isinstance(b, CtTuple) and _items_eq(a.items, b.items);
    }
    if isinstance(a, CtDict) {
        if not isinstance(b, CtDict) or len(a.keys) != len(b.keys) {
            return False;
        }
        for (i, k) in enumerate(a.keys) {
            other = dict_get(b, k);
            if other is None or not ct_same_or_eq(a.vals[i], other) {
                return False;
            }
        }
        return True;
    }
    if isinstance(a, CtSet) {
        if not isinstance(b, CtSet) or len(a.items) != len(b.items) {
            return False;
        }
        for item in a.items {
            if not set_has(b, item) {
                return False;
            }
        }
        return True;
    }
    if isinstance(a, CtRange) {
        if not isinstance(b, CtRange) {
            return False;
        }
        n = range_len(a);
        if n != range_len(b) {
            return False;
        }
        if n == 0 {
            return True;
        }
        if a.start != b.start {
            return False;
        }
        return n == 1 or a.step == b.step;
    }
    if isinstance(a, CtView) {
        if not isinstance(b, CtView) or a.kind == "values" or b.kind == "values" {
            return a is b;
        }
        return ct_eq(view_items_set(a), view_items_set(b));
    }
    if isinstance(a, CtType) {
        return isinstance(b, CtType) and a.name == b.name and a.module == b.module;
    }
    if isinstance(a, CtEnumMember) {
        return (
            isinstance(b, CtEnumMember)
            and a.enum_name == b.enum_name
            and a.member == b.member
        );
    }
    if isinstance(a, CtFunc) {
        return (
            isinstance(b, CtFunc) and a.qualname == b.qualname and a.module == b.module
        );
    }
    if isinstance(a, CtRecord) {
        if not isinstance(b, CtRecord) or a.class_name != b.class_name {
            return False;
        }
        if len(a.fields) != len(b.fields) {
            return False;
        }
        for (k, av) in a.fields.items() {
            if k not in b.fields or not ct_same_or_eq(av, b.fields[k]) {
                return False;
            }
        }
        return True;
    }
    if isinstance(a, CtBuiltin) {
        return isinstance(b, CtBuiltin) and a.name == b.name;
    }
    if isinstance(a, CtModule) {
        return isinstance(b, CtModule) and a.name == b.name;
    }
    if isinstance(a, CtMethod) {
        return (
            isinstance(b, CtMethod)
            and a.owner == b.owner
            and a.name == b.name
            and a.recv is b.recv
        );
    }
    return a is b;
}

impl _items_eq(a: list[CtValue], b: list[CtValue]) -> bool {
    if len(a) != len(b) {
        return False;
    }
    for i in range(len(a)) {
        if not ct_same_or_eq(a[i], b[i]) {
            return False;
        }
    }
    return True;
}

impl view_items_set(v: CtView) -> CtSet {
    out = CtSet(items=[], index={}, frozen=False);
    if v.kind == "keys" {
        for k in v.source.keys {
            set_add(out, k);
        }
    } else {
        for (i, k) in enumerate(v.source.keys) {
            set_add(out, mk_tuple([k, v.source.vals[i]]));
        }
    }
    return out;
}

impl bytes_has(data: bytes, byte: int) -> bool {
    for b in data {
        if b == byte {
            return True;
        }
    }
    return False;
}

impl bytes_repr(data: bytes) -> str {
    quote = "'";
    if bytes_has(data, 39) and not bytes_has(data, 34) {
        quote = "\"";
    }
    out = "b" + quote;
    hexd = "0123456789abcdef";
    for byte in data {
        if byte == ord(quote) or byte == 92 {
            out += "\\" + chr(byte);
        } elif byte == 9 {
            out += "\\t";
        } elif byte == 10 {
            out += "\\n";
        } elif byte == 13 {
            out += "\\r";
        } elif byte < 32 or byte >= 127 {
            out += "\\x" + hexd[byte >> 4] + hexd[byte & 15];
        } else {
            out += chr(byte);
        }
    }
    return out + quote;
}

impl ct_repr(v: CtValue) -> str {
    return _repr_in(v, []);
}

impl _seen_in(v: CtValue, seen: list[CtValue]) -> bool {
    for s in seen {
        if s is v {
            return True;
        }
    }
    return False;
}

impl _repr_items(items: list[CtValue], seen: list[CtValue]) -> str {
    parts: list[str] = [];
    for item in items {
        parts.append(_repr_in(item, seen));
    }
    return ", ".join(parts);
}

impl _repr_in(v: CtValue, seen: list[CtValue]) -> str {
    if isinstance(v, CtNone) {
        return "None";
    }
    if isinstance(v, CtBool) {
        return "True" if v.value else "False";
    }
    if isinstance(v, CtInt) {
        return int_decimal(v.value);
    }
    if isinstance(v, CtFloat) {
        return repr(v.value);
    }
    if isinstance(v, CtStr) {
        return repr(v.value);
    }
    if isinstance(v, CtBytes) {
        return bytes_repr(v.value);
    }
    if isinstance(v, CtRange) {
        if v.step == 1 {
            return f"range({v.start}, {v.stop})";
        }
        return f"range({v.start}, {v.stop}, {v.step})";
    }
    if isinstance(v, (CtList, CtTuple, CtDict, CtSet, CtView, CtRecord)) {
        if _seen_in(v, seen) {
            if isinstance(v, CtList) {
                return "[...]";
            }
            if isinstance(v, CtDict) {
                return "{...}";
            }
            return "...";
        }
        seen.append(v);
        try {
            return _repr_container(v, seen);
        } finally {
            seen.pop();
        }
    }
    if isinstance(v, CtType) {
        return f"<type {v.name}>";
    }
    if isinstance(v, CtFunc) {
        return f"<function {v.module}.{v.qualname}>";
    }
    if isinstance(v, CtEnumMember) {
        return f"{v.enum_name}.{v.member}";
    }
    if isinstance(v, CtBound) {
        name = v.ability.name_ref.sym_name if v.ability.name_ref else "unnamed";
        return f"<bound method {name} of {_repr_in(v.self_val, seen)}>";
    }
    if isinstance(v, CtBuiltin) {
        return f"<built-in function {v.name}>";
    }
    if isinstance(v, CtMethod) {
        if v.recv is None {
            return f"<method '{v.name}' of '{v.owner}' objects>";
        }
        return f"<built-in method {v.name} of {v.owner} object>";
    }
    if isinstance(v, CtModule) {
        return f"<module '{v.name}' (built-in)>";
    }
    if isinstance(v, CtExc) {
        return v.kind + "(" + _repr_items(v.args, seen) + ")";
    }
    return "<comptime deferred>";
}

impl _repr_container(v: CtValue, seen: list[CtValue]) -> str {
    if isinstance(v, CtList) {
        return "[" + _repr_items(v.items, seen) + "]";
    }
    if isinstance(v, CtTuple) {
        if len(v.items) == 1 {
            return "(" + _repr_in(v.items[0], seen) + ",)";
        }
        return "(" + _repr_items(v.items, seen) + ")";
    }
    if isinstance(v, CtDict) {
        parts: list[str] = [];
        for (i, k) in enumerate(v.keys) {
            parts.append(_repr_in(k, seen) + ": " + _repr_in(v.vals[i], seen));
        }
        return "{" + ", ".join(parts) + "}";
    }
    if isinstance(v, CtSet) {
        if not v.items {
            return "frozenset()" if v.frozen else "set()";
        }
        body = "{" + _repr_items(v.items, seen) + "}";
        return f"frozenset({body})" if v.frozen else body;
    }
    if isinstance(v, CtView) {
        src = v.source;
        parts2: list[str] = [];
        for (i, k) in enumerate(src.keys) {
            if v.kind == "keys" {
                parts2.append(_repr_in(k, seen));
            } elif v.kind == "values" {
                parts2.append(_repr_in(src.vals[i], seen));
            } else {
                parts2.append(
                    "(" + _repr_in(k, seen) + ", " + _repr_in(src.vals[i], seen) + ")"
                );
            }
        }
        return f"dict_{v.kind}([" + ", ".join(parts2) + "])";
    }
    if isinstance(v, CtRecord) {
        parts3: list[str] = [];
        for (k, fv) in v.fields.items() {
            parts3.append(f"{k}={_repr_in(fv, seen)}");
        }
        return f"{v.class_name}(" + ", ".join(parts3) + ")";
    }
    return "";
}

impl ct_str(v: CtValue) -> str {
    if isinstance(v, CtStr) {
        return v.value;
    }
    if isinstance(v, CtExc) {
        if not v.args {
            return "";
        }
        if len(v.args) == 1 {
            if v.kind == "KeyError" {
                return ct_repr(v.args[0]);
            }
            return ct_str(v.args[0]);
        }
        return ct_repr(mk_tuple(v.args));
    }
    return ct_repr(v);
}

impl ct_iter(v: CtValue) -> list[CtValue] {
    if isinstance(v, (CtList, CtTuple)) {
        return v.items.copy();
    }
    if isinstance(v, CtStr) {
        out: list[CtValue] = [];
        for ch in v.value {
            out.append(mk_str(ch));
        }
        return out;
    }
    if isinstance(v, CtBytes) {
        out2: list[CtValue] = [];
        for byte in v.value {
            out2.append(CtInt(value=byte));
        }
        return out2;
    }
    if isinstance(v, CtDict) {
        return v.keys.copy();
    }
    if isinstance(v, CtSet) {
        return v.items.copy();
    }
    if isinstance(v, CtRange) {
        out3: list[CtValue] = [];
        cur = v.start;
        for _ in range(range_len(v)) {
            out3.append(mk_int(cur));
            cur += v.step;
        }
        return out3;
    }
    if isinstance(v, CtView) {
        src = v.source;
        if v.kind == "keys" {
            return src.keys.copy();
        }
        if v.kind == "values" {
            return src.vals.copy();
        }
        out4: list[CtValue] = [];
        for (i, k) in enumerate(src.keys) {
            out4.append(mk_tuple([k, src.vals[i]]));
        }
        return out4;
    }
    if isinstance(v, CtDeferred) {
        raise CtDeferredSignal();
    }
    raise ct_exc("TypeError", f"'{ct_type_name(v)}' object is not iterable");
}

impl ct_is_iterable(v: CtValue) -> bool {
    return isinstance(
        v, (CtList, CtTuple, CtStr, CtBytes, CtDict, CtSet, CtRange, CtView)
    );
}

impl ct_len(v: CtValue) -> int {
    if isinstance(v, (CtList, CtTuple)) {
        return len(v.items);
    }
    if isinstance(v, CtStr) {
        return len(v.value);
    }
    if isinstance(v, CtBytes) {
        return len(v.value);
    }
    if isinstance(v, CtDict) {
        return len(v.keys);
    }
    if isinstance(v, CtSet) {
        return len(v.items);
    }
    if isinstance(v, CtRange) {
        return range_len(v);
    }
    if isinstance(v, CtView) {
        return len(v.source.keys);
    }
    raise ct_exc("TypeError", f"object of type '{ct_type_name(v)}' has no len()");
}

impl ct_is_scalar(v: CtValue) -> bool {
    return isinstance(v, (CtNone, CtBool, CtInt, CtFloat, CtStr, CtBytes));
}

impl ct_is_materializable(v: CtValue) -> bool {
    if ct_is_scalar(v) {
        return True;
    }
    if isinstance(v, (CtEnumMember, CtType, CtFunc)) {
        return True;
    }
    if isinstance(v, (CtList, CtTuple)) {
        for item in v.items {
            if not ct_is_materializable(item) {
                return False;
            }
        }
        return True;
    }
    if isinstance(v, CtSet) {
        for item in v.items {
            if not ct_is_materializable(item) {
                return False;
            }
        }
        return True;
    }
    if isinstance(v, CtDict) {
        for (i, k) in enumerate(v.keys) {
            if not ct_is_materializable(k) or not ct_is_materializable(v.vals[i]) {
                return False;
            }
        }
        return True;
    }
    if isinstance(v, CtRecord) {
        for item in v.fields.values() {
            if not ct_is_materializable(item) {
                return False;
            }
        }
        return True;
    }
    return False;
}

impl ct_host_scalar(v: CtValue) -> (int | float | str | bytes | bool | None) {
    if isinstance(v, CtBool) {
        return v.value;
    }
    if isinstance(v, CtInt) {
        return v.value;
    }
    if isinstance(v, CtFloat) {
        return v.value;
    }
    if isinstance(v, CtStr) {
        return v.value;
    }
    if isinstance(v, CtBytes) {
        return v.value;
    }
    return None;
}

impl _fnv32(data: bytes, seed: int) -> int {
    h = seed;
    for byte in data {
        h = ((h ^ byte) * 16777619) & 4294967295;
    }
    return h;
}

impl ct_mangle(v: CtValue) -> str {
    if isinstance(v, CtBool) {
        return "b1" if v.value else "b0";
    }
    if isinstance(v, CtInt) {
        text = int_decimal(v.value);
        return "n" + text[1:] if text.startswith("-") else "i" + text;
    }
    if isinstance(v, CtFloat) {
        return "f" + repr(v.value).replace(".", "_").replace("-", "n").replace("+", "");
    }
    if isinstance(v, CtStr) {
        return "s" + "".join([c if c.isalnum() else f"_{ord(c)}_" for c in v.value]);
    }
    if isinstance(v, CtNone) {
        return "N";
    }
    if isinstance(v, CtEnumMember) {
        return f"e{v.enum_name}_{v.member}";
    }
    if isinstance(v, CtType) {
        return f"t{v.name}";
    }
    if isinstance(v, CtFunc) {
        return f"fn{v.qualname}";
    }
    if isinstance(v, (CtList, CtTuple)) {
        return "L" + "_".join([ct_mangle(x) for x in v.items]) + "_";
    }
    data = ct_repr(v).encode("utf-8");
    return "x"
        + format(_fnv32(data, 2166136261), "08x")
        + format(_fnv32(data, 3735928559), "08x");
}

impl CtValue.is_deferred.getter -> bool {
    return isinstance(self, CtDeferred);
}
