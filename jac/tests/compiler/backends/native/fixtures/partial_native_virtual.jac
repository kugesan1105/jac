# An un-lowerable *virtual* method (`Derived.render` overrides `Base.render`).
# Native compilation reports a located error at the `eval` call.
obj Base {
    has raw: str;

    def render -> int {
        return len(self.raw);
    }  # native-eligible
}

obj Derived(Base) {
    def render -> int {
        return eval(self.raw);
    }  # virtual + un-lowerable
}

def use(s: str) -> int {
    items: list[Base] = [Derived(raw=s)];
    return items[0].render();
}

with entry {
    print(use("1"));
}
