"""Fixture: a local function named `contextmanager`, unrelated to contextlib.

Expected: E1091 + E1092. The shadow must not be mistaken for contextlib's
contextmanager, so `get()` stays NoneType and the with statement still errors.
"""

def contextmanager(f: any) -> any {
    return f;
}

obj Foo {
    @contextmanager
    def get -> None;
}

impl Foo.get -> None { }

def use_it {
    f = Foo();
    with f.get() {
        print("should fail");
    }
}
