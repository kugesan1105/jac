"""A body-scoped static call into the Python-side merge module.

`probe` owns the violation, so the call in its body is a located compile
error naming the callee, reached through the class-qualified call form rather
than the free-function one.
"""
import from xmod_static_pybase_merge { Merger }
import from xmod_static_types { Item }


def probe -> int {
    return Merger.merge(Item(value=3), Item(value=4));
}


def clean -> int {
    return Item(value=8).value;
}
