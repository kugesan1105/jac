"""Tuple values meeting variadic slots and range subscripts natively.

A fixed-arity tuple stored into a `tuple[Any, ...]` slot is boxed element by
element into the slot's sequence instead of being bitcast into it, and a range
subscript the native backend cannot slice is refused instead of being lowered
as an index read at the range's start.
"""

import ctypes;
import os;
import from tests.support { TESTS_DIR, compile_native, get_func }
import from jaclang.compiler.driver.compile_options { CompileOptions }
import from jaclang.compiler.driver.program { JacProgram }

glob FIXTURES = os.path.join(
         TESTS_DIR, "compiler", "backends", "native", "fixtures"
     ),
     _ENG: list[any] = [];

def _engine -> any {
    if not _ENG {
        (eng, _) = compile_native("struct_unpack_variadic.jac");
        get_func(eng, "jac_entry", None)();
        _ENG.append(eng);
    }
    return _ENG[0];
}

test "an unpacked tuple in an entry global keeps its length and elements" {
    eng = _engine();
    assert get_func(eng, "entry_len", ctypes.c_int64)() == 2;
    assert get_func(eng, "entry_second", ctypes.c_double)() == 2.5;
}

test "a slice of an unpacked tuple in an entry global is not empty" {
    eng = _engine();
    assert get_func(eng, "entry_head_len", ctypes.c_int64)() == 1;
    assert get_func(eng, "entry_head", ctypes.c_double)() == 1.5;
    assert get_func(eng, "zeros_head_len", ctypes.c_int64)() == 1;
}

test "mixed int and float fields box into the variadic slot" {
    eng = _engine();
    assert get_func(eng, "mixed_sum", ctypes.c_double)() == 11.5;
}

test "an annotated variadic local holds every unpacked field" {
    eng = _engine();
    assert get_func(eng, "local_tail_len", ctypes.c_int64)() == 2;
}

test "a slice of a None-narrowed optional string still lowers" {
    eng = _engine();
    assert get_func(eng, "narrowed_str_tail", ctypes.c_int64)() == 3;
}

test "a fixed tuple slice is refused rather than read as an index" {
    path = os.path.join(FIXTURES, "tuple_slice_refusal.jac");
    prog = JacProgram();
    prog.compile(file_path=path, options=CompileOptions(force_codespace='native'));
    errors = [str(e) for e in prog.errors_had];
    assert any(
        e.code is not None
        and e.code.code in ("E5090", "E5092")
        and "slice" in e.msg
        and e.loc.first_line == 9
        for e in prog.errors_had
    ) , f"`t[1:3]` in tail_of_three must be a located refusal: {errors}";
}
