"""Regression: match-case narrowing must be killed by a later assignment.

Inside a `case MultiString():` body, the subject `expr` is narrowed to
MultiString. A subsequent `expr = 90` (invalid — int is not an Expr) must
act as a barrier that resets the narrowing to the declared type `Expr` for
every access that follows in the same case body. Accessing `.strings`
after the reassignment must error, because `Expr` has no `strings`.
"""

class UniNode {
    has parent: UniNode | None = None;
}

class Expr(UniNode) {}

class MultiString(Expr) {
    has strings: list[str] = [];
}

class SubTag(UniNode) {}
class FuncSignature(UniNode) {}

obj Checker {
    def check(expr: Expr) {
        match expr {
            case MultiString():
                # Narrowed to MultiString here — OK.
                if isinstance(expr.parent, (SubTag, FuncSignature)) {
                    expr.strings;  # OK (MultiString)
                }
                # Barrier: this assignment is an error (int → Expr) but must
                # still reset narrowing on the edges that follow.
                expr = 90;  # <-- Error: Cannot assign int to Expr
                # These must all error: expr is now back to declared `Expr`.
                expr.strings;  # <-- Error (no attribute "strings")
                if (
                    isinstance(expr.parent, (SubTag, FuncSignature))
                    and expr.strings  # <-- Error (no attribute "strings")
                ) {
                    expr.strings;  # <-- Error (no attribute "strings")
                }

        }
    }
}
