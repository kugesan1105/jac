walker GoodWalker {
    can visit with Root entry { ; }   # valid — Root is the class
}

walker BadWalker {
    can visit with root entry { ; }   # E1116 — root is a runtime instance
}
