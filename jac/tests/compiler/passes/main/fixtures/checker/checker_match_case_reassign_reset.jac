"""Match-case narrowing must be killed by a later assignment."""

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
                # expr is narrowed to MultiString here.
                if isinstance(expr.parent, (SubTag, FuncSignature)) {
                    expr.strings;
                }
                expr = 90;  # error: cannot assign int to Expr
                # The barrier resets expr to the declared type for the
                # rest of this case body, so each access below errors.
                expr.strings;  # error
                if (
                    isinstance(expr.parent, (SubTag, FuncSignature))
                    and expr.strings  # error
                ) {
                    expr.strings;  # error
                }

        }
    }
}
