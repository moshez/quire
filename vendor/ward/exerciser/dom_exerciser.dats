(* dom_exerciser.dats — WASM entry point for Node.js DOM exerciser *)
(* Pure safe ATS2: no $UNSAFE, no %{}, no praxi. *)

#include "share/atspre_staload.hats"
staload "./../lib/memory.sats"
staload "./../lib/dom.sats"
staload "./../lib/promise.sats"
staload "./../lib/event.sats"
staload "./../lib/idb.sats"
staload "./../lib/window.sats"
staload "./../lib/nav.sats"
staload "./../lib/dom_read.sats"
staload "./../lib/listener.sats"
staload "./../lib/fetch.sats"
staload "./../lib/clipboard.sats"
staload "./../lib/file.sats"
staload "./../lib/decompress.sats"
staload "./../lib/notify.sats"
dynload "./../lib/memory.dats"
dynload "./../lib/dom.dats"
dynload "./../lib/promise.dats"
dynload "./../lib/event.dats"
dynload "./../lib/idb.dats"
dynload "./../lib/window.dats"
dynload "./../lib/nav.dats"
dynload "./../lib/dom_read.dats"
dynload "./../lib/listener.dats"
dynload "./../lib/fetch.dats"
dynload "./../lib/clipboard.dats"
dynload "./../lib/file.dats"
dynload "./../lib/decompress.dats"
dynload "./../lib/notify.dats"
staload _ = "./../lib/memory.dats"
staload _ = "./../lib/dom.dats"
staload _ = "./../lib/promise.dats"
staload _ = "./../lib/event.dats"
staload _ = "./../lib/idb.dats"
staload _ = "./../lib/window.dats"
staload _ = "./../lib/nav.dats"
staload _ = "./../lib/dom_read.dats"
staload _ = "./../lib/listener.dats"
staload _ = "./../lib/fetch.dats"
staload _ = "./../lib/clipboard.dats"
staload _ = "./../lib/file.dats"
staload _ = "./../lib/decompress.dats"
staload _ = "./../lib/notify.dats"

(* Helper: build safe text "p" (1 char) *)
fn make_tag_p (): ward_safe_text(1) = let
  val b = ward_text_build(1)
  val b = ward_text_putc(b, 0, char2int1('p'))
in ward_text_done(b) end

(* Helper: build safe text "span" (4 chars) *)
fn make_tag_span (): ward_safe_text(4) = let
  val b = ward_text_build(4)
  val b = ward_text_putc(b, 0, char2int1('s'))
  val b = ward_text_putc(b, 1, char2int1('p'))
  val b = ward_text_putc(b, 2, char2int1('a'))
  val b = ward_text_putc(b, 3, char2int1('n'))
in ward_text_done(b) end

(* Helper: build safe text "hello-ward" (10 chars) *)
fn make_text_hello (): ward_safe_text(10) = let
  val b = ward_text_build(10)
  val b = ward_text_putc(b, 0, char2int1('h'))
  val b = ward_text_putc(b, 1, char2int1('e'))
  val b = ward_text_putc(b, 2, char2int1('l'))
  val b = ward_text_putc(b, 3, char2int1('l'))
  val b = ward_text_putc(b, 4, char2int1('o'))
  val b = ward_text_putc(b, 5, 45) (* '-' *)
  val b = ward_text_putc(b, 6, char2int1('w'))
  val b = ward_text_putc(b, 7, char2int1('a'))
  val b = ward_text_putc(b, 8, char2int1('r'))
  val b = ward_text_putc(b, 9, char2int1('d'))
in ward_text_done(b) end

(* Helper: build safe text "it-works" (8 chars) *)
fn make_text_works (): ward_safe_text(8) = let
  val b = ward_text_build(8)
  val b = ward_text_putc(b, 0, char2int1('i'))
  val b = ward_text_putc(b, 1, char2int1('t'))
  val b = ward_text_putc(b, 2, 45) (* '-' *)
  val b = ward_text_putc(b, 3, char2int1('w'))
  val b = ward_text_putc(b, 4, char2int1('o'))
  val b = ward_text_putc(b, 5, char2int1('r'))
  val b = ward_text_putc(b, 6, char2int1('k'))
  val b = ward_text_putc(b, 7, char2int1('s'))
in ward_text_done(b) end

(* Helper: build safe text "class" (5 chars) *)
fn make_attr_class (): ward_safe_text(5) = let
  val b = ward_text_build(5)
  val b = ward_text_putc(b, 0, char2int1('c'))
  val b = ward_text_putc(b, 1, char2int1('l'))
  val b = ward_text_putc(b, 2, char2int1('a'))
  val b = ward_text_putc(b, 3, char2int1('s'))
  val b = ward_text_putc(b, 4, char2int1('s'))
in ward_text_done(b) end

(* Helper: build safe text "demo" (4 chars) *)
fn make_val_demo (): ward_safe_text(4) = let
  val b = ward_text_build(4)
  val b = ward_text_putc(b, 0, char2int1('d'))
  val b = ward_text_putc(b, 1, char2int1('e'))
  val b = ward_text_putc(b, 2, char2int1('m'))
  val b = ward_text_putc(b, 3, char2int1('o'))
in ward_text_done(b) end

(* Helper: build safe text "test-key" (8 chars) *)
fn make_idb_key (): ward_safe_text(8) = let
  val b = ward_text_build(8)
  val b = ward_text_putc(b, 0, char2int1('t'))
  val b = ward_text_putc(b, 1, char2int1('e'))
  val b = ward_text_putc(b, 2, char2int1('s'))
  val b = ward_text_putc(b, 3, char2int1('t'))
  val b = ward_text_putc(b, 4, 45) (* '-' *)
  val b = ward_text_putc(b, 5, char2int1('k'))
  val b = ward_text_putc(b, 6, char2int1('e'))
  val b = ward_text_putc(b, 7, char2int1('y'))
in ward_text_done(b) end

(* Helper: build safe text "ward-init" (9 chars) for log message *)
fn make_log_msg (): ward_safe_text(9) = let
  val b = ward_text_build(9)
  val b = ward_text_putc(b, 0, char2int1('w'))
  val b = ward_text_putc(b, 1, char2int1('a'))
  val b = ward_text_putc(b, 2, char2int1('r'))
  val b = ward_text_putc(b, 3, char2int1('d'))
  val b = ward_text_putc(b, 4, 45) (* '-' *)
  val b = ward_text_putc(b, 5, char2int1('i'))
  val b = ward_text_putc(b, 6, char2int1('n'))
  val b = ward_text_putc(b, 7, char2int1('i'))
  val b = ward_text_putc(b, 8, char2int1('t'))
in ward_text_done(b) end

(* WASM export: called by Node.js to start the exerciser *)
extern fun ward_node_init (root_id: int): void = "ext#ward_node_init"

implement ward_node_init (root_id) = let
  val dom = ward_dom_init()
  val () = ward_dom_store(dom)

  (* Exercise ward_log — sync, no promise needed *)
  val log_msg = make_log_msg()
  val () = ward_log(1, log_msg, 9)

  (* --- Flat promise chain: timer → DOM → IDB put → get → delete → timer → exit --- *)

  val p1 = ward_timer_set(1000)

  (* Step 1: 1s timer fires — create DOM elements, start IDB put *)
  val p2 = ward_promise_then<int><int>(p1,
    lam (x: int) =<cloref1> let
      val dom = ward_dom_load()

      val tag_p = make_tag_p()
      val dom = ward_dom_create_element(dom, 1, root_id, tag_p, 1)

      val text_hello = make_text_hello()
      val dom = ward_dom_set_safe_text(dom, 1, text_hello, 10)

      val tag_span = make_tag_span()
      val dom = ward_dom_create_element(dom, 2, root_id, tag_span, 4)

      val attr_class = make_attr_class()
      val val_demo = make_val_demo()
      val dom = ward_dom_set_attr_safe(dom, 2, attr_class, 5, val_demo, 4)

      val text_works = make_text_works()
      val dom = ward_dom_set_safe_text(dom, 2, text_works, 8)

      val () = ward_dom_store(dom)

      (* Build value array [72,101,108,108,111] = "Hello" *)
      val idb_val = ward_arr_alloc<byte>(5)
      val () = ward_arr_set<byte>(idb_val, 0, ward_int2byte(72))  (* H *)
      val () = ward_arr_set<byte>(idb_val, 1, ward_int2byte(101)) (* e *)
      val () = ward_arr_set<byte>(idb_val, 2, ward_int2byte(108)) (* l *)
      val () = ward_arr_set<byte>(idb_val, 3, ward_int2byte(108)) (* l *)
      val () = ward_arr_set<byte>(idb_val, 4, ward_int2byte(111)) (* o *)

      val @(frozen, borrow) = ward_arr_freeze<byte>(idb_val)
      val idb_key = make_idb_key()
      val p_put = ward_idb_put(idb_key, 8, borrow, 5)

      val () = ward_arr_drop<byte>(frozen, borrow)
      val idb_val2 = ward_arr_thaw<byte>(frozen)
      val () = ward_arr_free<byte>(idb_val2)
    in p_put end)

  (* Step 2: IDB put done — start IDB get *)
  val p3 = ward_promise_then<int><int>(p2,
    lam (put_status: int) =<cloref1> let
      val idb_key2 = make_idb_key()
    in ward_idb_get(idb_key2, 8) end)

  (* Step 3: IDB get done — retrieve result, start IDB delete *)
  val p4 = ward_promise_then<int><int>(p3,
    lam (got_len: int) =<cloref1> let
      val result = ward_idb_get_result(5)
      val () = ward_arr_free<byte>(result)
      val idb_key3 = make_idb_key()
    in ward_idb_delete(idb_key3, 8) end)

  (* Step 4: IDB delete done — set 5s exit timer *)
  val p5 = ward_promise_then<int><int>(p4,
    lam (del_status: int) =<cloref1>
      ward_timer_set(5000))

  (* Step 5: 5s timer fires — clean up and exit *)
  val p6 = ward_promise_then<int><int>(p5,
    lam (x2: int) =<cloref1> let
      val dom = ward_dom_load()
      val () = ward_dom_fini(dom)
      val () = ward_exit()
    in ward_promise_return<int>(0) end)

  val () = ward_promise_discard<int><Pending>(p6)
in end
