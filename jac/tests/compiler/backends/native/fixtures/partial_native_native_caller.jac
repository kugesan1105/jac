# A native caller of a method the backend cannot lower. The error is located at
# the `eval` call inside `Box.evaluate`.
obj Box {
    has raw: str;

    def length -> int {
        return len(self.raw);
    }  # native-eligible

    def evaluate -> int {
        return eval(self.raw);
    }
}

def call_evaluate(s: str) -> int {
    b = Box(raw=s);
    return b.evaluate();
}

with entry {
    print(call_evaluate("1"));
}
