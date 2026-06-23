





# def something(it: int) -> bool {
#     return (it > 5);
# }
# def t1(items: list[int]) {
#     fb: (int | str | None) = None;
#     for it in items {
#         if something(it) {
#             fb = 5;
#         } else {
#             fb = 'sdfsdf';
#         }
#     }
#     out = fb;
# }



obj Box{

}

with entry {
    b: Box | None;

    if b is not None {
        ok: Box = b; 
        x:list[Box] = [b for _ in range(3)]
    }
}