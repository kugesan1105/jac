from __future__ import annotations


def something(it: int) -> bool:
    return it > 5

def t1(items: list[int]) -> None:
    fb: int | str | None = None
    for it in items:
        if something(it):
            fb = 5
        else:
            fb = 'sdfsdf'
    out = fb

