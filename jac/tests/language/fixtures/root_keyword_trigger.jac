node N {}

walker GoodWalker {
    can visit with Root entry {
        print("GoodWalker: ok");
    }
}

walker BadWalker {
    can visit with root entry {
        print("should not reach here");
    }
}

walker BadUnion {
    can visit with Root | root entry {
        print("should not reach here");
    }
}

walker BadTuple {
    can visit with (Root, root) entry {
        print("should not reach here");
    }
}

with entry {
    root spawn GoodWalker();

    try { root spawn BadWalker(); } except TypeError as e { print(f"BadWalker: {e}"); }
    try { root spawn BadUnion(); } except TypeError as e { print(f"BadUnion: {e}"); }
    try { root spawn BadTuple(); } except TypeError as e { print(f"BadTuple: {e}"); }
}
