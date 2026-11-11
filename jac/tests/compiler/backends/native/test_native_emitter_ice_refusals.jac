"""Previously crashing argument shapes either execute or report a checked refusal."""

import os;
import ctypes;
import tempfile;
import from tests.support { native_str_func }
import from jaclang.compiler.driver.compile_options { CompileOptions }
import from jaclang.compiler.driver.program { JacProgram }
import from tests.support { JAC_ROOT }

glob FIXTURES = os.path.join(
         JAC_ROOT, "tests", "compiler", "backends", "native", "fixtures"
     ),
     FIXTURE = "emitter_ice_refusals.jac";

"""Compile `src` natively from a temporary file and return its errors."""
def probe_errors(src: str) -> list[any] {
    with tempfile.TemporaryDirectory() as tmp {
        path = os.path.join(tmp, "arg_shape_probe.jac");
        with open(path, "w") as f {
            f.write(src);
        }
        prog = JacProgram();
        prog.compile(file_path=path, options=CompileOptions(force_codespace='native'));
        return list(prog.errors_had or []);
    }
}


test "tuple prefixes lower and match the correct strings" {
    prog = JacProgram();
    ir = prog.compile(
        file_path=os.path.join(FIXTURES, FIXTURE),
        options=CompileOptions(force_codespace='native')
    );
    assert not prog.errors_had , [str(e) for e in prog.errors_had];
    check = native_str_func(
        ir.gen.native_engine, "tuple_startswith", ctypes.c_int64, ctypes.c_char_p
    );
    assert check(b"'quoted") == 1;
    assert check(b'"quoted') == 1;
    assert check(b"plain") == 0;
    assert check(b"") == 0;
}


test "a mismatched call argument is the checker's refusal, not the emitter's" {
    # With type checking on the critical path a plainly-typed mismatch never
    # reaches codegen: the checker names the parameter at check time.
    holder = (
        "obj Holder { has n: int = 0; }\n"
        + "def takes_holder(h: Holder) -> int { return h.n; }\n"
    );
    errors = probe_errors(
        holder + "def arg_shape_mismatch(s: str) -> int { return takes_holder(s); }\n"
    );
    hits = [
        str(e)
        for e in errors
        if e.code is not None and e.code.code == "E1053" and "'h'" in str(e)
    ];
    assert hits , (
        "the direct mismatch must be refused at check time naming the "
        f"parameter, got: {[str(e) for e in errors]}"
    );
    # Through an `any` box the type is lost upstream, so the shape reaches
    # the emitter: it must lower or refuse by name, never crash the builder.
    errors = probe_errors(
        holder
        + "def arg_shape_mismatch(s: str) -> int {\n"
        + "    _s: any = s;\n"
        + "    return takes_holder(_s);\n"
        + "}\n"
    );
    assert all(
        e.code is not None and e.code.code in ("E5090", "E5092") for e in errors
    ) , f"the boxed argument must lower or be a located refusal: {[str(e) for e in errors]}";
}
