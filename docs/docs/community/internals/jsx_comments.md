# JSX comments — design notes

JSX comments use the syntax `{#* … *#}` inside a JSX child slot. They
are syntactically valid, semantically a no-op (compile to nothing at
runtime), and round-trip through the formatter. This document explains
how the compiler handles them so contributors writing new passes know
where the moving parts live.

## The user-facing surface

```jac
<div>
    <span>before</span>
    {#* this is a JSX-body comment *#}
    <span>after</span>
</div>
```

Three legal shapes inside a JSX child position:

| Shape | Example | AST |
| --- | --- | --- |
| Comment-only brace pair | `{#* note *#}` | `JsxComment(comment=ct, …)` |
| Literal empty brace pair | `{}` | `JsxComment(comment=None, …)` |
| Whitespace-only brace pair | `{   }` | `JsxComment(comment=None, …)` |

The `{}` and `{   }` cases are pragmatically accepted (silently rendered
as `{}` by the formatter). TSX rejects them; Jac does not. This is a
deliberate UX choice — empty JSX braces are harmless and can appear in
machine-generated or in-progress code.

## Architectural choice — why a real AST node

`JsxComment` is a real AST node, sibling to `JsxText` and
`JsxExpression` under `JsxChild`. Earlier iterations used:

- A side-channel set on `Source` (parser-tagged byte offsets) — rejected
  as cross-pass leakage.
- A flag on `CommentToken` plus multiple inheritance (`Token` +
  `JsxChild`) — rejected as type conflation: a single class would have
  to mean two different things depending on optional fields.

The current design says: *a JSX-body comment isn't a kind of comment
that happens to be in JSX position; it's a kind of JSX child that
happens to wrap a comment*. The owning type is the AST position; the
`CommentToken` is its payload.

## Pipeline overview

The fix is split across the **lexer** and the **parser**. Each layer
does its own job; downstream passes (formatter, codegens) see a typed
node and dispatch on it like any other JSX child.

```
┌─────────┐    JSX_BLOCK_COMMENT (single token)    ┌────────┐
│  Lexer  │  ────────────────────────────────────▶ │ Parser │
└─────────┘                                        └───┬────┘
     │                                                 │
     │  free comments → lexer.comments                 ▼
     │                                          JsxComment(JsxChild)
     ▼                                                 │
 source.comments                                       ▼
                                                  doc_ir / unparse / etc.
```

### Lexer — JSX-aware atomic scan

When the lexer is in `JSX_CONTENT` mode and the cursor sits on `{`, it
calls `_try_scan_jsx_block_comment` ([lexer.impl.jac](../../jac/jaclang/jac0core/parser/impl/lexer.impl.jac)).
That helper does a reversible lookahead for `{ \s* #* ... *# \s* }`:

- **Match** → consume the entire pattern, emit a single
  `JSX_BLOCK_COMMENT` token whose value is the full source text of the
  slot (including outer braces).
- **Miss** (no comment, comment plus extra content, two comments,
  unterminated) → restore `pos`/`line`/`col` and return `None`. The
  caller falls through to normal `{` handling: emit `LBRACE`, push
  `NORMAL` mode, scan the inside as an expression, etc.

The rewind is fully reversible — no tokens are emitted and nothing is
appended to `self.comments` during the lookahead. Direct tests live in
[test_jsx_block_comment_lexer.jac](../../jac/tests/compiler/passes/native/test_jsx_block_comment_lexer.jac).

### Parser — typed dispatch

`parse_jsx_child` ([parser.impl.jac](../../jac/jaclang/jac0core/parser/impl/parser.impl.jac))
sees three relevant entry points:

1. `TokenKind.JSX_BLOCK_COMMENT` → slice the inner `#* ... *#` out of
   the token's source range, build a `CommentToken`, synthesize
   `LBRACE`/`RBRACE` `UniToken`s at the slot's outer brace positions,
   return `JsxComment(comment=ct, kid=[lbrace, rbrace])`.
2. `TokenKind.LBRACE` followed immediately by `TokenKind.RBRACE` →
   literal empty `{}` (or whitespace-only after lookahead miss). Return
   `JsxComment(comment=None, kid=[lbrace, rbrace])`.
3. `TokenKind.LBRACE` followed by an expression → existing
   `JsxExpression(expr, …)` path.

Both `JsxComment` shapes have `kid = [lbrace_uni, rbrace_uni]` —
intentionally the same shape so downstream passes don't have to branch.

### Comment ownership

The `CommentToken` for a JSX-body comment lives on its `JsxComment`
node. It is **never** added to `module.source.comments` — the lexer
diverts JSX-body comments at scan time, and free `lexer.comments` only
contains comments that aren't bound to any AST node.

This means:

- `CommentInjectionPass` (which walks `source.comments`) never sees
  JSX-body comments → no double-render, no positional heuristic.
- The two pipelines are disjoint: free comments flow through
  `CommentInjectionPass`; JSX-body comments flow through
  `JsxComment.gen.doc_ir`.

## Pass dispatch

| Pass | Handler | Behavior |
| --- | --- | --- |
| `doc_ir_gen_pass` | `exit_jsx_comment` | Renders `{ comment.value }` (or `{}`) inline; adds `JsxComment` to `inline_child_types` so JSX layout treats it as inline. |
| `unparse_pass` | `exit_jsx_comment` | Mirrors doc-IR rendering for non-formatter unparse. |
| `normalize_pass` | `enter_jsx_comment` | Rebuilds canonical `kid = [LBRACE, RBRACE]` (no-op for the parser-built shape, repairs synthesized kid lists). |
| `pyast_gen_pass` | (none) | `gen.py_ast` defaults to `[]`; `PyJsxProcessor.element` filters `JsxComment` children out of the runtime children list before reading `.py_ast[0]`. |
| `esast_gen_pass` | (none) | `gen.es_ast` defaults to `None`; `EsJsxProcessor.element`'s existing `child_expr is None` filter drops the slot. |
| `jir_registry` | (auto-generated) | `JsxComment` registered with its own type index. |

If you add a new pass that walks `JsxChild` children, decide whether it
needs a specific `_jsx_comment` handler. Most don't — the default
`enter_jsx_child` no-op covers JsxComment too.

## Adding a new JsxChild variant

If you ever add a fourth `JsxChild` subclass, the pattern is:

1. Declare `obj YourNewChild(JsxChild) { … }` in `unitree.jac`.
2. Add `postinit` impl.
3. Wire any pass that already handles `JsxText`/`JsxExpression`
   (currently: `doc_ir_gen`, `unparse`, `normalize`).
4. Update `inline_child_types` in `doc_ir_gen_pass.impl.jac` if your
   node should keep its parent JSX element flat-rendered.
5. If your node should compile to nothing in Python/JS, add an
   `isinstance(c, uni.YourNewChild)` filter to the relevant JSX
   processor (`PyJsxProcessor.element` /
   `EsJsxProcessor.element`).
6. Run `jac gen-jir-registry` to refresh the registry.

## Testing surface

| Test file | What it covers |
| --- | --- |
| [test_jsx_block_comment_lexer.jac](../../jac/tests/compiler/passes/native/test_jsx_block_comment_lexer.jac) | Lexer rewind invariants — match, miss, position preservation, JSX vs non-JSX context. |
| [test_jac_format_pass.jac](../../jac/tests/compiler/passes/tool/test_jac_format_pass.jac) | Formatter end-to-end — JSX-body comments preserved, idempotent, non-JSX same-line block comments unaffected. |
| [test_pyast_gen_pass.jac](../../jac/tests/compiler/passes/main/test_pyast_gen_pass.jac) | Python codegen — JsxComment children produce no `None` slot in the `_jaclib.jsx(…)` children list; runtime exec succeeds. |
| [test_esast_gen_pass.jac](../../jac/tests/compiler/passes/ecmascript/test_esast_gen_pass.jac) | ECMAScript codegen — same property for the `__jacJsx(…)` array. |
| [jsx_body_comment.jac](../../jac/tests/language/fixtures/jsx_body_comment.jac) | Fixture: comment-between-siblings, comment-only-child, comment-adjacent-to-expr. |

## Known limitations

- **Two comments in one slot** — `{ #* a *# #* b *# }` does not match
  the lexer pattern, falls through to normal `{` handling, and parses
  as an expression slot. The parser then errors because there's no
  expression. Treat this as "don't write that." Same limitation in all
  prior designs.
- **Empty/whitespace-only braces** — accepted as a no-op `JsxComment`,
  rendered by the formatter as `{}`. TSX rejects this; Jac does not.
