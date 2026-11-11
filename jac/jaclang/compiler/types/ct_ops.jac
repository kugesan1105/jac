import operator;

glob CT_POW_BITS_LIMIT: int = 4000000,
     CT_SHIFT_LIMIT: int = 4000000,
     CT_INDEX_MAX: int = 9223372036854775807,
     CT_PY_OPS: dict[str, any] = {
         "+": operator.add,
         "-": operator.sub,
         "*": operator.mul,
         "/": operator.truediv,
         "//": operator.floordiv,
         "%": operator.mod,
         "**": operator.pow,
         "&": operator.and_,
         "|": operator.or_,
         "^": operator.xor,
         "<<": operator.lshift,
         ">>": operator.rshift,
         "<": operator.lt,
         "<=": operator.le,
         ">": operator.gt,
         ">=": operator.ge
     },
     CT_OP_SYMBOLS: dict[str, str] = {
         "PLUS": "+",
         "MINUS": "-",
         "STAR_MUL": "*",
         "DIV": "/",
         "FLOOR_DIV": "//",
         "MOD": "%",
         "STAR_POW": "**",
         "BW_AND": "&",
         "BW_OR": "|",
         "BW_XOR": "^",
         "LSHIFT": "<<",
         "RSHIFT": ">>",
         "LT": "<",
         "LTE": "<=",
         "GT": ">",
         "GTE": ">="
     };

def ct_symbol(opn: str) -> str;

def ct_py_number(v: CtValue) -> (bool | int | float | None);

def ct_from_number(x: object) -> CtValue;

def ct_num_op(sym: str, x: (bool | int | float), y: (bool | int | float)) -> CtValue;

def int_to_float(a: CtInt) -> float;

def _unsupported(sym: str, l: CtValue, r: CtValue) -> CtRaise;

def _repeat_count(n: CtInt) -> int;

def ct_binop(sym: str, l: CtValue, r: CtValue) -> CtValue;

def set_algebra(sym: str, l: CtSet, r: CtSet, frozen: bool) -> CtSet;

def _repeat(seq: CtValue, n: int) -> CtValue;

def ct_unary(op: str, v: CtValue) -> CtValue;

def ct_order(sym: str, l: CtValue, r: CtValue) -> bool;

def _subset(a: CtSet, b: CtSet) -> bool;

def ct_lt(a: CtValue, b: CtValue) -> bool;

def ct_contains(container: CtValue, item: CtValue) -> bool;

def ct_is(l: CtValue, r: CtValue) -> bool;

def ct_compare(sym: str, l: CtValue, r: CtValue) -> bool;

def _index_of(base: CtValue, key: CtValue, what: str) -> int;

def ct_getitem(base: CtValue, key: CtValue) -> CtValue;

def _slice_bound(v: (CtValue | None)) -> (int | None);

def slice_indices(
    length: int, lo_v: (CtValue | None), hi_v: (CtValue | None), st_v: (CtValue | None)
) -> tuple[int, int, int, int];

def ct_getslice(
    base: CtValue, lo: (CtValue | None), hi: (CtValue | None), st: (CtValue | None)
) -> CtValue;

def ct_setitem(base: CtValue, key: CtValue, val: CtValue);

def ct_int_literal(text: str) -> CtInt;

def int_to_base_str(a: CtInt, base: int) -> str;

def _hashable_py(v: CtValue) -> object;

def ct_hash(v: CtValue) -> CtInt;
