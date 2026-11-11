"""A `from`-import item is classified by the capability gate, like a bare import.

`native_capability_violations` walked an import statement's items and asked
`classify_native_import` for a module name. Only a `ModulePath` -- the
`import mod;` spelling -- ever produced one, so under forced-native placement
every `from` import was waved through without being classified at all.

That is the silent-miscompile class. `import from threading { Event }` with
`obj Holder(Event)` over it passed the gate, and the base is dropped by
`LayoutPass` on the way to a layout, so the module lowered to a `Holder` with
everything it inherits quietly missing. A refusal is the right answer, and it
is the answer the bare spelling of the same module already gave.

The placement pre-scan never had the hole: `scan_native_blockers` reads a
`from` import's module through `imp.from_loc` and refuses it there. So the fix
is to classify `ModuleItem` on the same terms the bare spelling gets, using the
compile-time vocabulary centralized in `codeinfo` -- and the pre-scan verdicts
must not move at all, which is pinned below.

The four ways a `from`-import item can be legitimate are each pinned here: a
compile-time name (`ABC`, `cast`, `TypeVar`, `TypeAlias`, `ClassVar`), a
lowered stdlib module, an na_stdlib-shimmed module, and another Jac module on
the native pathway. The vocabulary is per name and not per module, so a
compile-time module's non-erasable name still refuses.

Every refusal is a located error: a module-scope import is reported at the
import, and a body-scoped one at the import inside its owning function or
property accessor.
"""

import ctypes;
import os;
import from jaclang.compiler.passes.capability_check_pass {
    native_capability_violations
}
import from jaclang.compiler.driver.compile_options { CompileOptions }
import from jaclang.compiler.frontend.parser { parse as rd_parse }
import from jaclang.compiler.placement.placement { scan_native_blockers }
import from jaclang.compiler.driver.program { JacProgram }
import from tests.support { TESTS_DIR, native_address }

glob FIXTURES = os.path.join(
         TESTS_DIR, "compiler", "backends", "native", "fixtures"
     );


"""Forced-native compile options."""
def _opts -> CompileOptions {
    return CompileOptions(force_codespace='native');
}


"""Compile a fixture on the native pathway; return (program, module)."""
def _compile_native(fixture: str) -> tuple[any, ...] {
    prog = JacProgram();
    ir = prog.compile(file_path=os.path.join(FIXTURES, fixture), options=_opts());
    return (prog, ir, );
}


"""The `Python module import` names the capability gate rejects for a fixture."""
def _rejected_imports(fixture: str) -> list[str] {
    (_prog, ir) = _compile_native(fixture);
    assert ir is not None , f"{fixture} produced no module";
    return [
        str(v[2])
        for v in native_capability_violations(ir)
        if v[1] == "Python module import"
    ];
}


"""The placement solver's blocker verdict for a snippet, or 'OK' if it has none."""
def _scan_verdict(src: str) -> str {
    (mod, had_err) = rd_parse(
        src, os.path.join(FIXTURES, "from_import_probe.jac"), prog=JacProgram()
    );
    assert not had_err , f"fixture source did not parse: {src!r}";
    (reason, _deps) = scan_native_blockers(mod, FIXTURES, allow_pub=True);
    return reason or "OK";
}


"""Wrap an import line in a module the scanner accepts apart from the import."""
def _module_with(import_line: str) -> str {
    return import_line + "\n\nwith entry {\n    print(1);\n}\n";
}


"""The error codes a compiled program reported."""
def _codes(prog: any) -> list[str] {
    return [
        str(alrt.code.code)
        for alrt in prog.errors_had
        if alrt.code is not None
    ];
}


"""A JIT-resolved `int()` function from a compiled fixture."""
def _native_int_fn(ir: any, name: str) -> any {
    eng = ir.gen.native_engine;
    assert eng is not None , f"no native engine for '{name}'";
    addr = native_address(eng, name);
    assert addr != 0 , f"'{name}' is absent from the JIT engine";
    return ctypes.CFUNCTYPE(ctypes.c_int64)(addr);
}


test "a from-imported Python base is classified, not waved through" {
    assert _rejected_imports("from_import_retained_base.jac") == ["threading"] , (
        "the capability gate read the `from` import's items and found no "
        "module to classify, so an unlowerable Python base reached codegen "
        "unchallenged"
    );
}


test "the from-imported Python base refuses instead of lowering" {
    (prog, ir) = _compile_native("from_import_retained_base.jac");
    assert "E5090" in _codes(prog) , (
        "a module-scope Python `from` import has no owning callable to "
        f"absorb it, so it must keep the whole-module refusal, got: {[
            str(e) for e in prog.errors_had
        ]}"
    );
    assert any("threading" in str(e) for e in prog.errors_had) , (
        f"the diagnostic must name the module it refuses: {[
            str(e) for e in prog.errors_had
        ]}"
    );
    assert ir.gen.llvm_ir is None , (
        "a wrong binary is worse than a refusal: lowering `Holder` here "
        "drops everything it inherits from `Event` with no diagnostic"
    );
}


test "the pre-scan verdict on that import is unchanged" {
    assert _scan_verdict(_module_with("import from threading { Event }"))
        == "unresolved import 'threading'" , (
        "`scan_native_blockers` already refused this import through "
        "`imp.from_loc`; closing the forced-native hole must not move the "
        "pre-scan at all"
    );
}


test "a non-erasable name from a compile-time module still refuses" {
    assert _rejected_imports("from_import_abc_mixed.jac") == ["abc"] , (
        "the compile-time vocabulary is per name, not per module: `ABC` "
        "erases and `abstractmethod` does not, so listing both must refuse "
        "exactly as it does at placement"
    );
}


test "compile-time from-imports stay compile-time" {
    for fixture in [
        "abc_marker_base.jac",
        "typing_cast_identity.jac",
        "typing_typevar_glob.jac"
    ] {
        assert _rejected_imports(fixture) == [] , (
            "classifying `from`-import items must not refuse a name the "
            f"native lane erases: {fixture}"
        );
    }
}


test "a TypeAlias import no longer blocks native placement" {
    assert _scan_verdict(_module_with("import from typing { TypeAlias }")) == "OK" , (
        "native glob lowering already skips a `TypeAlias` assignment as a "
        "compile-time declaration; the import in front of it was all that "
        "still refused the module"
    );
}


test "a TypeAlias glob module lowers clean" {
    (prog, ir) = _compile_native("typing_type_alias_glob.jac");
    assert not prog.errors_had , f"{[str(e) for e in prog.errors_had]}";
    assert ir is not None and ir.gen.llvm_ir , "no native IR for the TypeAlias glob";
    assert _native_int_fn(ir, "run")() == 8 , (
        "the TypeAlias glob changed what the rest of the module computes"
    );
}


test "a ClassVar import no longer blocks native placement" {
    assert _scan_verdict(_module_with("import from typing { ClassVar }")) == "OK" , (
        "`ClassVar[T]` says where a slot lives, not what a program computes: "
        "it is annotation-only, like `TypeAlias`, and the native lane already "
        "erases it. The import in front of it was all that still refused the "
        "module at placement"
    );
}


test "a mixed typing import is still judged per name" {
    assert _scan_verdict(_module_with("import from typing { ClassVar, Optional }"))
        == "unresolved import 'typing'" , (
        "the compile-time vocabulary is per name: adding `ClassVar` to it must "
        "not wave through a `typing` import that also binds a name with no "
        "compile-time reading"
    );
}


test "a consumer links a ClassVar-importing dependency" {
    for _ in range(2) {
        (prog, ir) = _compile_native("classvar_marker_consumer.jac");
        assert not prog.errors_had , f"{[str(e) for e in prog.errors_had]}";
        assert ir is not None and ir.gen.llvm_ir , (
            "no native IR for a module whose dependency's only compile-time "
            "import is `ClassVar`"
        );
        dep = [
            m
            for (p, m) in prog.mod.hub.items()
            if p.endswith("classvar_marker_dep.jac")
        ];
        assert dep and dep[0].decided_codespace == 'native' , (
            "the dependency has to be compiled native, not refused at placement "
            "and left to Python"
        );
        assert _native_int_fn(ir, "run")() == 42 , (
            "the linked dependency has to answer across the native edge"
        );
    }
}


test "a from import of an na_stdlib-shimmed module lowers" {
    assert _rejected_imports("from_import_shimmed_stdlib.jac") == [] , (
        "`keyword` ships as Jac source under `runtime/na_stdlib`, so a "
        "native unit supplies the name the import binds; classifying "
        "`from`-import items must not read a shimmed module as Python"
    );
    (prog, ir) = _compile_native("from_import_shimmed_stdlib.jac");
    assert not prog.errors_had , f"{[str(e) for e in prog.errors_had]}";
    assert ir is not None and ir.gen.llvm_ir , (
        "no native IR for a module whose only import is a shimmed one"
    );
    layout = ir.gen.native_layout;
    assert layout is not None , "whole-module native compile aborted";
    assert "run" in layout.functions , (
        "a shimmed module supplies the name natively, so nothing here "
        f"refuses: {sorted(layout.functions)}"
    );
}


test "a body-scoped from-import is an error located at the import" {
    for fixture in ["from_import_accessor_seam.jac", "from_import_freefn_seam.jac"] {
        path = os.path.realpath(os.path.join(FIXTURES, fixture));
        with open(path, encoding="utf-8") as fh {
            import_line = [
                i + 1
                for (i, line) in enumerate(fh.read().splitlines())
                if "import from collections" in line
            ][0];
        }
        (prog, _ir) = _compile_native(fixture);
        located = [
            e
            for e in prog.errors_had
            if e.loc is not None
                and os.path.realpath(e.loc.mod_path) == path
                and e.loc.first_line == import_line
                and "collections" in str(e)
        ];
        assert located , (
            f"{fixture}: expected an error naming `collections` at line "
            f"{import_line}, got {[str(e) for e in prog.errors_had]}"
        );
    }
}


test "a Jac field import is a compile-time declaration" {
    assert _rejected_imports("object_field_default.jac") == [] , (
        "`ObjectField` only ever appears as a has-field default, where the "
        "declaration site consumes it; the native lane never calls it, so "
        "the import belongs in the compile-time vocabulary"
    );
    assert _scan_verdict(
        _module_with("import from jaclang.runtime.object_model { ObjectField }")
    )
        == "OK" , (
        "the placement pre-scan reads the same vocabulary, so a "
        "`ObjectField` import must stop refusing the module there too"
    );
}


test "a Python dataclass decorator still refuses" {
    verdict = _scan_verdict(_module_with("import from dataclasses { dataclass }"));
    assert verdict != "OK" , (
        "the vocabulary is per name: `ObjectField` erases at the declaration site "
        f"and `dataclass` does not, so listing it must still refuse: {verdict}"
    );
}


test "a field-defaulted archetype lowers and builds its defaults" {
    (prog, ir) = _compile_native("object_field_default.jac");
    assert not prog.errors_had , f"{[str(e) for e in prog.errors_had]}";
    assert ir is not None and ir.gen.llvm_ir , (
        "no native IR for an archetype whose has-fields default through "
        "`jaclang.runtime.object_model.ObjectField`"
    );
    layout = ir.gen.native_layout;
    assert layout is not None , "whole-module native compile aborted";
    assert "run" in layout.functions , (
        f"the declaration-site marker refused its module: {sorted(layout.functions)}"
    );
    assert _native_int_fn(ir, "run")() == 13 , (
        "a `default_factory` field must arrive as an empty container of the "
        "declared type and a `default` field as that literal"
    );
}
