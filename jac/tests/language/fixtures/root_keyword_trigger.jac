walker Bad {
    can visit with root entry { #error, E1116 — root is a runtime instance, not the class
        print("should not reach here");
    }
}

with entry {
    root spawn Bad();
}
