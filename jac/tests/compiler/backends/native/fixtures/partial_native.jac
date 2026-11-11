# A native class with one method the backend cannot lower (`evaluate`, which
# uses `eval`). Native compilation reports a located error at the `eval` call.
obj Literal {
    has raw: str;

    def length -> int {
        return len(self.raw);
    }  # native-eligible
    def evaluate -> int {
        return eval(self.raw);
    }
}

"""Construct the class and call its lowerable sibling method."""
def measure(s: str) -> int {
    lit = Literal(raw=s);
    return lit.length();
}

with entry {
    print(measure("42"));
}
