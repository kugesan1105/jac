"""Parenthesized BoolExpr conditions must wire the short-circuit CFG."""

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
    def check_bare(expr: Expr) {
        match expr {
            case MultiString():
                if isinstance(expr.parent, (SubTag, FuncSignature)) and expr.strings {
                    expr.strings;
                }

        }
    }

    def check_parens(expr: Expr) {
        match expr {
            case MultiString():
                if (isinstance(expr.parent, (SubTag, FuncSignature)) and expr.strings) {
                    expr.strings;
                }

        }
    }

    def check_while_parens(expr: Expr) {
        match expr {
            case MultiString():
                while (
                    isinstance(expr.parent, (SubTag, FuncSignature)) and expr.strings
                ) {
                    expr.strings;
                    break;
                }

        }
    }
}
