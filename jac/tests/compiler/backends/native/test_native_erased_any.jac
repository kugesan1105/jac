"""Why `Any` will never be in the compile-time import vocabulary, and codeinfo's clearing.

This file used to pin a refusal and a three-item clearing list: `typing`'s
compile-time vocabulary admitted `TypeVar`, `cast`, `TypeAlias` and
`ClassVar` but not `Any`, so `import from typing { Any }` answered
`unresolved import 'typing'` and `compiler/frontend/codeinfo.jac` -- whose only typing
import that was -- failed the native pre-scan. Three seams in
`capability_check_pass` were that one fact, and the list said what admitting
`Any` would cost.

The question is closed now, and not by admitting the name. `Any` is not
importable from `typing` at all: E1122 refuses every shape that binds it,
because jac has its own `any` and will not carry an aliased twin. A name the
language rejects can never reach the pre-scan, so there is nothing for the
vocabulary to decide. The first test below pins that -- the vocabulary must
keep refusing `Any`, now for a reason that cannot change back.

`codeinfo` spells its four annotations `any` and imports nothing from
`typing`, so the import-shaped blocker is gone.

The clearing list, and where each item stands:

  1. `BaseTransform.prog: JacProgram`. The field had no native layout, so it
     was module-fatal for every closure member behind it. #8288's pass rim
     stamps `prog` on the instance at construction and the declaration is
     gone -- not widened to `any`, which would have been wrong twice over
     (only eleven passes shadowed it, so the rest would have silently lost
     every `self.prog.*` check). `compiler/passes/transform.jac` is a member
     of codeinfo's closure now, which is the measurement that says so.

  2 and 3. `codeinfo`'s `CLIENT_RUNTIME_SOURCE_PATHS` glob, which was a bare
     `tuple` whose element type did not lower, and would not lower annotated
     either: its rows were ragged -- two, three and six strings -- so a
     nested tuple annotation became one heterogeneous literal struct and
     storing it into a `%List.ptr` was a type mismatch. The shape had to
     change, and it did: a flat `list[str]` of "/"-joined relative paths,
     rejoined with `os.sep` at its one use site.

So the list is spent as a list: nothing on it blocks anything any more.

The last test keeps the half of the old reasoning that outlived the rest.
`ModuleFacts.is_erased_type_decl` reads the *marker* set
(`NATIVE_ERASED_TYPE_MARKERS`, `TypeAlias`) to decide which globs are
compile-time declarations the backend skips. An `any`-annotated glob is not
one: it is an ordinary global whose value has to reach the binary, and
classifying it as a declaration would drop it silently. That is the trap
`ClassVar` was lifted out of in #8278, and it holds for the lowercase
keyword exactly as it would have for the name.
"""

import os;
import from jaclang.compiler.frontend.codeinfo { native_erased_import_names }
import from jaclang.compiler.frontend.parser { parse as rd_parse }
import from jaclang.compiler.placement.placement { scan_native_blockers }
import from jaclang.compiler.driver.program { JacProgram }
import from jaclang.compiler.frontend.module_facts { ModuleFacts }
import from jaclang.compiler.frontend.unitree { Assignment, GlobalVars }
import from tests.support { TESTS_DIR }

glob FIXTURES = os.path.join(
         TESTS_DIR, "compiler", "backends", "native", "fixtures"
     ),
     FIXTURE: str = "erased_any_annotation.jac";


"""Parse a fixture and return its module."""
def _parse(fixture: str) -> any {
    path = os.path.join(FIXTURES, fixture);
    with open(path, encoding='utf-8') as fh {
        src = fh.read();
    }
    (mod, had_err) = rd_parse(src, path, prog=JacProgram());
    assert not had_err , f"{fixture} did not parse";
    return mod;
}


test "the typing vocabulary refuses Any, and no module can ask it to" {
    assert not native_erased_import_names("typing", ["Any"]) , (
        "'Any' is in the compile-time import vocabulary. It must not be: "
        "E1122 refuses every import that binds the name, so admitting it "
        "here would describe a module the language cannot accept"
    );
    assert native_erased_import_names("typing", ["ClassVar", "cast"]) , (
        "the names that were already admitted must stay admitted"
    );
}


test "a module annotated with the any keyword passes the native pre-scan" {
    (reason, _deps) = scan_native_blockers(_parse(FIXTURE), FIXTURES, allow_pub=True);
    assert reason == "" , (
        f"the pre-scan refused an any-annotated module with {reason!r}. The "
        "lowercase keyword is a builtin: it binds no import, so there is "
        "nothing here for the scan to resolve"
    );
}


test "an any-annotated glob is not a compile-time declaration" {
    mod = _parse(FIXTURE);
    found = False;
    for stmt in mod.body {
        if not isinstance(stmt, GlobalVars) {
            continue;
        }
        for assign in stmt.assignments {
            if not isinstance(assign, Assignment) {
                continue;
            }
            found = True;
            assert not ModuleFacts.is_erased_type_decl(assign) , (
                "the any-annotated glob was classified as a compile-time "
                "declaration, so its value would never be emitted"
            );
        }
    }
    assert found , "the fixture no longer declares a glob to check";
}
