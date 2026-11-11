import _string;
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

def _hashable_py(v: CtValue) -> object;

def ct_hash(v: CtValue) -> CtInt;

class CtPy {
    def init(self: CtPy, ct: CtValue);
    def __repr__(self: CtPy) -> str;
    def __str__(self: CtPy) -> str;
    def __format__(self: CtPy, spec: str) -> str;
}

class CtPyIterable(CtPy) {
    def __len__(self: CtPyIterable) -> int;
    def __iter__(self: CtPyIterable) -> object;
}

class CtPySubscript(CtPyIterable) {
    def __getitem__(self: CtPySubscript, key: object) -> object;
}

obj CtFormatState {
    has args: list[CtValue],
        kwargs: dict[str, CtValue],
        auto_idx: int = 0,
        mode: str = "";
}

glob CT_PY_CLASSES: dict[str, type] = {};

def ct_to_py(v: CtValue) -> object;

def ct_from_py(x: object) -> CtValue;

def ct_py_call(fn: any, args: list[any], kwargs: dict[str, any]) -> any;

def ct_format(v: CtValue, spec: str) -> str;

def ct_convert(v: CtValue, conv: str) -> CtValue;

def ct_str_format(fmt: str, args: list[CtValue], kwargs: dict[str, CtValue]) -> str;

def _str_format(fmt: str, st: CtFormatState, depth: int) -> str;

def _field_value(field_name: str, st: CtFormatState) -> CtValue;

def _format_attr(value: CtValue, attr: str) -> CtValue;

def ct_binary(sym: str, l: CtValue, r: CtValue) -> CtValue;

def ct_inplace(sym: str, cur: CtValue, val: CtValue) -> CtValue;
