"""Native placement is declared, and a declared-native module is analyzed once.

What only one codespace has is recorded on the typed module as a requirement
or a refusal, and the placement pass reads those for every element that is
native. The tree it placed is the tree every backend reads: nothing types the
module again. Anything a declared-native element cannot lower, whether the
analysis or only the backend sees it, is a located error; nothing falls back
to Python. A backend crash is a compiler error."""

import os;
import tempfile;
import from jaclang.compiler.driver.program { JacProgram }
import from jaclang.compiler.driver.compile_options { CompileOptions }
import jaclang.compiler.frontend.unitree as uni;
import from jaclang.compiler.frontend.codeinfo { InteropBinding, InteropContext }
import from jaclang.compiler.capability_notes { capability_notes_of }
import from jaclang.compiler.driver.session_compile { drop_native_bindings }
import from jaclang.compiler.placement.placement_solver { invalidate_importers_es }
import from tests.support { JAC_ROOT }

glob PIN_FIXTURE_DIR = os.path.join(
         JAC_ROOT, "tests", "compiler", "fixtures", "codespace", "native_demoted_pin"
     ),
     SEAM_SRC = (
         "def helper(x: int) -> str {\n"
         "    s = \"abc\";\n"
         "    return f\"{s!a}{x}\";\n"
         "}\n\n"
         "def other(x: int) -> int {\n"
         "    return x * 2;\n"
         "}\n\n"
         "def mid(x: int) -> str {\n"
         "    return helper(other(x));\n"
         "}\n\n"
     ),
     REACHING_ENTRY = "with entry {\n    print(other(2));\n    print(mid(3));\n}\n",
     LATE_SRC = (
         "def other(x: int) -> int {\n"
         "    return x * 2;\n"
         "}\n\n"
         "with entry {\n"
         "    s = {1, \"a\"};\n"
         "    print(other(2), len(s));\n"
         "}\n"
     ),
     CLEAN_SRC = (
         "def other(x: int) -> int {\n"
         "    return x * 2;\n"
         "}\n\n"
         "with entry {\n"
         "    print(other(2));\n"
         "}\n"
     ),
     STRICT_SRC = (
         "def run(t: any, x: int) -> int {\n"
         "    if x in t {\n"
         "        return 1;\n"
         "    }\n"
         "    return 0;\n"
         "}\n\n"
         "def narrow(x: int | None) -> int {\n"
         "    if x < 5 {\n"
         "        return 1;\n"
         "    }\n"
         "    return 0;\n"
         "}\n\n"
         "def other(x: int) -> int {\n"
         "    return x * 2;\n"
         "}\n\n"
         "with entry {\n"
         "    print(other(2));\n"
         "}\n"
     ),
     TOKEN_SRC = (
         "import from contextvars { ContextVar, Token }\n\n"
         "def double(n: int) -> int {\n"
         "    return n * 2;\n"
         "}\n\n"
         "with entry {\n"
         "    print(double(2));\n"
         "}\n"
     ),
     PINNED_METHOD_SRC = (
         "obj Foo {\n"
         "    has n: int = 1;\n\n"
         "    def size -> int {\n"
         "        s = \"x\";\n"
         "        return len(f\"{s!a}\") + self.n;\n"
         "    }\n"
         "}\n\n"
         "with entry {\n"
         "    print(Foo().size());\n"
         "}\n"
     ),
     PINNED_LATE_METHOD_SRC = (
         "import json;\n\n"
         "def pretty(x: dict[str, int]) -> str {\n"
         "    return json.dumps(x, indent=2);\n"
         "}\n\n"
         "obj Foo {\n"
         "    has n: int = 1;\n\n"
         "    def size -> int {\n"
         "        s = {1, \"a\"};\n"
         "        return len(s) + self.n;\n"
         "    }\n"
         "}\n\n"
         "with entry {\n"
         "    print(Foo().size());\n"
         "}\n"
     ),
     OVERLOAD_STUB = (
         "from typing import Callable, overload\n"
         "@overload\n"
         "def run(a: int, b: str) -> int: ...\n"
         "@overload\n"
         "def run(a: Callable[[int], int], b: int) -> int: ...\n"
     ),
     OVERLOAD_SRC = (
         "import choices;\n\n"
         "def inc(x: int) -> int {\n"
         "    return x + 1;\n"
         "}\n\n"
         "def by_callable -> int {\n"
         "    return choices.run(inc, 3);\n"
         "}\n\n"
         "def by_address -> int {\n"
         "    return choices.run(inc, \"x\");\n"
         "}\n"
     ),
     NATIVE_ONLY_SRC = (
         "def size(f: File) -> int {\n"
         "    s = \"x\";\n"
         "    return len(f\"{s!a}\");\n"
         "}\n\n"
         "with entry {\n"
         "    print(1);\n"
         "}\n"
     );

"""Compile `text` under the native default, counting how often it is parsed."""
def compile_native_default(text: str) -> tuple[JacProgram, uni.Module, str, int] {
    import from unittest.mock { patch }
    import from jaclang.compiler.frontend.codeinfo {
        set_effective_default_codespace,
        get_effective_default_codespace_override
    }
    path = os.path.realpath(os.path.join(tempfile.mkdtemp(), "m.jac"));
    with open(path, "w", encoding="utf-8") as fh {
        fh.write(text);
    }
    real_parse: any = getattr(JacProgram, "parse_source");
    parsed: list[str] = [];
    def count_parse(this: JacProgram, *args: any, **kwargs: any) -> uni.Module {
        parsed.append(os.path.realpath(str(args[1])));
        return real_parse(this, *args, **kwargs);
    }
    previous = get_effective_default_codespace_override();
    prog = JacProgram();
    try {
        with patch.object(JacProgram, "parse_source", count_parse) {
            mod = prog.compile(
                path, options=CompileOptions(default_codespace="native")
            );
        }
    } finally {
        set_effective_default_codespace(previous);
    }
    return (prog, mod, path, parsed.count(path));
}

"""Where each top-level function and the entry block were placed."""
def placed_by_name(mod: uni.Module) -> dict[str, str] {
    out: dict[str, str] = {};
    for stmt in mod.body {
        if isinstance(stmt, uni.Ability) and stmt.name_ref is not None {
            out[stmt.name_ref.sym_name] = stmt.code_context.value;
        } elif isinstance(stmt, uni.ModuleCode) {
            out["entry"] = stmt.code_context.value;
        }
    }
    return out;
}

"""The errors reported at a location in `path`."""
def errors_at(prog: JacProgram, path: str) -> list[any] {
    return [
        e
        for e in prog.errors_had
        if e.loc is not None and os.path.realpath(e.loc.mod_path) == path
    ];
}

test "a declared native module is analyzed once" {
    (prog, mod, path, parses) = compile_native_default(CLEAN_SRC);
    assert not prog.errors_had , f"{[str(e) for e in prog.errors_had]}";
    assert parses == 1 , f"placement needs no second analysis, got {parses}";
    assert mod.decided_codespace == 'native';
    assert mod.gen.llvm_ir is not None;
}

test "what a declared-native element cannot lower is a located error, not a fallback" {
    (prog, mod, path, parses) = compile_native_default(SEAM_SRC + REACHING_ENTRY);
    errs = errors_at(prog, path);
    assert errs , (
        f"`helper` cannot lower natively, so the build must fail: {[
            str(e) for e in prog.errors_had
        ]}"
    );
    assert any(e.loc.first_line == 3 for e in errs) , (
        f"the error must point at the construct in `helper`: {[str(e) for e in errs]}"
    );
}

test "a refusal only the backend can see is a located error" {
    (prog, mod, path, parses) = compile_native_default(LATE_SRC);
    errs = errors_at(prog, path);
    assert errs , (
        f"the backend's refusal must fail the build, not move the module: {[
            str(e) for e in prog.errors_had
        ]}"
    );
}

test "native lowering reads user and native-library trees, not the compiler's own" {
    import jaclang;
    import from jaclang.compiler.driver.ifacecache { native_lowering_reads }
    pkg = os.path.dirname(os.path.realpath(jaclang.__file__));
    assert not native_lowering_reads(
        os.path.join(pkg, "compiler", "frontend", "unitree.jac")
    );
    assert native_lowering_reads(os.path.join(pkg, "runtime", "na_stdlib", "json.jac"));
    assert native_lowering_reads(os.path.join(tempfile.mkdtemp(), "app.jac"));
}

test "a finding that only matters natively keeps its own code where native is required" {
    path = os.path.realpath(os.path.join(tempfile.mkdtemp(), "strict.jac"));
    with open(path, "w", encoding="utf-8") as fh {
        fh.write(STRICT_SRC);
    }
    forced = JacProgram();
    forced.compile(
        path, options=CompileOptions(force_codespace="native", no_cgen=True)
    );
    codes = [
        e.code.code
        for e in forced.errors_had
        if e.code is not None
    ];
    assert "E1124" in codes and "E1121" in codes , (
        f"forced native must report the recorded findings under their own "
        f"codes: {[str(e) for e in forced.errors_had]}"
    );
}

test "a native-only construct in code that cannot be placed native is an error" {
    path = os.path.realpath(os.path.join(tempfile.mkdtemp(), "m.jac"));
    with open(path, "w", encoding="utf-8") as fh {
        fh.write(NATIVE_ONLY_SRC);
    }
    prog = JacProgram();
    prog.compile(path);
    unmet = [
        e
        for e in prog.errors_had
        if e.code is not None and e.code.code == "E5090" and "native-only" in str(e)
    ];
    assert unmet , f"expected the unmet native requirement: {[
        str(e) for e in prog.errors_had
    ]}";
    assert "cannot be placed native" in (unmet[0].help_text or "");
}

test "a backend crash is a compiler error, never a placement decision" {
    import from unittest.mock { patch }
    import from jaclang.compiler.backends.native.na_ir_gen_pass { NaIRGenPass }
    real_body: any = NaIRGenPass._codegen_body;
    calls: list[int] = [];
    def crash_once(this: NaIRGenPass, *args: any) {
        calls.append(1);
        if len(calls) == 1 {
            raise RuntimeError("boom");
        }
        real_body(this, *args);
    }
    with patch.object(NaIRGenPass, "_codegen_body", crash_once) {
        (prog, mod, path, parses) = compile_native_default(CLEAN_SRC);
    }
    crashes = [
        e
        for e in prog.errors_had
        if e.code is not None and e.code.code == "E9003"
    ];
    assert crashes , f"a backend crash must surface as E9003: {[
        str(e) for e in prog.errors_had
    ]}";
    assert "boom" in str(crashes[0]);
    assert not [
        e
        for e in prog.errors_had
        if e.code is not None and e.code.code == "E5092"
    ] , "a crash must not read as a refusal";
    assert mod.decided_codespace == 'native' , "a crash must not move the module";
    assert mod.gen.jcir is None , "a crashed module must keep nothing to run";
}

test "a native type alias is something the native library provides" {
    (prog, mod, path, parses) = compile_native_default(TOKEN_SRC);
    assert not prog.errors_had , f"{[str(e) for e in prog.errors_had]}";
    placed = placed_by_name(mod);
    assert placed["double"] == 'native' , (
        f"importing the native contextvars' Token alias keeps the module "
        f"native: {placed}"
    );
}

"""Compile `text` as m.jac in a project that pins `m.Foo` native."""
def compile_pinned_foo(text: str) -> JacProgram {
    base = tempfile.mkdtemp();
    with open(os.path.join(base, "jac.toml"), "w", encoding="utf-8") as fh {
        fh.write(
            '[project]\nname = "pinned-method"\n\n[placement.pins]\n"m.Foo" = "native"\n'
        );
    }
    path = os.path.realpath(os.path.join(base, "m.jac"));
    with open(path, "w", encoding="utf-8") as fh {
        fh.write(text);
    }
    prog = JacProgram();
    prog.compile(path);
    return prog;
}

test "a refusal inside an element pinned native is an error" {
    prog = compile_pinned_foo(PINNED_METHOD_SRC);
    assert any("must be native" in (e.help_text or "") for e in prog.errors_had) , f"a method of a pinned archetype that cannot lower is an error: {[
        str(e) for e in prog.errors_had
    ]}";
}

test "a late refusal inside an element pinned native is an error" {
    prog = compile_pinned_foo(PINNED_LATE_METHOD_SRC);
    assert any("mixed element types" in str(e) for e in prog.errors_had) , (
        f"a method of a pinned archetype that refuses during lowering keeps its "
        f"error: {[str(e) for e in prog.errors_had]}"
    );
}

test "an overload the call does not select records no native requirement" {
    import from unittest.mock { patch }
    import from jaclang.compiler.types.type_evaluator { TypeEvaluator }
    base = tempfile.mkdtemp();
    with open(os.path.join(base, "choices.pyi"), "w", encoding="utf-8") as fh {
        fh.write(OVERLOAD_STUB);
    }
    path = os.path.realpath(os.path.join(base, "main.jac"));
    with open(path, "w", encoding="utf-8") as fh {
        fh.write(OVERLOAD_SRC);
    }
    prog = JacProgram();
    with patch.object(
        TypeEvaluator, "neutral_site", lambda (this: any, nd: any) { True }
    ) {
        prog.compile(path, options=CompileOptions(no_cgen=True));
    }
    owners: set[str] = set();
    for note in capability_notes_of(prog, path, "native") {
        if not note.requires {
            continue;
        }
        cur: (uni.UniNode | None) = note.site;
        while cur is not None and not isinstance(cur, uni.Ability) {
            cur = cur.parent;
        }
        if isinstance(cur, uni.Ability) and cur.name_ref is not None {
            owners.add(cur.name_ref.sym_name);
        }
    }
    assert "by_address" in owners , (
        f"the selected (int, str) overload takes the function as an address: {owners}"
    );
    assert "by_callable" not in owners , (
        f"the (int, str) overload was only tried; (Callable, int) was selected: {owners}"
    );
}

test "importer invalidation clears ES output and NATIVE bindings" {
    prog = JacProgram();
    app = prog.compile(os.path.join(PIN_FIXTURE_DIR, "app.jac"));
    assert not prog.errors_had , f"{[str(e) for e in prog.errors_had]}";
    models_path = os.path.realpath(os.path.join(PIN_FIXTURE_DIR, "models.jac"));
    app.gen.js = "stale na glue";
    manifest = app.gen.interop_manifest;
    manifest.bindings["double"] = InteropBinding(
        name="double",
        source_context=InteropContext.NATIVE,
        callers={InteropContext.CLIENT},
        source_module=models_path
    );
    manifest.bindings["unrelated"] = InteropBinding(
        name="unrelated",
        source_context=InteropContext.SERVER,
        callers={InteropContext.CLIENT},
        source_module=models_path
    );
    cleared = invalidate_importers_es(prog, models_path);
    assert app in cleared , "the importer must be found by the hub walk";
    assert app.gen.js == "" , "stale ES output must be cleared";
    for m in cleared {
        drop_native_bindings(m, models_path);
    }
    assert "double" not in manifest.bindings , "the NATIVE binding naming the module must be dropped";
    assert "unrelated" in manifest.bindings , "bindings in other contexts must survive";
}
