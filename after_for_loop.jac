def t1(items: list[int]) {
    fb: int | None = None;      # NoneType
    for it in items {
        fb = 5;                 # int
    }
    out = fb;                   # EXPECTED: int | None
}


# def t2(n: int) {
#     x: int | None = None;       # NoneType
#     while n > 0 {
#         x = 5;                  # int
#         n = n - 1;
#     }
#     out = x;                    # EXPECTED: int | None
# }


# def t3(flag: bool) {
#     fb: int | None = None;      # NoneType
#     if flag {
#         fb = 5;                 # int
#     }
#     out = fb;                   # EXPECTED: int | None
# }