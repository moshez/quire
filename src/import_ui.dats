(* import_ui.dats — Import progress UI implementations *)

#define ATS_DYNLOADFLAG 0

#include "share/atspre_staload.hats"
staload "./quire.sats"
staload "./quire_ui.sats"
staload "./import_ui.sats"
staload "./quire_text.sats"
staload "./ui_classes.sats"
staload "./app_state.sats"
staload "./dom.sats"
staload "./arith.sats"
staload "./buf.sats"
staload "./quire_ext.sats"
staload "./../vendor/ward/lib/memory.sats"
staload "./../vendor/ward/lib/dom.sats"
staload "./../vendor/ward/lib/window.sats"
staload _ = "./../vendor/ward/lib/memory.dats"
staload _ = "./../vendor/ward/lib/dom.dats"
staload _ = "./../vendor/ward/lib/listener.dats"

(* Forward declaration for JS import — suppresses C99 warning *)
%{
extern void quireSetTitle(int mode);
%}

(* ========== Linear import outcome ========== *)

local
assume import_handled = int
in
implement import_mark_success() = 1
implement import_mark_failed{n}(msg, len) = let
  val () = ward_log(3, msg, len)
in 0 end
implement import_complete(h) = let
  val _ = h
  val () = ward_log(1, log_import_done(), 11)
in end
end

(* ========== CSS class builders ========== *)

implement cls_import_card() = let
  val b = ward_text_build(11)
  val b = ward_text_putc(b, 0, char2int1('i'))
  val b = ward_text_putc(b, 1, char2int1('m'))
  val b = ward_text_putc(b, 2, char2int1('p'))
  val b = ward_text_putc(b, 3, char2int1('o'))
  val b = ward_text_putc(b, 4, char2int1('r'))
  val b = ward_text_putc(b, 5, char2int1('t'))
  val b = ward_text_putc(b, 6, 45)  (* '-' *)
  val b = ward_text_putc(b, 7, char2int1('c'))
  val b = ward_text_putc(b, 8, char2int1('a'))
  val b = ward_text_putc(b, 9, char2int1('r'))
  val b = ward_text_putc(b, 10, char2int1('d'))
in ward_text_done(b) end

implement cls_import_bar() = let
  val b = ward_text_build(10)
  val b = ward_text_putc(b, 0, char2int1('i'))
  val b = ward_text_putc(b, 1, char2int1('m'))
  val b = ward_text_putc(b, 2, char2int1('p'))
  val b = ward_text_putc(b, 3, char2int1('o'))
  val b = ward_text_putc(b, 4, char2int1('r'))
  val b = ward_text_putc(b, 5, char2int1('t'))
  val b = ward_text_putc(b, 6, 45)  (* '-' *)
  val b = ward_text_putc(b, 7, char2int1('b'))
  val b = ward_text_putc(b, 8, char2int1('a'))
  val b = ward_text_putc(b, 9, char2int1('r'))
in ward_text_done(b) end

implement cls_import_fill() = let
  val b = ward_text_build(11)
  val b = ward_text_putc(b, 0, char2int1('i'))
  val b = ward_text_putc(b, 1, char2int1('m'))
  val b = ward_text_putc(b, 2, char2int1('p'))
  val b = ward_text_putc(b, 3, char2int1('o'))
  val b = ward_text_putc(b, 4, char2int1('r'))
  val b = ward_text_putc(b, 5, char2int1('t'))
  val b = ward_text_putc(b, 6, 45)  (* '-' *)
  val b = ward_text_putc(b, 7, char2int1('f'))
  val b = ward_text_putc(b, 8, char2int1('i'))
  val b = ward_text_putc(b, 9, char2int1('l'))
  val b = ward_text_putc(b, 10, char2int1('l'))
in ward_text_done(b) end

(* Import card CSS:
 * .library-list{display:flex;flex-direction:column}
 * .import-card{padding:12px 16px;border:1px solid #ddd;border-radius:4px;
 *   margin-bottom:8px;background:#f8f8f0;order:-1}
 * .import-bar{height:4px;background:#ddd;border-radius:2px;margin:8px 0}
 * .import-fill{height:4px;border-radius:2px;background:#5a8;transition:width .3s}
 *)
#define IMP_CARD_CSS_LEN 315

fn fill_css_import_card {l:agz}{n:int | n >= IMP_CARD_CSS_LEN}
  (arr: !ward_arr(byte, l, n), alen: int n): void = let
  val () = _w4(arr, alen, 0, 1651076142)
  val () = _w4(arr, alen, 4, 2037539186)
  val () = _w4(arr, alen, 8, 1936288813)
  val () = _w4(arr, alen, 12, 1768192884)
  val () = _w4(arr, alen, 16, 1634496627)
  val () = _w4(arr, alen, 20, 1818638969)
  val () = _w4(arr, alen, 24, 1715173477)
  val () = _w4(arr, alen, 28, 762865004)
  val () = _w4(arr, alen, 32, 1701996900)
  val () = _w4(arr, alen, 36, 1869182051)
  val () = _w4(arr, alen, 40, 1868773998)
  val () = _w4(arr, alen, 44, 1852667244)
  val () = _w4(arr, alen, 48, 1835609725)
  val () = _w4(arr, alen, 52, 1953656688)
  val () = _w4(arr, alen, 56, 1918985005)
  val () = _w4(arr, alen, 60, 1634761572)
  val () = _w4(arr, alen, 64, 1852400740)
  val () = _w4(arr, alen, 68, 842087015)
  val () = _w4(arr, alen, 72, 824211568)
  val () = _w4(arr, alen, 76, 997748790)
  val () = _w4(arr, alen, 80, 1685221218)
  val () = _w4(arr, alen, 84, 825913957)
  val () = _w4(arr, alen, 88, 1931507824)
  val () = _w4(arr, alen, 92, 1684630639)
  val () = _w4(arr, alen, 96, 1684284192)
  val () = _w4(arr, alen, 100, 1868708708)
  val () = _w4(arr, alen, 104, 1919247474)
  val () = _w4(arr, alen, 108, 1684107821)
  val () = _w4(arr, alen, 112, 980645225)
  val () = _w4(arr, alen, 116, 997748788)
  val () = _w4(arr, alen, 120, 1735549293)
  val () = _w4(arr, alen, 124, 1647144553)
  val () = _w4(arr, alen, 128, 1869902959)
  val () = _w4(arr, alen, 132, 1882733165)
  val () = _w4(arr, alen, 136, 1633827704)
  val () = _w4(arr, alen, 140, 1919380323)
  val () = _w4(arr, alen, 144, 1684960623)
  val () = _w4(arr, alen, 148, 946217786)
  val () = _w4(arr, alen, 152, 812005478)
  val () = _w4(arr, alen, 156, 1685221179)
  val () = _w4(arr, alen, 160, 758805093)
  val () = _w4(arr, alen, 164, 1764654385)
  val () = _w4(arr, alen, 168, 1919905901)
  val () = _w4(arr, alen, 172, 1633824116)
  val () = _w4(arr, alen, 176, 1701346162)
  val () = _w4(arr, alen, 180, 1952999273)
  val () = _w4(arr, alen, 184, 2020619322)
  val () = _w4(arr, alen, 188, 1667326523)
  val () = _w4(arr, alen, 192, 1869768555)
  val () = _w4(arr, alen, 196, 979660405)
  val () = _w4(arr, alen, 200, 1684300835)
  val () = _w4(arr, alen, 204, 1919902267)
  val () = _w4(arr, alen, 208, 762471780)
  val () = _w4(arr, alen, 212, 1768186226)
  val () = _w4(arr, alen, 216, 842691445)
  val () = _w4(arr, alen, 220, 1832614000)
  val () = _w4(arr, alen, 224, 1768387169)
  val () = _w4(arr, alen, 228, 1882733166)
  val () = _w4(arr, alen, 232, 2100306040)
  val () = _w4(arr, alen, 236, 1886218542)
  val () = _w4(arr, alen, 240, 762606191)
  val () = _w4(arr, alen, 244, 1819044198)
  val () = _w4(arr, alen, 248, 1768253563)
  val () = _w4(arr, alen, 252, 980707431)
  val () = _w4(arr, alen, 256, 997748788)
  val () = _w4(arr, alen, 260, 1685221218)
  val () = _w4(arr, alen, 264, 1915581029)
  val () = _w4(arr, alen, 268, 1969841249)
  val () = _w4(arr, alen, 272, 1882339955)
  val () = _w4(arr, alen, 276, 1633827704)
  val () = _w4(arr, alen, 280, 1919380323)
  val () = _w4(arr, alen, 284, 1684960623)
  val () = _w4(arr, alen, 288, 1630872378)
  val () = _w4(arr, alen, 292, 1920219960)
  val () = _w4(arr, alen, 296, 1769172577)
  val () = _w4(arr, alen, 300, 1852795252)
  val () = _w4(arr, alen, 304, 1684633402)
  val () = _w4(arr, alen, 308, 773875828)
  val () = ward_arr_set_byte(arr, 312, alen, 51)
  val () = ward_arr_set_byte(arr, 313, alen, 115)
  val () = ward_arr_set_byte(arr, 314, alen, 125)
in end

fn inject_import_card_css(parent: int): void = let
  val dom = ward_dom_init()
  val s = ward_dom_stream_begin(dom)
  val style_id = dom_next_id()
  val s = ward_dom_stream_create_element(s, style_id, parent, tag_style(), 5)
  val arr = ward_arr_alloc<byte>(IMP_CARD_CSS_LEN)
  val () = fill_css_import_card(arr, IMP_CARD_CSS_LEN)
  val @(frozen, borrow) = ward_arr_freeze<byte>(arr)
  val s = ward_dom_stream_set_text(s, style_id, borrow, IMP_CARD_CSS_LEN)
  val () = ward_arr_drop<byte>(frozen, borrow)
  val arr = ward_arr_thaw<byte>(frozen)
  val () = ward_arr_free<byte>(arr)
  val dom = ward_dom_stream_end(s)
  val () = ward_dom_fini(dom)
in end

(* Build style string "width:NN%" for progress bar.
 * All PROGRESS_PHASE percentages are 2-digit (10,30,60,90) -> always 9 bytes. *)
#define BAR_STYLE_LEN 9

fn build_bar_style {pct:nat | pct >= 10; pct <= 99}
  (pct: int(pct)): [l:agz] ward_arr(byte, l, BAR_STYLE_LEN) = let
  val arr = ward_arr_alloc<byte>(BAR_STYLE_LEN)
  (* "width:" = 6 bytes *)
  val () = ward_arr_set_byte(arr, 0, BAR_STYLE_LEN, 119)  (* w *)
  val () = ward_arr_set_byte(arr, 1, BAR_STYLE_LEN, 105)  (* i *)
  val () = ward_arr_set_byte(arr, 2, BAR_STYLE_LEN, 100)  (* d *)
  val () = ward_arr_set_byte(arr, 3, BAR_STYLE_LEN, 116)  (* t *)
  val () = ward_arr_set_byte(arr, 4, BAR_STYLE_LEN, 104)  (* h *)
  val () = ward_arr_set_byte(arr, 5, BAR_STYLE_LEN, 58)   (* : *)
  val tens = div_int_int(_g0(pct), 10)
  val ones = mod_int_int(_g0(pct), 10)
  val () = ward_arr_set_byte(arr, 6, BAR_STYLE_LEN, 48 + tens)
  val () = ward_arr_set_byte(arr, 7, BAR_STYLE_LEN, 48 + ones)
  val () = ward_arr_set_byte(arr, 8, BAR_STYLE_LEN, 37)   (* % *)
in arr end

(* ========== Import progress card ========== *)

implement render_import_card(list_id, root) = let
  (* Inject import card CSS *)
  val () = inject_import_card_css(root)

  val dom = ward_dom_init()
  val s = ward_dom_stream_begin(dom)

  (* Card container *)
  val card_id = dom_next_id()
  val s = ward_dom_stream_create_element(s, card_id, list_id, tag_div(), 3)
  val s = ward_dom_stream_set_attr_safe(s, card_id, attr_class(), 5,
    cls_import_card(), 11)

  (* Header: "Importing" (bold) *)
  val header_id = dom_next_id()
  val s = ward_dom_stream_create_element(s, header_id, card_id, tag_div(), 3)
  val fw_arr = ward_arr_alloc<byte>(16)
  val () = _w4(fw_arr, 16, 0, 1953394534)   (* font *)
  val () = _w4(fw_arr, 16, 4, 1768257325)   (* -wei *)
  val () = _w4(fw_arr, 16, 8, 980707431)    (* ght: *)
  val () = _w4(fw_arr, 16, 12, 1684828002)  (* bold *)
  val @(fw_frozen, fw_borrow) = ward_arr_freeze<byte>(fw_arr)
  val s = ward_dom_stream_set_style(s, header_id, fw_borrow, 16)
  val () = ward_arr_drop<byte>(fw_frozen, fw_borrow)
  val fw_arr = ward_arr_thaw<byte>(fw_frozen)
  val () = ward_arr_free<byte>(fw_arr)
  val s = set_text_cstr(VT_4() | s, header_id, 4, 9)

  (* Progress bar container *)
  val bar_wrap_id = dom_next_id()
  val s = ward_dom_stream_create_element(s, bar_wrap_id, card_id, tag_div(), 3)
  val s = ward_dom_stream_set_attr_safe(s, bar_wrap_id, attr_class(), 5,
    cls_import_bar(), 10)

  (* Progress fill element — starts at 10% *)
  val bar_id = dom_next_id()
  val s = ward_dom_stream_create_element(s, bar_id, bar_wrap_id, tag_div(), 3)
  val s = ward_dom_stream_set_attr_safe(s, bar_id, attr_class(), 5,
    cls_import_fill(), 11)
  val bar_arr = build_bar_style(10)
  val @(bar_frozen, bar_borrow) = ward_arr_freeze<byte>(bar_arr)
  val s = ward_dom_stream_set_style(s, bar_id, bar_borrow, BAR_STYLE_LEN)
  val () = ward_arr_drop<byte>(bar_frozen, bar_borrow)
  val bar_arr = ward_arr_thaw<byte>(bar_frozen)
  val () = ward_arr_free<byte>(bar_arr)

  (* Status text: "Opening file" *)
  val status_id = dom_next_id()
  val s = ward_dom_stream_create_element(s, status_id, card_id, tag_div(), 3)
  val s = set_text_cstr(VT_5() | s, status_id, 5, 12)

  val dom = ward_dom_stream_end(s)
  val () = ward_dom_fini(dom)

  (* Store IDs in app_state *)
  val () = _app_set_import_card_id(_g0(card_id))
  val () = _app_set_import_card_bar_id(_g0(bar_id))
  val () = _app_set_import_card_status_id(_g0(status_id))

  prval pf_idp0 = IDP_OPEN()
in (pf_idp0 | card_id, bar_id, status_id) end

(* update_import_bar: updates progress bar fill width.
 * Takes PROGRESS_PHASE as borrowed proof to enforce bar_pct correctness. *)
implement update_import_bar
  {ph}{pct}{tid}{tl}
  (pf | bar_id, bar_pct) = let
  val style_arr = build_bar_style(bar_pct)
  val @(sf, sb) = ward_arr_freeze<byte>(style_arr)
  val dom = ward_dom_init()
  val s = ward_dom_stream_begin(dom)
  val s = ward_dom_stream_set_style(s, bar_id, sb, BAR_STYLE_LEN)
  val dom = ward_dom_stream_end(s)
  val () = ward_dom_fini(dom)
  val () = ward_arr_drop<byte>(sf, sb)
  val sa = ward_arr_thaw<byte>(sf)
  val () = ward_arr_free<byte>(sa)
in end

(* remove_import_card: removes card from DOM. Requires terminal proof. *)
implement remove_import_card
  {c}
  (pf_term | card_id) = let
  prval _ = pf_term
  val dom = ward_dom_init()
  val s = ward_dom_stream_begin(dom)
  val s = ward_dom_stream_remove_child(s, card_id)
  val dom = ward_dom_stream_end(s)
  val () = ward_dom_fini(dom)
  val () = _app_set_import_card_id(0)
  val () = _app_set_import_card_bar_id(0)
  val () = _app_set_import_card_status_id(0)
in end

(* clear_node: remove all children of a DOM node *)
fn clear_node(nid: int): void = let
  val dom = ward_dom_init()
  val s = ward_dom_stream_begin(dom)
  val s = ward_dom_stream_remove_children(s, nid)
  val dom = ward_dom_stream_end(s)
  val () = ward_dom_fini(dom)
in end

(* import_finish: consumes linear import_handled token, restores UI, logs "import-done".
 * Called from each branch of the import outcome — token never crosses if-then-else. *)
implement import_finish(h, label_id, span_id, status_id) = let
  val () = quire_set_title(0)
  val () = update_import_label_class(label_id, 0)
  (* Restore span text to "Import" *)
  val import_st2 = let
    val b = ward_text_build(6)
    val b = ward_text_putc(b, 0, 73) (* 'I' *)
    val b = ward_text_putc(b, 1, char2int1('m'))
    val b = ward_text_putc(b, 2, char2int1('p'))
    val b = ward_text_putc(b, 3, char2int1('o'))
    val b = ward_text_putc(b, 4, char2int1('r'))
    val b = ward_text_putc(b, 5, char2int1('t'))
  in ward_text_done(b) end
  val dom2 = ward_dom_init()
  val s2 = ward_dom_stream_begin(dom2)
  val s2 = ward_dom_stream_set_safe_text(s2, span_id, import_st2, 6)
  val dom2 = ward_dom_stream_end(s2)
  val () = ward_dom_fini(dom2)
  val () = clear_node(status_id)
  val () = import_complete(h)
in end

(* import_finish_with_card: removes import card then does standard import_finish cleanup. *)
implement import_finish_with_card
  {c}
  (pf_term |
   h, card_id, label_id, span_id, status_id) = let
  val () = remove_import_card(pf_term | card_id)
in import_finish(h, label_id, span_id, status_id) end

(* ========== Import progress DOM update helpers ========== *)

(* Update a node's text content from a fill_text constant.
 * Opens/closes its own DOM stream — safe to call from promise callbacks. *)
implement update_status_text {tid}{tl}
  (pf | nid, text_id, text_len) = let
  val dom = ward_dom_init()
  val s = ward_dom_stream_begin(dom)
  val s = set_text_cstr(pf | s, nid, text_id, text_len)
  val dom = ward_dom_stream_end(s)
  val () = ward_dom_fini(dom)
in end

(* Set CSS class on import label: 1=importing, 0=import-btn *)
implement update_import_label_class(label_id, importing) = let
  val dom = ward_dom_init()
  val s = ward_dom_stream_begin(dom)
in
  if gt_int_int(importing, 0) then let
    val s = ward_dom_stream_set_attr_safe(s, label_id, attr_class(), 5,
      cls_importing(), 9)
    val dom = ward_dom_stream_end(s)
    val () = ward_dom_fini(dom)
  in end
  else let
    val s = ward_dom_stream_set_attr_safe(s, label_id, attr_class(), 5,
      cls_import_btn(), 10)
    val dom = ward_dom_stream_end(s)
    val () = ward_dom_fini(dom)
  in end
end
