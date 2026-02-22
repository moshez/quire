(* modals.dats — Modal and banner implementations for duplicate, reset, error UI *)

#define ATS_DYNLOADFLAG 0

#include "share/atspre_staload.hats"
staload "./quire.sats"
staload "./quire_ui.sats"
staload "./modals.sats"
staload "./quire_text.sats"
staload "./ui_classes.sats"
staload "./app_state.sats"
staload "./dom.sats"
staload "./arith.sats"
staload "./library.sats"
staload "./buf.sats"
staload "./quire_ext.sats"
staload "./../vendor/ward/lib/memory.sats"
staload "./../vendor/ward/lib/dom.sats"
staload "./../vendor/ward/lib/listener.sats"
staload "./../vendor/ward/lib/event.sats"
staload "./../vendor/ward/lib/file.sats"
staload _ = "./../vendor/ward/lib/memory.dats"
staload _ = "./../vendor/ward/lib/dom.dats"
staload _ = "./../vendor/ward/lib/listener.dats"
staload _ = "./../vendor/ward/lib/event.dats"
staload _ = "./../vendor/ward/lib/file.dats"
staload "./../vendor/ward/lib/promise.sats"
staload _ = "./../vendor/ward/lib/promise.dats"
staload "./epub.sats"

%{
extern void quire_factory_reset(void);
%}

extern castfn _mk_book_access(x: int): [i:nat | i < 32] (BOOK_ACCESS_SAFE(i) | int(i))
extern castfn _checked_spine_count(x: int): [n:nat | n <= 256] int n

(* ========== Duplicate modal CSS class builders ========== *)

implement cls_dup_overlay(): ward_safe_text(11) = let
  val b = ward_text_build(11)
  val b = ward_text_putc(b, 0, char2int1('d'))
  val b = ward_text_putc(b, 1, char2int1('u'))
  val b = ward_text_putc(b, 2, char2int1('p'))
  val b = ward_text_putc(b, 3, 45) (* '-' *)
  val b = ward_text_putc(b, 4, char2int1('o'))
  val b = ward_text_putc(b, 5, char2int1('v'))
  val b = ward_text_putc(b, 6, char2int1('e'))
  val b = ward_text_putc(b, 7, char2int1('r'))
  val b = ward_text_putc(b, 8, char2int1('l'))
  val b = ward_text_putc(b, 9, char2int1('a'))
  val b = ward_text_putc(b, 10, char2int1('y'))
in ward_text_done(b) end

implement cls_dup_modal(): ward_safe_text(9) = let
  val b = ward_text_build(9)
  val b = ward_text_putc(b, 0, char2int1('d'))
  val b = ward_text_putc(b, 1, char2int1('u'))
  val b = ward_text_putc(b, 2, char2int1('p'))
  val b = ward_text_putc(b, 3, 45) (* '-' *)
  val b = ward_text_putc(b, 4, char2int1('m'))
  val b = ward_text_putc(b, 5, char2int1('o'))
  val b = ward_text_putc(b, 6, char2int1('d'))
  val b = ward_text_putc(b, 7, char2int1('a'))
  val b = ward_text_putc(b, 8, char2int1('l'))
in ward_text_done(b) end

implement cls_dup_title(): ward_safe_text(9) = let
  val b = ward_text_build(9)
  val b = ward_text_putc(b, 0, char2int1('d'))
  val b = ward_text_putc(b, 1, char2int1('u'))
  val b = ward_text_putc(b, 2, char2int1('p'))
  val b = ward_text_putc(b, 3, 45) (* '-' *)
  val b = ward_text_putc(b, 4, char2int1('t'))
  val b = ward_text_putc(b, 5, char2int1('i'))
  val b = ward_text_putc(b, 6, char2int1('t'))
  val b = ward_text_putc(b, 7, char2int1('l'))
  val b = ward_text_putc(b, 8, char2int1('e'))
in ward_text_done(b) end

implement cls_dup_msg(): ward_safe_text(7) = let
  val b = ward_text_build(7)
  val b = ward_text_putc(b, 0, char2int1('d'))
  val b = ward_text_putc(b, 1, char2int1('u'))
  val b = ward_text_putc(b, 2, char2int1('p'))
  val b = ward_text_putc(b, 3, 45) (* '-' *)
  val b = ward_text_putc(b, 4, char2int1('m'))
  val b = ward_text_putc(b, 5, char2int1('s'))
  val b = ward_text_putc(b, 6, char2int1('g'))
in ward_text_done(b) end

implement cls_dup_actions(): ward_safe_text(11) = let
  val b = ward_text_build(11)
  val b = ward_text_putc(b, 0, char2int1('d'))
  val b = ward_text_putc(b, 1, char2int1('u'))
  val b = ward_text_putc(b, 2, char2int1('p'))
  val b = ward_text_putc(b, 3, 45) (* '-' *)
  val b = ward_text_putc(b, 4, char2int1('a'))
  val b = ward_text_putc(b, 5, char2int1('c'))
  val b = ward_text_putc(b, 6, char2int1('t'))
  val b = ward_text_putc(b, 7, char2int1('i'))
  val b = ward_text_putc(b, 8, char2int1('o'))
  val b = ward_text_putc(b, 9, char2int1('n'))
  val b = ward_text_putc(b, 10, char2int1('s'))
in ward_text_done(b) end

implement cls_dup_btn(): ward_safe_text(7) = let
  val b = ward_text_build(7)
  val b = ward_text_putc(b, 0, char2int1('d'))
  val b = ward_text_putc(b, 1, char2int1('u'))
  val b = ward_text_putc(b, 2, char2int1('p'))
  val b = ward_text_putc(b, 3, 45) (* '-' *)
  val b = ward_text_putc(b, 4, char2int1('b'))
  val b = ward_text_putc(b, 5, char2int1('t'))
  val b = ward_text_putc(b, 6, char2int1('n'))
in ward_text_done(b) end

implement cls_dup_replace(): ward_safe_text(11) = let
  val b = ward_text_build(11)
  val b = ward_text_putc(b, 0, char2int1('d'))
  val b = ward_text_putc(b, 1, char2int1('u'))
  val b = ward_text_putc(b, 2, char2int1('p'))
  val b = ward_text_putc(b, 3, 45) (* '-' *)
  val b = ward_text_putc(b, 4, char2int1('r'))
  val b = ward_text_putc(b, 5, char2int1('e'))
  val b = ward_text_putc(b, 6, char2int1('p'))
  val b = ward_text_putc(b, 7, char2int1('l'))
  val b = ward_text_putc(b, 8, char2int1('a'))
  val b = ward_text_putc(b, 9, char2int1('c'))
  val b = ward_text_putc(b, 10, char2int1('e'))
in ward_text_done(b) end

(* ========== Error banner CSS class builders ========== *)

(* "err-banner" = 10 chars *)
implement cls_err_banner(): ward_safe_text(10) = let
  val b = ward_text_build(10)
  val b = ward_text_putc(b, 0, char2int1('e'))
  val b = ward_text_putc(b, 1, char2int1('r'))
  val b = ward_text_putc(b, 2, char2int1('r'))
  val b = ward_text_putc(b, 3, 45) (* '-' *)
  val b = ward_text_putc(b, 4, char2int1('b'))
  val b = ward_text_putc(b, 5, char2int1('a'))
  val b = ward_text_putc(b, 6, char2int1('n'))
  val b = ward_text_putc(b, 7, char2int1('n'))
  val b = ward_text_putc(b, 8, char2int1('e'))
  val b = ward_text_putc(b, 9, char2int1('r'))
in ward_text_done(b) end

(* "err-close" = 9 chars *)
implement cls_err_close(): ward_safe_text(9) = let
  val b = ward_text_build(9)
  val b = ward_text_putc(b, 0, char2int1('e'))
  val b = ward_text_putc(b, 1, char2int1('r'))
  val b = ward_text_putc(b, 2, char2int1('r'))
  val b = ward_text_putc(b, 3, 45) (* '-' *)
  val b = ward_text_putc(b, 4, char2int1('c'))
  val b = ward_text_putc(b, 5, char2int1('l'))
  val b = ward_text_putc(b, 6, char2int1('o'))
  val b = ward_text_putc(b, 7, char2int1('s'))
  val b = ward_text_putc(b, 8, char2int1('e'))
in ward_text_done(b) end

(* ========== Duplicate modal CSS ========== *)

#define DUP_CSS_WRITES 140
stadef DUP_CSS_WRITES = 140
stadef DUP_CSS_LEN = DUP_CSS_WRITES * 4
#define DUP_CSS_LEN 560

fn fill_css_dup {l:agz}{n:int | n >= DUP_CSS_LEN}
  (arr: !ward_arr(byte, l, n), alen: int n): void = let
  val () = _w4(arr, alen, 0, 1886741550)
  val () = _w4(arr, alen, 4, 1702260525)
  val () = _w4(arr, alen, 8, 2036427890)
  val () = _w4(arr, alen, 12, 1936683131)
  val () = _w4(arr, alen, 16, 1869182057)
  val () = _w4(arr, alen, 20, 1768307310)
  val () = _w4(arr, alen, 24, 996435320)
  val () = _w4(arr, alen, 28, 1702063721)
  val () = _w4(arr, alen, 32, 993016436)
  val () = _w4(arr, alen, 36, 1801675106)
  val () = _w4(arr, alen, 40, 1970238055)
  val () = _w4(arr, alen, 44, 1916429422)
  val () = _w4(arr, alen, 48, 677470823)
  val () = _w4(arr, alen, 52, 741354544)
  val () = _w4(arr, alen, 56, 875441200)
  val () = _w4(arr, alen, 60, 1768176425)
  val () = _w4(arr, alen, 64, 1634496627)
  val () = _w4(arr, alen, 68, 1818638969)
  val () = _w4(arr, alen, 72, 1631287397)
  val () = _w4(arr, alen, 76, 1852270956)
  val () = _w4(arr, alen, 80, 1702127917)
  val () = _w4(arr, alen, 84, 1664775021)
  val () = _w4(arr, alen, 88, 1702129253)
  val () = _w4(arr, alen, 92, 1969896306)
  val () = _w4(arr, alen, 96, 1718187123)
  val () = _w4(arr, alen, 100, 1868770681)
  val () = _w4(arr, alen, 104, 1852142702)
  val () = _w4(arr, alen, 108, 1701001844)
  val () = _w4(arr, alen, 112, 1919251566)
  val () = _w4(arr, alen, 116, 1764588091)
  val () = _w4(arr, alen, 120, 2019910766)
  val () = _w4(arr, alen, 124, 808464698)
  val () = _w4(arr, alen, 128, 1969499773)
  val () = _w4(arr, alen, 132, 1869426032)
  val () = _w4(arr, alen, 136, 2070700388)
  val () = _w4(arr, alen, 140, 1801675106)
  val () = _w4(arr, alen, 144, 1970238055)
  val () = _w4(arr, alen, 148, 591029358)
  val () = _w4(arr, alen, 152, 996566630)
  val () = _w4(arr, alen, 156, 1685221218)
  val () = _w4(arr, alen, 160, 1915581029)
  val () = _w4(arr, alen, 164, 1969841249)
  val () = _w4(arr, alen, 168, 1882733171)
  val () = _w4(arr, alen, 172, 1634745208)
  val () = _w4(arr, alen, 176, 1852400740)
  val () = _w4(arr, alen, 180, 774978151)
  val () = _w4(arr, alen, 184, 1835364917)
  val () = _w4(arr, alen, 188, 2019650875)
  val () = _w4(arr, alen, 192, 1684633389)
  val () = _w4(arr, alen, 196, 842688628)
  val () = _w4(arr, alen, 200, 1835364916)
  val () = _w4(arr, alen, 204, 1684633403)
  val () = _w4(arr, alen, 208, 960129140)
  val () = _w4(arr, alen, 212, 1950033200)
  val () = _w4(arr, alen, 216, 762607717)
  val () = _w4(arr, alen, 220, 1734962273)
  val () = _w4(arr, alen, 224, 1701001838)
  val () = _w4(arr, alen, 228, 1919251566)
  val () = _w4(arr, alen, 232, 1969499773)
  val () = _w4(arr, alen, 236, 1769221488)
  val () = _w4(arr, alen, 240, 2070244468)
  val () = _w4(arr, alen, 244, 1953394534)
  val () = _w4(arr, alen, 248, 1768257325)
  val () = _w4(arr, alen, 252, 980707431)
  val () = _w4(arr, alen, 256, 993013815)
  val () = _w4(arr, alen, 260, 1735549293)
  val () = _w4(arr, alen, 264, 1647144553)
  val () = _w4(arr, alen, 268, 1869902959)
  val () = _w4(arr, alen, 272, 892222061)
  val () = _w4(arr, alen, 276, 2104321394)
  val () = _w4(arr, alen, 280, 1886741550)
  val () = _w4(arr, alen, 284, 1735617837)
  val () = _w4(arr, alen, 288, 1819239291)
  val () = _w4(arr, alen, 292, 591032943)
  val () = _w4(arr, alen, 296, 993408566)
  val () = _w4(arr, alen, 300, 1735549293)
  val () = _w4(arr, alen, 304, 1647144553)
  val () = _w4(arr, alen, 308, 1869902959)
  val () = _w4(arr, alen, 312, 774978157)
  val () = _w4(arr, alen, 316, 1835364917)
  val () = _w4(arr, alen, 320, 1969499773)
  val () = _w4(arr, alen, 324, 1667313008)
  val () = _w4(arr, alen, 328, 1852795252)
  val () = _w4(arr, alen, 332, 1768192883)
  val () = _w4(arr, alen, 336, 1634496627)
  val () = _w4(arr, alen, 340, 1818638969)
  val () = _w4(arr, alen, 344, 1731950693)
  val () = _w4(arr, alen, 348, 775581793)
  val () = _w4(arr, alen, 352, 1701983543)
  val () = _w4(arr, alen, 356, 1969896301)
  val () = _w4(arr, alen, 360, 1718187123)
  val () = _w4(arr, alen, 364, 1868770681)
  val () = _w4(arr, alen, 368, 1852142702)
  val () = _w4(arr, alen, 372, 1701001844)
  val () = _w4(arr, alen, 376, 1919251566)
  val () = _w4(arr, alen, 380, 1969499773)
  val () = _w4(arr, alen, 384, 1952591216)
  val () = _w4(arr, alen, 388, 1680747630)
  val () = _w4(arr, alen, 392, 1915580533)
  val () = _w4(arr, alen, 396, 1634496613)
  val () = _w4(arr, alen, 400, 1887135075)
  val () = _w4(arr, alen, 404, 1768186977)
  val () = _w4(arr, alen, 408, 775579502)
  val () = _w4(arr, alen, 412, 1835364917)
  val () = _w4(arr, alen, 416, 892219680)
  val () = _w4(arr, alen, 420, 997025138)
  val () = _w4(arr, alen, 424, 1685221218)
  val () = _w4(arr, alen, 428, 1915581029)
  val () = _w4(arr, alen, 432, 1969841249)
  val () = _w4(arr, alen, 436, 1882471027)
  val () = _w4(arr, alen, 440, 1868708728)
  val () = _w4(arr, alen, 444, 1919247474)
  val () = _w4(arr, alen, 448, 2020618554)
  val () = _w4(arr, alen, 452, 1819243296)
  val () = _w4(arr, alen, 456, 589325417)
  val () = _w4(arr, alen, 460, 996369251)
  val () = _w4(arr, alen, 464, 1936880995)
  val () = _w4(arr, alen, 468, 1882878575)
  val () = _w4(arr, alen, 472, 1953393007)
  val () = _w4(arr, alen, 476, 1715171941)
  val () = _w4(arr, alen, 480, 762605167)
  val () = _w4(arr, alen, 484, 1702521203)
  val () = _w4(arr, alen, 488, 1701982522)
  val () = _w4(arr, alen, 492, 1680768365)
  val () = _w4(arr, alen, 496, 1915580533)
  val () = _w4(arr, alen, 500, 1634496613)
  val () = _w4(arr, alen, 504, 1652254051)
  val () = _w4(arr, alen, 508, 1735091041)
  val () = _w4(arr, alen, 512, 1853190002)
  val () = _w4(arr, alen, 516, 874723940)
  val () = _w4(arr, alen, 520, 895694689)
  val () = _w4(arr, alen, 524, 1868774201)
  val () = _w4(arr, alen, 528, 980578156)
  val () = _w4(arr, alen, 532, 1717986851)
  val () = _w4(arr, alen, 536, 1919902267)
  val () = _w4(arr, alen, 540, 762471780)
  val () = _w4(arr, alen, 544, 1869377379)
  val () = _w4(arr, alen, 548, 874723954)
  val () = _w4(arr, alen, 552, 895694689)
  val () = _w4(arr, alen, 556, 539000121)
in end

(* Inject dup modal CSS as a separate <style> element.
 * Called when rendering the duplicate modal overlay. *)
fn inject_dup_css(parent: int): void = let
  val dup_arr = ward_arr_alloc<byte>(DUP_CSS_LEN)
  val () = fill_css_dup(dup_arr, DUP_CSS_LEN)
  val style_id = dom_next_id()
  val dom = ward_dom_init()
  val s = ward_dom_stream_begin(dom)
  val s = ward_dom_stream_create_element(s, style_id, parent, tag_style(), 5)
  val @(frozen, borrow) = ward_arr_freeze<byte>(dup_arr)
  val s = ward_dom_stream_set_text(s, style_id, borrow, DUP_CSS_LEN)
  val () = ward_arr_drop<byte>(frozen, borrow)
  val dup_arr = ward_arr_thaw<byte>(frozen)
  val () = ward_arr_free<byte>(dup_arr)
  val dom = ward_dom_stream_end(s)
  val () = ward_dom_fini(dom)
in end

(* Render duplicate book modal: overlay with book title, message, Skip and Replace buttons.
 * Uses dup_idx to look up book title from library. *)
implement render_dup_modal(dup_idx, root) = let
  (* Inject dup CSS under root *)
  val () = inject_dup_css(root)

  val dom = ward_dom_init()
  val s = ward_dom_stream_begin(dom)

  (* Overlay *)
  val overlay_id = dom_next_id()
  val s = ward_dom_stream_create_element(s, overlay_id, root, tag_div(), 3)
  val s = ward_dom_stream_set_attr_safe(s, overlay_id, attr_class(), 5,
    cls_dup_overlay(), 11)
  val () = _app_set_dup_overlay_id(overlay_id)

  (* Modal container *)
  val modal_id = dom_next_id()
  val s = ward_dom_stream_create_element(s, modal_id, overlay_id, tag_div(), 3)
  val s = ward_dom_stream_set_attr_safe(s, modal_id, attr_class(), 5,
    cls_dup_modal(), 9)

  (* Title: show existing book's title *)
  val title_div_id = dom_next_id()
  val s = ward_dom_stream_create_element(s, title_div_id, modal_id, tag_div(), 3)
  val s = ward_dom_stream_set_attr_safe(s, title_div_id, attr_class(), 5,
    cls_dup_title(), 9)
  val title_len = library_get_title(dup_idx, 0)
  val s = set_text_from_sbuf(s, title_div_id, title_len)

  (* Message: "Already in library" *)
  val msg_id = dom_next_id()
  val s = ward_dom_stream_create_element(s, msg_id, modal_id, tag_div(), 3)
  val s = ward_dom_stream_set_attr_safe(s, msg_id, attr_class(), 5,
    cls_dup_msg(), 7)
  val s = set_text_cstr(VT_32() | s, msg_id, 32, 18)

  (* Actions container *)
  val actions_id = dom_next_id()
  val s = ward_dom_stream_create_element(s, actions_id, modal_id, tag_div(), 3)
  val s = ward_dom_stream_set_attr_safe(s, actions_id, attr_class(), 5,
    cls_dup_actions(), 11)

  (* Skip button *)
  val skip_btn_id = dom_next_id()
  val s = ward_dom_stream_create_element(s, skip_btn_id, actions_id, tag_button(), 6)
  val s = ward_dom_stream_set_attr_safe(s, skip_btn_id, attr_class(), 5,
    cls_dup_btn(), 7)
  val s = set_text_cstr(VT_30() | s, skip_btn_id, 30, 4)

  (* Replace button *)
  val replace_btn_id = dom_next_id()
  val s = ward_dom_stream_create_element(s, replace_btn_id, actions_id, tag_button(), 6)
  val s = ward_dom_stream_set_attr_safe(s, replace_btn_id, attr_class(), 5,
    cls_dup_replace(), 11)
  val s = set_text_cstr(VT_31() | s, replace_btn_id, 31, 7)

  val dom = ward_dom_stream_end(s)
  val () = ward_dom_fini(dom)

  (* Register click listeners on buttons *)
  val () = ward_add_event_listener(
    skip_btn_id, evt_click(), 5, LISTENER_DUP_SKIP,
    lam (_pl: int): int => let
      val () = _app_set_dup_choice(1) (* skip *)
    in 0 end
  )
  val () = ward_add_event_listener(
    replace_btn_id, evt_click(), 5, LISTENER_DUP_REPLACE,
    lam (_pl: int): int => let
      val () = _app_set_dup_choice(2) (* replace *)
    in 0 end
  )
in end

(* Remove the duplicate modal overlay from the DOM *)
implement dismiss_dup_modal() = let
  val overlay_id = _app_dup_overlay_id()
in
  if gt_int_int(overlay_id, 0) then let
    val dom = ward_dom_init()
    val s = ward_dom_stream_begin(dom)
    val s = ward_dom_stream_remove_child(s, overlay_id)
    val dom = ward_dom_stream_end(s)
    val () = ward_dom_fini(dom)
    val () = _app_set_dup_overlay_id(0)
  in end
  else ()
end

(* Remove the factory reset modal overlay from the DOM *)
implement dismiss_reset_modal() = let
  val overlay_id = _app_reset_overlay_id()
in
  if gt_int_int(overlay_id, 0) then let
    val dom = ward_dom_init()
    val s = ward_dom_stream_begin(dom)
    val s = ward_dom_stream_remove_child(s, overlay_id)
    val dom = ward_dom_stream_end(s)
    val () = ward_dom_fini(dom)
    val () = _app_set_reset_overlay_id(0)
  in end
  else ()
end

(* Render factory reset confirmation modal *)
implement render_reset_modal(root) = let
  val dom = ward_dom_init()
  val s = ward_dom_stream_begin(dom)

  (* Overlay *)
  val overlay_id = dom_next_id()
  val s = ward_dom_stream_create_element(s, overlay_id, root, tag_div(), 3)
  val s = ward_dom_stream_set_attr_safe(s, overlay_id, attr_class(), 5,
    cls_dup_overlay(), 11)
  val () = _app_set_reset_overlay_id(overlay_id)

  (* Modal container *)
  val modal_id = dom_next_id()
  val s = ward_dom_stream_create_element(s, modal_id, overlay_id, tag_div(), 3)
  val s = ward_dom_stream_set_attr_safe(s, modal_id, attr_class(), 5,
    cls_dup_modal(), 9)

  (* Message: "Delete all data?" *)
  val msg_id = dom_next_id()
  val s = ward_dom_stream_create_element(s, msg_id, modal_id, tag_div(), 3)
  val s = ward_dom_stream_set_attr_safe(s, msg_id, attr_class(), 5,
    cls_dup_msg(), 7)
  val s = set_text_cstr(VT_34() | s, msg_id, 34, 16)

  (* Actions container *)
  val actions_id = dom_next_id()
  val s = ward_dom_stream_create_element(s, actions_id, modal_id, tag_div(), 3)
  val s = ward_dom_stream_set_attr_safe(s, actions_id, attr_class(), 5,
    cls_dup_actions(), 11)

  (* Cancel button *)
  val cancel_btn_id = dom_next_id()
  val s = ward_dom_stream_create_element(s, cancel_btn_id, actions_id, tag_button(), 6)
  val s = ward_dom_stream_set_attr_safe(s, cancel_btn_id, attr_class(), 5,
    cls_dup_btn(), 7)
  val s = set_text_cstr(VT_35() | s, cancel_btn_id, 35, 6)

  (* Reset button *)
  val reset_btn_id = dom_next_id()
  val s = ward_dom_stream_create_element(s, reset_btn_id, actions_id, tag_button(), 6)
  val s = ward_dom_stream_set_attr_safe(s, reset_btn_id, attr_class(), 5,
    cls_dup_replace(), 11)
  val s = set_text_cstr(VT_33() | s, reset_btn_id, 33, 5)

  val dom = ward_dom_stream_end(s)
  val () = ward_dom_fini(dom)

  (* Register click listeners *)
  val () = ward_add_event_listener(
    cancel_btn_id, evt_click(), 5, LISTENER_RESET_CANCEL,
    lam (_pl: int): int => let
      val () = dismiss_reset_modal()
    in 0 end
  )
  val () = ward_add_event_listener(
    reset_btn_id, evt_click(), 5, LISTENER_RESET_CONFIRM,
    lam (_pl: int): int => let
      val () = quire_factory_reset()
    in 0 end
  )
in end

(* ========== Error banner CSS + rendering ========== *)

(* css_hex3: write "#rgb" to ward_arr at offset.
 * Each nibble is [0,15] — constraint solver verifies valid hex.
 * Hex digit: 0-9 → 48-57 ('0'-'9'), 10-15 → 97-102 ('a'-'f'). *)
implement css_hex_digit {v} (v) =
  if lt_int_int(_g0(v), 10) then _g0(v) + 48
  else _g0(v) + 87

implement css_hex3 {l}{n}{r,g,b}
  (arr, off, cap, r, g, b) = let
  val () = ward_arr_set_byte(arr, off, cap, 35)   (* '#' *)
  val () = ward_arr_set_byte(arr, off + 1, cap, css_hex_digit(r))
  val () = ward_arr_set_byte(arr, off + 2, cap, css_hex_digit(g))
  val () = ward_arr_set_byte(arr, off + 3, cap, css_hex_digit(b))
in off + 4 end

(* css_dim: write "Npx" where N is a nat, 1-2 digits.
 * Returns new offset. *)
implement css_dim {l}{n}{v}
  (arr, off, cap, value) =
  if lt_int_int(_g0(value), 10) then let
    val () = ward_arr_set_byte(arr, off, cap, _g0(value) + 48)
    val () = ward_arr_set_byte(arr, off + 1, cap, 112) (* 'p' *)
    val () = ward_arr_set_byte(arr, off + 2, cap, 120) (* 'x' *)
  in off + 3 end
  else let
    val tens = div_int_int(_g0(value), 10)
    val ones = mod_int_int(_g0(value), 10)
    val () = ward_arr_set_byte(arr, off, cap, tens + 48)
    val () = ward_arr_set_byte(arr, off + 1, cap, ones + 48)
    val () = ward_arr_set_byte(arr, off + 2, cap, 112) (* 'p' *)
    val () = ward_arr_set_byte(arr, off + 3, cap, 120) (* 'x' *)
  in off + 4 end

(* Error banner CSS — typed builder for provable colors + dimensions.
 * .err-banner{background:#fee;color:#922;padding:12px 16px;position:relative;
 *   border-bottom:1px solid #d99;margin-bottom:8px}
 * .err-close{position:absolute;top:4px;right:4px;background:none;border:none;
 *   font-size:20px;cursor:pointer;color:inherit;padding:4px 8px}
 *)
#define ERR_CSS_LEN 257

fn fill_css_err {l:agz}{n:int | n >= ERR_CSS_LEN}
  (arr: !ward_arr(byte, l, n), alen: int n): void = let
  (* .err-banner{background:#fee;color:#922;padding:12px 16px;
   * position:relative;border-bottom:1px solid #d99;margin-bottom:8px}
   * .err-close{position:absolute;top:4px;right:4px;background:none;
   * border:none;font-size:20px;cursor:pointer;color:inherit;padding:4px 8px} *)
  val () = _w4(arr, alen, 0, 1920099630)       (* .err *)
  val () = _w4(arr, alen, 4, 1851875885)       (* -ban *)
  val () = _w4(arr, alen, 8, 2071094638)       (* ner{ *)
  val () = _w4(arr, alen, 12, 1801675106)      (* back *)
  val () = _w4(arr, alen, 16, 1970238055)      (* grou *)
  val () = ward_arr_set_byte(arr, 20, alen, 110) (* n *)
  val () = ward_arr_set_byte(arr, 21, alen, 100) (* d *)
  val () = ward_arr_set_byte(arr, 22, alen, 58)  (* : *)
  val o = css_hex3(arr, 23, alen, 15, 14, 14)  (* #fee *)
  val () = _w4(arr, alen, o, 1819239227)        (* ;col *)
  val o = o + 4
  val () = ward_arr_set_byte(arr, o, alen, 111)  (* o *)
  val () = ward_arr_set_byte(arr, o+1, alen, 114) (* r *)
  val () = ward_arr_set_byte(arr, o+2, alen, 58)  (* : *)
  val o = css_hex3(arr, o+3, alen, 9, 2, 2)    (* #922 *)
  val () = _w4(arr, alen, o, 1684107323)        (* ;pad *)
  val () = _w4(arr, alen, o+4, 1735289188)      (* ding *)
  val () = ward_arr_set_byte(arr, o+8, alen, 58) (* : *)
  val o = css_dim(arr, o+9, alen, 12)           (* 12px *)
  val () = ward_arr_set_byte(arr, o, alen, 32)   (*   *)
  val o = css_dim(arr, o+1, alen, 16)           (* 16px *)
  val () = _w4(arr, alen, o, 1936683067)        (* ;pos *)
  val () = _w4(arr, alen, o+4, 1869182057)      (* itio *)
  val () = _w4(arr, alen, o+8, 1701984878)      (* n:re *)
  val () = _w4(arr, alen, o+12, 1769234796)     (* lati *)
  val () = _w4(arr, alen, o+16, 1648059766)     (* ve;b *)
  val () = _w4(arr, alen, o+20, 1701081711)     (* orde *)
  val () = _w4(arr, alen, o+24, 1868705138)     (* r-bo *)
  val () = _w4(arr, alen, o+28, 1836020852)     (* ttom *)
  val () = ward_arr_set_byte(arr, o+32, alen, 58) (* : *)
  val o = css_dim(arr, o+33, alen, 1)           (* 1px *)
  val () = _w4(arr, alen, o, 1819243296)        (*  sol *)
  val () = ward_arr_set_byte(arr, o+4, alen, 105) (* i *)
  val () = ward_arr_set_byte(arr, o+5, alen, 100) (* d *)
  val () = ward_arr_set_byte(arr, o+6, alen, 32)  (*   *)
  val o = css_hex3(arr, o+7, alen, 13, 9, 9)   (* #d99 *)
  val () = _w4(arr, alen, o, 1918987579)        (* ;mar *)
  val () = _w4(arr, alen, o+4, 762210663)       (* gin- *)
  val () = _w4(arr, alen, o+8, 1953787746)      (* bott *)
  val () = ward_arr_set_byte(arr, o+12, alen, 111) (* o *)
  val () = ward_arr_set_byte(arr, o+13, alen, 109) (* m *)
  val () = ward_arr_set_byte(arr, o+14, alen, 58)  (* : *)
  val o = css_dim(arr, o+15, alen, 8)           (* 8px *)
  val () = _w4(arr, alen, o, 1919233661)        (* }.er *)
  val () = _w4(arr, alen, o+4, 1818439026)      (* r-cl *)
  val () = _w4(arr, alen, o+8, 2070246255)      (* ose{ *)
  val () = _w4(arr, alen, o+12, 1769172848)     (* posi *)
  val () = _w4(arr, alen, o+16, 1852795252)     (* tion *)
  val () = _w4(arr, alen, o+20, 1935827258)     (* :abs *)
  val () = _w4(arr, alen, o+24, 1953852527)     (* olut *)
  val () = _w4(arr, alen, o+28, 1869888357)     (* e;to *)
  val () = ward_arr_set_byte(arr, o+32, alen, 112) (* p *)
  val () = ward_arr_set_byte(arr, o+33, alen, 58)  (* : *)
  val o = css_dim(arr, o+34, alen, 4)           (* 4px *)
  val () = _w4(arr, alen, o, 1734963771)        (* ;rig *)
  val () = ward_arr_set_byte(arr, o+4, alen, 104) (* h *)
  val () = ward_arr_set_byte(arr, o+5, alen, 116) (* t *)
  val () = ward_arr_set_byte(arr, o+6, alen, 58)  (* : *)
  val o = css_dim(arr, o+7, alen, 4)            (* 4px *)
  val () = _w4(arr, alen, o, 1667326523)        (* ;bac *)
  val () = _w4(arr, alen, o+4, 1869768555)      (* kgro *)
  val () = _w4(arr, alen, o+8, 979660405)       (* und: *)
  val () = _w4(arr, alen, o+12, 1701736302)     (* none *)
  val () = _w4(arr, alen, o+16, 1919902267)     (* ;bor *)
  val () = _w4(arr, alen, o+20, 980575588)      (* der: *)
  val () = _w4(arr, alen, o+24, 1701736302)     (* none *)
  val () = _w4(arr, alen, o+28, 1852794427)     (* ;fon *)
  val () = _w4(arr, alen, o+32, 1769155956)     (* t-si *)
  val () = ward_arr_set_byte(arr, o+36, alen, 122) (* z *)
  val () = ward_arr_set_byte(arr, o+37, alen, 101) (* e *)
  val () = ward_arr_set_byte(arr, o+38, alen, 58)  (* : *)
  val o = css_dim(arr, o+39, alen, 20)          (* 20px *)
  val () = _w4(arr, alen, o, 1920295739)        (* ;cur *)
  val () = _w4(arr, alen, o+4, 980578163)       (* sor: *)
  val () = _w4(arr, alen, o+8, 1852403568)      (* poin *)
  val () = _w4(arr, alen, o+12, 997352820)      (* ter; *)
  val () = _w4(arr, alen, o+16, 1869377379)     (* colo *)
  val () = _w4(arr, alen, o+20, 1852390002)     (* r:in *)
  val () = _w4(arr, alen, o+24, 1769104744)     (* heri *)
  val () = _w4(arr, alen, o+28, 1634745204)     (* t;pa *)
  val () = _w4(arr, alen, o+32, 1852400740)     (* ddin *)
  val () = ward_arr_set_byte(arr, o+36, alen, 103) (* g *)
  val () = ward_arr_set_byte(arr, o+37, alen, 58)  (* : *)
  val o = css_dim(arr, o+38, alen, 4)           (* 4px *)
  val () = ward_arr_set_byte(arr, o, alen, 32)   (*   *)
  val o = css_dim(arr, o+1, alen, 8)            (* 8px *)
  val () = ward_arr_set_byte(arr, o, alen, 125)  (* } *)
in end

(* Inject error banner CSS into a new <style> element *)
fn inject_err_css(parent: int): void = let
  val dom = ward_dom_init()
  val s = ward_dom_stream_begin(dom)
  val style_id = dom_next_id()
  val s = ward_dom_stream_create_element(s, style_id, parent, tag_style(), 5)
  val arr = ward_arr_alloc<byte>(ERR_CSS_LEN)
  val () = fill_css_err(arr, ERR_CSS_LEN)
  val @(frozen, borrow) = ward_arr_freeze<byte>(arr)
  val s = ward_dom_stream_set_text(s, style_id, borrow, ERR_CSS_LEN)
  val () = ward_arr_drop<byte>(frozen, borrow)
  val arr = ward_arr_thaw<byte>(frozen)
  val () = ward_arr_free<byte>(arr)
  val dom = ward_dom_stream_end(s)
  val () = ward_dom_fini(dom)
in end

(* Dismiss error banner *)
implement dismiss_error_banner() = let
  val banner_id = _app_err_banner_id()
in
  if gt_int_int(banner_id, 0) then let
    val dom = ward_dom_init()
    val s = ward_dom_stream_begin(dom)
    val s = ward_dom_stream_remove_child(s, banner_id)
    val dom = ward_dom_stream_end(s)
    val () = ward_dom_fini(dom)
    val () = _app_set_err_banner_id(0)
  in end
  else ()
end

(* Copy filename bytes to string buffer. Returns bytes copied.
 * Uses ward_file_get_name_len / ward_file_get_name from ward.
 * Dependent return [n:nat] bounds caller's use of length. *)
implement copy_filename_to_sbuf(max_len) = let
  val raw_len = ward_file_get_name_len()
  val use_len: int = if lt_int_int(raw_len, max_len) then raw_len else max_len
  val name_len = _checked_nat(use_len)
in
  if lte_g1(name_len, 0) then 0
  else let
    val name_arr = ward_file_get_name(name_len)
    fun _copy_name {la:agz}{nc:pos}{k:nat} .<k>.
      (rem: int(k), narr: !ward_arr(byte, la, nc), nlen: int nc, i: int): void =
      if lte_g1(rem, 0) then ()
      else let
        val b = byte2int0(ward_arr_get<byte>(narr, _ward_idx(i, nlen)))
        val () = _app_sbuf_set_u8(i, b)
      in _copy_name(sub_g1(rem, 1), narr, nlen, i + 1) end
    val () = _copy_name(name_len, name_arr, name_len, 0)
    val () = ward_arr_free<byte>(name_arr)
  in name_len end
end

(* Render error banner with filename and DRM message.
 * DOM structure:
 *   <div class="err-banner">
 *     <button class="err-close">X</button>
 *     <div style="font-weight:bold">"Import failed"</div>
 *     <div>"filename.ext" is not a valid ePub file.</div>
 *     <div>Quire supports .epub files without DRM.</div>
 *   </div> *)
implement render_error_banner(root) = let
  (* Dismiss any existing banner first *)
  val () = dismiss_error_banner()

  (* Inject CSS if not already present — idempotent via separate <style> *)
  val () = inject_err_css(root)

  val dom = ward_dom_init()
  val s = ward_dom_stream_begin(dom)

  (* Banner container *)
  val banner_id = dom_next_id()
  val s = ward_dom_stream_create_element(s, banner_id, root, tag_div(), 3)
  val s = ward_dom_stream_set_attr_safe(s, banner_id, attr_class(), 5,
    cls_err_banner(), 10)
  val () = _app_set_err_banner_id(banner_id)

  (* Close button: "X" *)
  val close_id = dom_next_id()
  val s = ward_dom_stream_create_element(s, close_id, banner_id, tag_button(), 6)
  val s = ward_dom_stream_set_attr_safe(s, close_id, attr_class(), 5,
    cls_err_close(), 9)
  val x_st = let
    val b = ward_text_build(1)
    val b = ward_text_putc(b, 0, 88) (* 'X' *)
  in ward_text_done(b) end
  val s = ward_dom_stream_set_safe_text(s, close_id, x_st, 1)

  (* Line 1: "Import failed" (bold via inline style) *)
  val line1_id = dom_next_id()
  val s = ward_dom_stream_create_element(s, line1_id, banner_id, tag_div(), 3)
  (* style: font-weight:bold — 16 bytes via ward_arr *)
  val fw_arr = ward_arr_alloc<byte>(16)
  val () = _w4(fw_arr, 16, 0, 1953394534)   (* font *)
  val () = _w4(fw_arr, 16, 4, 1768257325)   (* -wei *)
  val () = _w4(fw_arr, 16, 8, 980707431)    (* ght: *)
  val () = _w4(fw_arr, 16, 12, 1684828002)  (* bold *)
  val @(fw_frozen, fw_borrow) = ward_arr_freeze<byte>(fw_arr)
  val s = ward_dom_stream_set_style(s, line1_id, fw_borrow, 16)
  val () = ward_arr_drop<byte>(fw_frozen, fw_borrow)
  val fw_arr = ward_arr_thaw<byte>(fw_frozen)
  val () = ward_arr_free<byte>(fw_arr)
  val s = set_text_cstr(VT_29() | s, line1_id, 29, 13)

  (* Line 2: compose '"filename" is not a valid ePub file.' in ward_arr *)
  val name_len = copy_filename_to_sbuf(80)
  val line2_id = dom_next_id()
  val s = ward_dom_stream_create_element(s, line2_id, banner_id, tag_div(), 3)
in
  if gt_g1(name_len, 0) then let
    (* Total: 1 (") + name_len + 1 (") + 26 (suffix) = name_len + 28 *)
    val total = _g0(name_len) + 28
    val total_pos = g1ofg0(total)
  in
    if total_pos > 0 then
      if total_pos < 65536 then let
        val text_arr = ward_arr_alloc<byte>(total_pos)
        (* Opening quote *)
        val () = ward_arr_set_byte(text_arr, 0, total_pos, 34) (* '"' *)
        (* Copy filename from sbuf *)
        fun _copy_sb {ld:agz}{nd:pos}{k:nat} .<k>.
          (rem: int(k), dst: !ward_arr(byte, ld, nd), dlen: int nd, i: int): void =
          if lte_g1(rem, 0) then ()
          else let
            val b = _app_sbuf_get_u8(i)
            val () = ward_arr_set_byte(dst, i + 1, dlen, b)
          in _copy_sb(sub_g1(rem, 1), dst, dlen, i + 1) end
        val () = _copy_sb(name_len, text_arr, total_pos, 0)
        (* Closing quote *)
        val () = ward_arr_set_byte(text_arr, _g0(name_len) + 1, total_pos, 34)
        (* Suffix: " is not a valid ePub file." — 26 bytes from fill_text(36) *)
        val suffix_off = _g0(name_len) + 2
        val suffix_arr = ward_arr_alloc<byte>(26)
        val () = fill_text(suffix_arr, 26, 36)
        fun _copy_suffix {ld:agz}{nd:pos}{ls:agz}{ns:pos}{k:nat} .<k>.
          (rem: int(k), dst: !ward_arr(byte, ld, nd), dlen: int nd,
           src: !ward_arr(byte, ls, ns), slen: int ns, i: int): void =
          if lte_g1(rem, 0) then ()
          else let
            val b = byte2int0(ward_arr_get<byte>(src, _ward_idx(i, slen)))
            val () = ward_arr_set_byte(dst, suffix_off + i, dlen, b)
          in _copy_suffix(sub_g1(rem, 1), dst, dlen, src, slen, i + 1) end
        val () = _copy_suffix(_checked_nat(26), text_arr, total_pos, suffix_arr, 26, 0)
        val () = ward_arr_free<byte>(suffix_arr)
        val @(frozen2, borrow2) = ward_arr_freeze<byte>(text_arr)
        val s = ward_dom_stream_set_text(s, line2_id, borrow2, total_pos)
        val () = ward_arr_drop<byte>(frozen2, borrow2)
        val text_arr = ward_arr_thaw<byte>(frozen2)
        val () = ward_arr_free<byte>(text_arr)

        (* Line 3: DRM message *)
        val line3_id = dom_next_id()
        val s = ward_dom_stream_create_element(s, line3_id, banner_id, tag_div(), 3)
        val s = set_text_cstr(VT_37() | s, line3_id, 37, 39)

        val dom = ward_dom_stream_end(s)
        val () = ward_dom_fini(dom)
        val () = ward_add_event_listener(
          close_id, evt_click(), 5, LISTENER_ERR_DISMISS,
          lam (_pl: int): int => let val () = dismiss_error_banner() in 0 end)
      in end
      else let
        val dom = ward_dom_stream_end(s)
        val () = ward_dom_fini(dom)
        val () = ward_add_event_listener(
          close_id, evt_click(), 5, LISTENER_ERR_DISMISS,
          lam (_pl: int): int => let val () = dismiss_error_banner() in 0 end)
      in end
    else let
      val dom = ward_dom_stream_end(s)
      val () = ward_dom_fini(dom)
      val () = ward_add_event_listener(
        close_id, evt_click(), 5, LISTENER_ERR_DISMISS,
        lam (_pl: int): int => let val () = dismiss_error_banner() in 0 end)
    in end
  end
  else let
    (* No filename — just show DRM message *)
    val line3_id = dom_next_id()
    val s = ward_dom_stream_create_element(s, line3_id, banner_id, tag_div(), 3)
    val s = set_text_cstr(VT_37() | s, line3_id, 37, 39)
    val dom = ward_dom_stream_end(s)
    val () = ward_dom_fini(dom)
    val () = ward_add_event_listener(
      close_id, evt_click(), 5, LISTENER_ERR_DISMISS,
      lam (_pl: int): int => let val () = dismiss_error_banner() in 0 end)
  in end
end

(* Clear text content of a node by removing its children *)
implement clear_node(nid) = let
  val dom = ward_dom_init()
  val s = ward_dom_stream_begin(dom)
  val s = ward_dom_stream_remove_children(s, nid)
  val dom = ward_dom_stream_end(s)
  val () = ward_dom_fini(dom)
in end

(* ========== Delete book modal ========== *)

(* Remove the delete modal overlay from the DOM *)
implement dismiss_delete_modal() = let
  val overlay_id = _app_del_overlay_id()
in
  if gt_int_int(overlay_id, 0) then let
    val dom = ward_dom_init()
    val s = ward_dom_stream_begin(dom)
    val s = ward_dom_stream_remove_child(s, overlay_id)
    val dom = ward_dom_stream_end(s)
    val () = ward_dom_fini(dom)
    val () = _app_set_del_overlay_id(0)
  in end
  else ()
end

(* Step 1: Delete IDB data for a book.
 * Re-resolves book by stored book_id to prevent stale index.
 * Returns resolved_idx (plain int), negative if book already gone. *)
fn delete_book_idb
  (): int = let
  val resolved = library_find_book_by_id()
in
  if lt_g1(resolved, 0) then _g0(resolved) (* book already gone *)
  else let
    val bi0 = g1ofg0(_g0(resolved))
    val cnt = library_get_count()
    val ok = check_book_index(bi0, cnt)
  in
    if eq_g1(ok, 1) then let
      val (pf_ba | biv) = _mk_book_access(_g0(resolved))
      val _ = epub_set_book_id_from_library(pf_ba | biv)
      val sc0 = library_get_spine_count(_g0(resolved))
      val sc = (if lte_g1(sc0, 256) then sc0 else 256): int
      val () = epub_delete_book_data(_checked_spine_count(sc))
    in _g0(resolved) end
    else 0 - 1 (* bounds check failed *)
  end
end

(* Step 2: Remove book from library and save.
 * REQUIRES IDB data to have been deleted first (enforced by call order
 * in polling loop — compiler rejects constructing BOOK_DELETE_COMPLETE
 * without both IDB_DATA_DELETED and BOOK_REMOVED). *)
fn delete_book_from_lib
  (resolved_idx: int, root: int): void = let
  val () = library_remove_book(resolved_idx)
  val () = library_save()
  val () = render_library(root)
in end

(* Render delete confirmation modal and start polling loop *)
implement render_delete_modal(book_idx, root) = let
  (* Dismiss any existing delete modal *)
  val () = dismiss_delete_modal()

  (* Validate book_idx and store book_id for re-resolution at confirm time *)
  val bi0 = g1ofg0(book_idx)
  val cnt = library_get_count()
  val ok = check_book_index(bi0, cnt)
in
  if eq_g1(ok, 1) then let
    val (pf_ba | biv) = _mk_book_access(book_idx)
    val _ = epub_set_book_id_from_library(pf_ba | biv)

    (* Set choice to pending *)
    val () = _app_set_del_choice(0)

    (* Inject dup CSS — reuse same overlay/modal styling *)
    val () = inject_dup_css(root)

    val dom = ward_dom_init()
    val s = ward_dom_stream_begin(dom)

    (* Overlay *)
    val overlay_id = dom_next_id()
    val s = ward_dom_stream_create_element(s, overlay_id, root, tag_div(), 3)
    val s = ward_dom_stream_set_attr_safe(s, overlay_id, attr_class(), 5,
      cls_dup_overlay(), 11)
    val () = _app_set_del_overlay_id(overlay_id)

    (* Modal container *)
    val modal_id = dom_next_id()
    val s = ward_dom_stream_create_element(s, modal_id, overlay_id, tag_div(), 3)
    val s = ward_dom_stream_set_attr_safe(s, modal_id, attr_class(), 5,
      cls_dup_modal(), 9)

    (* Title: show book name *)
    val title_div_id = dom_next_id()
    val s = ward_dom_stream_create_element(s, title_div_id, modal_id, tag_div(), 3)
    val s = ward_dom_stream_set_attr_safe(s, title_div_id, attr_class(), 5,
      cls_dup_title(), 9)
    val title_len = library_get_title(book_idx, 0)
    val s = set_text_from_sbuf(s, title_div_id, title_len)

    (* Message: "Permanently delete?" *)
    val msg_id = dom_next_id()
    val s = ward_dom_stream_create_element(s, msg_id, modal_id, tag_div(), 3)
    val s = ward_dom_stream_set_attr_safe(s, msg_id, attr_class(), 5,
      cls_dup_msg(), 7)
    val s = set_text_cstr(VT_48() | s, msg_id, 48, 19)

    (* Actions container *)
    val actions_id = dom_next_id()
    val s = ward_dom_stream_create_element(s, actions_id, modal_id, tag_div(), 3)
    val s = ward_dom_stream_set_attr_safe(s, actions_id, attr_class(), 5,
      cls_dup_actions(), 11)

    (* Cancel button *)
    val cancel_btn_id = dom_next_id()
    val s = ward_dom_stream_create_element(s, cancel_btn_id, actions_id, tag_button(), 6)
    val s = ward_dom_stream_set_attr_safe(s, cancel_btn_id, attr_class(), 5,
      cls_dup_btn(), 7)
    val s = set_text_cstr(VT_35() | s, cancel_btn_id, 35, 6)

    (* Delete button — styled as danger/replace *)
    val delete_btn_id = dom_next_id()
    val s = ward_dom_stream_create_element(s, delete_btn_id, actions_id, tag_button(), 6)
    val s = ward_dom_stream_set_attr_safe(s, delete_btn_id, attr_class(), 5,
      cls_dup_replace(), 11)
    val s = set_text_cstr(VT_41() | s, delete_btn_id, 41, 6)

    val dom = ward_dom_stream_end(s)
    val () = ward_dom_fini(dom)

    (* Register Cancel click → choice=1 *)
    val () = ward_add_event_listener(
      cancel_btn_id, evt_click(), 5, LISTENER_DEL_CANCEL,
      lam (_pl: int): int => let
        val () = _app_set_del_choice(1)
      in 0 end
    )

    (* Register Delete click → choice=2 *)
    val () = ward_add_event_listener(
      delete_btn_id, evt_click(), 5, LISTENER_DEL_CONFIRM,
      lam (_pl: int): int => let
        val () = _app_set_del_choice(2)
      in 0 end
    )

    (* Polling loop: checks choice flag, executes delete once.
     * Termination metric .<k>. guarantees single execution and termination. *)
    val saved_root = root
    fun poll_del {k:nat} .<k>.
      (rem: int(k), sr: int): ward_promise_chained(int) = let
      val c = _app_del_choice()
    in
      if eq_int_int(c, 0) then
        (* Still pending — wait and retry *)
        if lte_g1(rem, 0) then let
          (* Timeout — dismiss silently *)
          val () = dismiss_delete_modal()
        in ward_promise_return<int>(0) end
        else
          ward_promise_then<int><int>(ward_timer_set(50),
            llam (_: int) => poll_del(sub_g1(rem, 1), sr))
      else if eq_int_int(c, 1) then let
        (* Cancel — dismiss *)
        val () = dismiss_delete_modal()
      in ward_promise_return<int>(0) end
      else let
        (* Confirm — delete *)
        val () = dismiss_delete_modal()
        val ri = delete_book_idb()
      in
        if gte_int_int(ri, 0) then let
          val () = delete_book_from_lib(ri, sr)
        in ward_promise_return<int>(0) end
        else
          (* Book already gone — nothing to do *)
          ward_promise_return<int>(0)
      end
    end
    val () = ward_promise_discard<int>(poll_del(_checked_nat(60000), saved_root))
  in end
  else () (* invalid book_idx — do nothing *)
end
