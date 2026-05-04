"""`Never` / `NoReturn` are accepted as `|` union arms."""

import from typing { Never, NoReturn }


def take_with_never(x: int | Never) -> int {
    return 0;
}


def take_with_noreturn(x: int | NoReturn) -> int {
    return 0;
}


def take_never_first(x: Never | int | str) -> int {
    return 0;
}


def boom -> Never {
    raise ValueError("never");
}


def call_site -> int {
    # Never is the bottom type → assignable to any expected param type.
    return take_with_never(boom());
}
