# Examples

## Array lifecycle

Allocate, write, read, free. The compiler enforces that `arr` is consumed exactly once.

```ats
staload "lib/memory.sats"
staload _ = "lib/memory.dats"

fun array_example (): void = let
  val arr = ward_arr_alloc<int>(10)
  val () = ward_arr_set<int>(arr, 5, 42)
  val v = ward_arr_get<int>(arr, 5)       (* v = 42 *)
  val () = ward_arr_free<int>(arr)
in end
```

## Freeze / borrow / thaw

Freeze an array to get read-only borrows. The array cannot be mutated or freed until all borrows are dropped and it is thawed.

```ats
fun borrow_example (): void = let
  val arr = ward_arr_alloc<int>(10)
  val () = ward_arr_set<int>(arr, 0, 42)

  val @(frozen, borrow) = ward_arr_freeze<int>(arr)
  val v = ward_arr_read<int>(borrow, 0)       (* read through borrow: v = 42 *)

  (* Duplicate the borrow -- now two readers *)
  val borrow2 = ward_arr_dup<int>(frozen, borrow)
  val v2 = ward_arr_read<int>(borrow2, 0)     (* v2 = 42 *)

  (* Drop both borrows *)
  val () = ward_arr_drop<int>(frozen, borrow)
  val () = ward_arr_drop<int>(frozen, borrow2)

  (* Now thaw -- requires 0 outstanding borrows *)
  val arr = ward_arr_thaw<int>(frozen)
  val () = ward_arr_free<int>(arr)
in end
```

## Split and join

Split an array into two sub-arrays. Size is tracked statically.

```ats
fun split_example (): void = let
  val arr = ward_arr_alloc<int>(10)
  val () = ward_arr_set<int>(arr, 3, 99)

  val @(left, right) = ward_arr_split<int>(arr, 5)
  (* left: ward_arr(int, l, 5) *)
  (* right: ward_arr(int, l+5, 5) *)

  val v = ward_arr_get<int>(left, 3)   (* v = 99 *)

  val arr = ward_arr_join<int>(left, right)
  val () = ward_arr_free<int>(arr)
in end
```

## Building safe text

Every character is verified at compile time. Unsafe characters are rejected by the constraint solver.

```ats
fun safe_text_example (): ward_safe_text(5) = let
  val b = ward_text_build(5)
  val b = ward_text_putc(b, 0, char2int1('h'))
  val b = ward_text_putc(b, 1, char2int1('e'))
  val b = ward_text_putc(b, 2, char2int1('l'))
  val b = ward_text_putc(b, 3, char2int1('l'))
  val b = ward_text_putc(b, 4, char2int1('o'))
in ward_text_done(b) end

(* This would NOT compile -- '<' is not SAFE_CHAR:
   val b = ward_text_putc(b, 0, char2int1('<'))  // COMPILE ERROR
*)
```

## DOM streaming

Stream ops batch into a 256KB buffer. Auto-flush handles buffer overflow.

```ats
staload "lib/dom.sats"
staload _ = "lib/dom.dats"

fun dom_example (): void = let
  val dom = ward_dom_init()

  (* Build tag name "div" *)
  val b = ward_text_build(3)
  val b = ward_text_putc(b, 0, char2int1('d'))
  val b = ward_text_putc(b, 1, char2int1('i'))
  val b = ward_text_putc(b, 2, char2int1('v'))
  val tag = ward_text_done(b)

  val s = ward_dom_stream_begin(dom)
  val s = ward_dom_stream_create_element(s, 1, 0, tag, 3)

  (* Set text content from safe text *)
  val b = ward_text_build(5)
  val b = ward_text_putc(b, 0, char2int1('h'))
  val b = ward_text_putc(b, 1, char2int1('e'))
  val b = ward_text_putc(b, 2, char2int1('l'))
  val b = ward_text_putc(b, 3, char2int1('l'))
  val b = ward_text_putc(b, 4, char2int1('o'))
  val text = ward_text_done(b)
  val s = ward_dom_stream_set_safe_text(s, 1, text, 5)

  (* Set attribute with safe text name and value *)
  val b = ward_text_build(2)
  val b = ward_text_putc(b, 0, char2int1('i'))
  val b = ward_text_putc(b, 1, char2int1('d'))
  val attr_name = ward_text_done(b)

  val b = ward_text_build(4)
  val b = ward_text_putc(b, 0, char2int1('m'))
  val b = ward_text_putc(b, 1, char2int1('a'))
  val b = ward_text_putc(b, 2, char2int1('i'))
  val b = ward_text_putc(b, 3, char2int1('n'))
  val attr_val = ward_text_done(b)
  val s = ward_dom_stream_set_attr_safe(s, 1, attr_name, 2, attr_val, 4)

  val dom = ward_dom_stream_end(s)
  val () = ward_dom_fini(dom)
in end
```

## DOM with async boundaries

Use linear closures (`llam`) in `ward_promise_then` to capture and thread linear DOM state across promise callbacks.

```ats
fun async_dom_example (): void = let
  val dom = ward_dom_init()

  val p1 = ward_timer_set(1000)

  val p2 = ward_promise_then<int><int>(p1,
    llam (x: int) => let
      (* dom is captured linearly from enclosing scope *)
      val s = ward_dom_stream_begin(dom)
      (* ... stream ops ... *)
      val dom = ward_dom_stream_end(s)
      val () = ward_dom_fini(dom)
    in ward_promise_return<int>(0) end)

  val () = ward_promise_discard<int><Pending>(p2)
in end
```

## Flat promise chain

Timer fires, then immediate value, then exit. All promises are linear -- every one must be consumed. Closures use `llam` (linear lambda) which can capture linear values and are freed after invocation.

```ats
staload "lib/promise.sats"
staload "lib/event.sats"
staload _ = "lib/promise.dats"
staload _ = "lib/event.dats"

fun chain_example (): void = let
  val p1 = ward_timer_set(1000)

  val p2 = ward_promise_then<int><int>(p1,
    llam (x: int) => ward_promise_return<int>(x + 1))

  val p3 = ward_promise_then<int><int>(p2,
    llam (x: int) => let
      val () = ward_exit()
    in ward_promise_return<int>(0) end)

  val () = ward_promise_discard<int><Pending>(p3)
in end
```

## Arena allocation

Arenas provide bulk allocation for large data (images, media). Arena arrays are standard `ward_arr` values -- all existing operations work unchanged.

```ats
fun arena_example (): void = let
  val arena = ward_arena_create(65536)  (* 64KB arena *)

  (* Allocate arrays from the arena *)
  val @(tok1, arr1) = ward_arena_alloc<byte>(arena, 1024)
  val () = ward_arr_set<byte>(arr1, 0, int2byte0(42))
  val v = byte2int0(ward_arr_get<byte>(arr1, 0))   (* v = 42 *)

  val @(tok2, arr2) = ward_arena_alloc<int>(arena, 256)
  val () = ward_arr_set<int>(arr2, 0, 12345)

  (* Freeze/thaw works on arena arrays *)
  val @(frozen, borrow) = ward_arr_freeze<byte>(arr1)
  val v2 = byte2int0(ward_arr_read<byte>(borrow, 0))  (* v2 = 42 *)
  val () = ward_arr_drop<byte>(frozen, borrow)
  val arr1 = ward_arr_thaw<byte>(frozen)

  (* Return arrays to arena, then destroy *)
  val () = ward_arena_return<byte>(arena, tok1, arr1)
  val () = ward_arena_return<int>(arena, tok2, arr2)
  val () = ward_arena_destroy(arena)  (* frees all arena memory at once *)
in end

(* This would NOT compile -- outstanding token prevents early destroy:
   val () = ward_arena_destroy(arena)  // COMPILE ERROR: k > 0
*)
```

## IDB round-trip

Put a value, get it back, delete it. All operations return promises.

```ats
staload "lib/idb.sats"
staload _ = "lib/idb.dats"

fun idb_example (): void = let
  (* Build key *)
  val b = ward_text_build(4)
  val b = ward_text_putc(b, 0, char2int1('k'))
  val b = ward_text_putc(b, 1, char2int1('e'))
  val b = ward_text_putc(b, 2, char2int1('y'))
  val b = ward_text_putc(b, 3, char2int1('1'))
  val key = ward_text_done(b)

  (* Build value *)
  val vbuf = ward_arr_alloc<byte>(3)
  val () = ward_arr_set<byte>(vbuf, 0, ward_int2byte(65))  (* A *)
  val () = ward_arr_set<byte>(vbuf, 1, ward_int2byte(66))  (* B *)
  val () = ward_arr_set<byte>(vbuf, 2, ward_int2byte(67))  (* C *)

  val @(frozen, borrow) = ward_arr_freeze<byte>(vbuf)
  val p_put = ward_idb_put(key, 4, borrow, 3)

  val () = ward_arr_drop<byte>(frozen, borrow)
  val vbuf = ward_arr_thaw<byte>(frozen)
  val () = ward_arr_free<byte>(vbuf)

  (* Chain: put -> get -> delete *)
  val b = ward_text_build(4)
  val b = ward_text_putc(b, 0, char2int1('k'))
  val b = ward_text_putc(b, 1, char2int1('e'))
  val b = ward_text_putc(b, 2, char2int1('y'))
  val b = ward_text_putc(b, 3, char2int1('1'))
  val key2 = ward_text_done(b)

  val p_get = ward_promise_then<int><int>(p_put,
    llam (_: int) => ward_idb_get(key2, 4))

  val () = ward_promise_discard<int><Pending>(p_get)
in end
```
