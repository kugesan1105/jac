# Fixture for the field-type diagnostic (#7871 F). A field whose declared
# type has no native lowering is a located E5092 on its declaration.
#
# `read_view` touches the field; `holder_tag` and `read_tag` never name it and
# report nothing of their own.

obj Holder {
    has view: memoryview,
        tag: int = 7;
}

def read_view(h: Holder) -> int {
    v = h.view;
    return 1;
}

def read_tag(h: Holder) -> int {
    return h.tag;
}

def holder_tag -> int {
    return 7;
}

glob _x: int = 1;
