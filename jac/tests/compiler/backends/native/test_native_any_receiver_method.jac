"""A call over `any` values refuses loudly instead of vanishing."""

import os;
import from jaclang.compiler.driver.compile_options { CompileOptions }
import from jaclang.compiler.driver.program { JacProgram }
import from tests.support { JAC_ROOT }

glob FIXTURES = os.path.join(
         JAC_ROOT, "tests", "compiler", "backends", "native", "fixtures"
     ),
     FIXTURE = "any_receiver_method_refusal.jac";

glob _MEMO: list[any] = [];

"""Compile the fixture once and return its errors."""
def measured -> list[any] {
    if _MEMO {
        return _MEMO[0];
    }
    prog = JacProgram();
    prog.compile(
        file_path=os.path.join(FIXTURES, FIXTURE),
        options=CompileOptions(force_codespace='native')
    );
    out = list(prog.errors_had or []);
    _MEMO.append(out);
    return out;
}

"""The errors located inside the top-level `def name` of the fixture."""
def errors_in(errors: list[any], name: str) -> list[any] {
    with open(os.path.join(FIXTURES, FIXTURE)) as f {
        lines = f.read().splitlines();
    }
    starts = [
        i + 1
        for (i, line) in enumerate(lines)
        if line.startswith(f"def {name} ") or line.startswith(f"def {name}(")
    ];
    assert len(starts) == 1 , f"the fixture must define {name} once";
    start = starts[0];
    ends = [
        i
        for (i, line) in enumerate(lines)
        if i >= start and line.startswith("def ")
    ];
    end = ends[0] if ends else len(lines);
    return [e for e in errors if start <= e.loc.first_line <= end];
}


test "calls over any values are located errors in their callable" {
    errors = measured();
    for (fn, refusal) in [
        ("any_field_append", "on an `any` receiver"),
        ("any_field_bytearray_append", "on an `any` receiver"),
        ("any_param_count", "on an `any` receiver"),
        ("any_list_sorted", "builtin call 'sorted'"),
        ("any_list_sort", "'list[Any].sort'")
    ] {
        assert any(
            e.code is not None and e.code.code == "E5092" and refusal in e.msg
            for e in errors_in(errors, fn)
        ) , f"{fn} must refuse its call over `any` values, got: {[str(e) for e in errors]}";
    }
}


test "the concretely typed twins report no error" {
    errors = measured();
    assert not errors_in(errors, "typed_field_append") , [str(e) for e in errors];
}


test "a File parameter's methods lower without a preceding open" {
    # The File helpers used to be emitted only by `open()`, so `fp.read()` on
    # a parameter in a unit that never opens a file found no method and was
    # dropped silently.
    errors = measured();
    assert not errors_in(errors, "file_param_read") , [str(e) for e in errors];
}
