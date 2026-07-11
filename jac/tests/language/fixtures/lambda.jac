with entry {
    x = lambda  a: int , b: int: b + a;
    print(x(5, 4));
    y = lambda : 567 ;
    print(y());
    z = lambda (d: list[int], e: int) : d[e];
    print(z([12, 8], 1));
    g = lambda d: dict[str, int] : d["n"];
    print(g({"n": 42}));
    u = lambda v: int | str : v;
    print(u("mix"));
}
