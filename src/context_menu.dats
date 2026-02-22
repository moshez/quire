(* context_menu.dats — Context menu implementation *)

#define ATS_DYNLOADFLAG 0

#include "share/atspre_staload.hats"
staload "./quire.sats"
staload "./quire_ui.sats"
staload "./context_menu.sats"
staload "./quire_text.sats"
staload "./ui_classes.sats"
staload "./app_state.sats"
staload "./dom.sats"
staload "./arith.sats"
staload "./library.sats"
staload "./epub.sats"
staload "./reader.sats"
staload "./../vendor/ward/lib/memory.sats"
staload "./../vendor/ward/lib/dom.sats"
staload "./../vendor/ward/lib/listener.sats"
staload "./../vendor/ward/lib/event.sats"
staload _ = "./../vendor/ward/lib/memory.dats"
staload _ = "./../vendor/ward/lib/dom.dats"
staload _ = "./../vendor/ward/lib/listener.dats"
staload _ = "./../vendor/ward/lib/event.dats"

(* ========== CSS class builders ========== *)

implement cls_ctx_overlay() = let
  val b = ward_text_build(11)
  val b = ward_text_putc(b, 0, char2int1('c'))
  val b = ward_text_putc(b, 1, char2int1('t'))
  val b = ward_text_putc(b, 2, char2int1('x'))
  val b = ward_text_putc(b, 3, 45) (* '-' *)
  val b = ward_text_putc(b, 4, char2int1('o'))
  val b = ward_text_putc(b, 5, char2int1('v'))
  val b = ward_text_putc(b, 6, char2int1('e'))
  val b = ward_text_putc(b, 7, char2int1('r'))
  val b = ward_text_putc(b, 8, char2int1('l'))
  val b = ward_text_putc(b, 9, char2int1('a'))
  val b = ward_text_putc(b, 10, char2int1('y'))
in ward_text_done(b) end

implement cls_ctx_menu() = let
  val b = ward_text_build(8)
  val b = ward_text_putc(b, 0, char2int1('c'))
  val b = ward_text_putc(b, 1, char2int1('t'))
  val b = ward_text_putc(b, 2, char2int1('x'))
  val b = ward_text_putc(b, 3, 45) (* '-' *)
  val b = ward_text_putc(b, 4, char2int1('m'))
  val b = ward_text_putc(b, 5, char2int1('e'))
  val b = ward_text_putc(b, 6, char2int1('n'))
  val b = ward_text_putc(b, 7, char2int1('u'))
in ward_text_done(b) end

implement cls_ctx_item() = let
  val b = ward_text_build(8)
  val b = ward_text_putc(b, 0, char2int1('c'))
  val b = ward_text_putc(b, 1, char2int1('t'))
  val b = ward_text_putc(b, 2, char2int1('x'))
  val b = ward_text_putc(b, 3, 45) (* '-' *)
  val b = ward_text_putc(b, 4, char2int1('i'))
  val b = ward_text_putc(b, 5, char2int1('t'))
  val b = ward_text_putc(b, 6, char2int1('e'))
  val b = ward_text_putc(b, 7, char2int1('m'))
in ward_text_done(b) end

implement cls_ctx_danger() = let
  val b = ward_text_build(10)
  val b = ward_text_putc(b, 0, char2int1('c'))
  val b = ward_text_putc(b, 1, char2int1('t'))
  val b = ward_text_putc(b, 2, char2int1('x'))
  val b = ward_text_putc(b, 3, 45) (* '-' *)
  val b = ward_text_putc(b, 4, char2int1('d'))
  val b = ward_text_putc(b, 5, char2int1('a'))
  val b = ward_text_putc(b, 6, char2int1('n'))
  val b = ward_text_putc(b, 7, char2int1('g'))
  val b = ward_text_putc(b, 8, char2int1('e'))
  val b = ward_text_putc(b, 9, char2int1('r'))
in ward_text_done(b) end

(* ========== Context menu CSS + rendering ========== *)

(* Context menu CSS:
 * .ctx-overlay{position:fixed;inset:0;z-index:999}
 * .ctx-menu{position:fixed;top:50%;left:50%;transform:translate(-50%,-50%);
 *   background:#fff;border-radius:8px;box-shadow:0 2px 12px #0003;
 *   min-width:180px;z-index:1000;padding:4px 0}
 * .ctx-item{display:block;width:100%;padding:10px 16px;border:none;
 *   background:none;text-align:left;cursor:pointer}
 * .ctx-item:hover{background:#f0f0f0}
 * .ctx-danger{color:#c22}
 *)
#define CTX_CSS_LEN 396

fn fill_css_ctx {l:agz}{n:int | n >= CTX_CSS_LEN}
  (arr: !ward_arr(byte, l, n), alen: int n): void = let
  val () = _w4(arr, alen, 0, 2020893486)       (* .ctx *)
  val () = _w4(arr, alen, 4, 1702260525)       (* -ove *)
  val () = _w4(arr, alen, 8, 2036427890)       (* rlay *)
  val () = _w4(arr, alen, 12, 1936683131)       (* {pos *)
  val () = _w4(arr, alen, 16, 1869182057)       (* itio *)
  val () = _w4(arr, alen, 20, 1768307310)       (* n:fi *)
  val () = _w4(arr, alen, 24, 996435320)       (* xed; *)
  val () = _w4(arr, alen, 28, 1702063721)       (* inse *)
  val () = _w4(arr, alen, 32, 993016436)       (* t:0; *)
  val () = _w4(arr, alen, 36, 1852386682)       (* z-in *)
  val () = _w4(arr, alen, 40, 980968804)       (* dex: *)
  val () = _w4(arr, alen, 44, 2100902201)       (* 999} *)
  val () = _w4(arr, alen, 48, 2020893486)       (* .ctx *)
  val () = _w4(arr, alen, 52, 1852140845)       (* -men *)
  val () = _w4(arr, alen, 56, 1869642613)       (* u{po *)
  val () = _w4(arr, alen, 60, 1769236851)       (* siti *)
  val () = _w4(arr, alen, 64, 1715105391)       (* on:f *)
  val () = _w4(arr, alen, 68, 1684371561)       (* ixed *)
  val () = _w4(arr, alen, 72, 1886352443)       (* ;top *)
  val () = _w4(arr, alen, 76, 623916346)       (* :50% *)
  val () = _w4(arr, alen, 80, 1717922875)       (* ;lef *)
  val () = _w4(arr, alen, 84, 808794740)       (* t:50 *)
  val () = _w4(arr, alen, 88, 1920219941)       (* %;tr *)
  val () = _w4(arr, alen, 92, 1718840929)       (* ansf *)
  val () = _w4(arr, alen, 96, 980251247)       (* orm: *)
  val () = _w4(arr, alen, 100, 1851880052)       (* tran *)
  val () = _w4(arr, alen, 104, 1952541811)       (* slat *)
  val () = _w4(arr, alen, 108, 892151909)       (* e(-5 *)
  val () = _w4(arr, alen, 112, 757867824)       (* 0%,- *)
  val () = _w4(arr, alen, 116, 690303029)       (* 50%) *)
  val () = _w4(arr, alen, 120, 1667326523)       (* ;bac *)
  val () = _w4(arr, alen, 124, 1869768555)       (* kgro *)
  val () = _w4(arr, alen, 128, 979660405)       (* und: *)
  val () = _w4(arr, alen, 132, 1717986851)       (* #fff *)
  val () = _w4(arr, alen, 136, 1919902267)       (* ;bor *)
  val () = _w4(arr, alen, 140, 762471780)       (* der- *)
  val () = _w4(arr, alen, 144, 1768186226)       (* radi *)
  val () = _w4(arr, alen, 148, 943354741)       (* us:8 *)
  val () = _w4(arr, alen, 152, 1648064624)       (* px;b *)
  val () = _w4(arr, alen, 156, 1932359791)       (* ox-s *)
  val () = _w4(arr, alen, 160, 1868849512)       (* hado *)
  val () = _w4(arr, alen, 164, 540031607)       (* w:0  *)
  val () = _w4(arr, alen, 168, 544763954)       (* 2px  *)
  val () = _w4(arr, alen, 172, 2020618801)       (* 12px *)
  val () = _w4(arr, alen, 176, 808461088)       (*  #00 *)
  val () = _w4(arr, alen, 180, 1832596272)       (* 03;m *)
  val () = _w4(arr, alen, 184, 1999466089)       (* in-w *)
  val () = _w4(arr, alen, 188, 1752458345)       (* idth *)
  val () = _w4(arr, alen, 192, 808988986)       (* :180 *)
  val () = _w4(arr, alen, 196, 2050717808)       (* px;z *)
  val () = _w4(arr, alen, 200, 1684957485)       (* -ind *)
  val () = _w4(arr, alen, 204, 825915493)       (* ex:1 *)
  val () = _w4(arr, alen, 208, 993013808)       (* 000; *)
  val () = _w4(arr, alen, 212, 1684300144)       (* padd *)
  val () = _w4(arr, alen, 216, 979857001)       (* ing: *)
  val () = _w4(arr, alen, 220, 544763956)       (* 4px  *)
  val () = _w4(arr, alen, 224, 1663991088)       (* 0}.c *)
  val () = _w4(arr, alen, 228, 1764587636)       (* tx-i *)
  val () = _w4(arr, alen, 232, 2070766964)       (* tem{ *)
  val () = _w4(arr, alen, 236, 1886611812)       (* disp *)
  val () = _w4(arr, alen, 240, 981033324)       (* lay: *)
  val () = _w4(arr, alen, 244, 1668246626)       (* bloc *)
  val () = _w4(arr, alen, 248, 1769421675)       (* k;wi *)
  val () = _w4(arr, alen, 252, 979924068)       (* dth: *)
  val () = _w4(arr, alen, 256, 623915057)       (* 100% *)
  val () = _w4(arr, alen, 260, 1684107323)       (* ;pad *)
  val () = _w4(arr, alen, 264, 1735289188)       (* ding *)
  val () = _w4(arr, alen, 268, 1882206522)       (* :10p *)
  val () = _w4(arr, alen, 272, 909189240)       (* x 16 *)
  val () = _w4(arr, alen, 276, 1648064624)       (* px;b *)
  val () = _w4(arr, alen, 280, 1701081711)       (* orde *)
  val () = _w4(arr, alen, 284, 1869494898)       (* r:no *)
  val () = _w4(arr, alen, 288, 1648059758)       (* ne;b *)
  val () = _w4(arr, alen, 292, 1735091041)       (* ackg *)
  val () = _w4(arr, alen, 296, 1853190002)       (* roun *)
  val () = _w4(arr, alen, 300, 1869494884)       (* d:no *)
  val () = _w4(arr, alen, 304, 1950049646)       (* ne;t *)
  val () = _w4(arr, alen, 308, 762607717)       (* ext- *)
  val () = _w4(arr, alen, 312, 1734962273)       (* alig *)
  val () = _w4(arr, alen, 316, 1701591662)       (* n:le *)
  val () = _w4(arr, alen, 320, 1664840806)       (* ft;c *)
  val () = _w4(arr, alen, 324, 1869836917)       (* urso *)
  val () = _w4(arr, alen, 328, 1869625970)       (* r:po *)
  val () = _w4(arr, alen, 332, 1702129257)       (* inte *)
  val () = _w4(arr, alen, 336, 1663991154)       (* r}.c *)
  val () = _w4(arr, alen, 340, 1764587636)       (* tx-i *)
  val () = _w4(arr, alen, 344, 980247924)       (* tem: *)
  val () = _w4(arr, alen, 348, 1702260584)       (* hove *)
  val () = _w4(arr, alen, 352, 1633844082)       (* r{ba *)
  val () = _w4(arr, alen, 356, 1919380323)       (* ckgr *)
  val () = _w4(arr, alen, 360, 1684960623)       (* ound *)
  val () = _w4(arr, alen, 364, 812000058)       (* :#f0 *)
  val () = _w4(arr, alen, 368, 812003430)       (* f0f0 *)
  val () = _w4(arr, alen, 372, 1952657021)       (* }.ct *)
  val () = _w4(arr, alen, 376, 1633955192)       (* x-da *)
  val () = _w4(arr, alen, 380, 1919248238)       (* nger *)
  val () = _w4(arr, alen, 384, 1819239291)       (* {col *)
  val () = _w4(arr, alen, 388, 591032943)       (* or:# *)
  val () = _w4(arr, alen, 392, 2100441699)       (* c22} *)
in end

fn inject_ctx_css(parent: int): void = let
  val ctx_arr = ward_arr_alloc<byte>(CTX_CSS_LEN)
  val () = fill_css_ctx(ctx_arr, CTX_CSS_LEN)
  val style_id = dom_next_id()
  val dom = ward_dom_init()
  val s = ward_dom_stream_begin(dom)
  val s = ward_dom_stream_create_element(s, style_id, parent, tag_style(), 5)
  val @(frozen, borrow) = ward_arr_freeze<byte>(ctx_arr)
  val s = ward_dom_stream_set_text(s, style_id, borrow, CTX_CSS_LEN)
  val () = ward_arr_drop<byte>(frozen, borrow)
  val ctx_arr = ward_arr_thaw<byte>(frozen)
  val () = ward_arr_free<byte>(ctx_arr)
  val dom = ward_dom_stream_end(s)
  val () = ward_dom_fini(dom)
in end

(* ========== dismiss_context_menu ========== *)

implement dismiss_context_menu() = let
  val overlay_id = _app_ctx_overlay_id()
in
  if gt_int_int(overlay_id, 0) then let
    val dom = ward_dom_init()
    val s = ward_dom_stream_begin(dom)
    val s = ward_dom_stream_remove_child(s, overlay_id)
    val dom = ward_dom_stream_end(s)
    val () = ward_dom_fini(dom)
    val () = _app_set_ctx_overlay_id(0)
  in end
  else ()
end

(* ========== Context menu helpers ========== *)

extern castfn _mk_book_access(x: int): [i:nat | i < 32] (BOOK_ACCESS_SAFE(i) | int(i))

extern castfn _checked_spine_count(x: int): [n:nat | n <= 256] int n

fn _ctx_add_hide_item {l:agz}
  (s: ward_dom_stream(l), menu_id: int, btn_id: int, vm: int)
  : ward_dom_stream(l) = let
  val s = ward_dom_stream_create_element(s, btn_id, menu_id, tag_button(), 6)
  val s = ward_dom_stream_set_attr_safe(s, btn_id, attr_class(), 5, cls_ctx_item(), 8)
in
  if eq_int_int(vm, 0) then
    set_text_cstr(VT_27() | s, btn_id, 27, 4)    (* "Hide" *)
  else
    set_text_cstr(VT_28() | s, btn_id, 28, 6)    (* "Unhide" *)
end

(* Helper: add archive/unarchive menu item.
 * Separate fn avoids viewtype-in-if-then-else issue. *)
fn _ctx_add_arch_item {l:agz}
  (s: ward_dom_stream(l), menu_id: int, btn_id: int, vm: int)
  : ward_dom_stream(l) = let
  val s = ward_dom_stream_create_element(s, btn_id, menu_id, tag_button(), 6)
  val s = ward_dom_stream_set_attr_safe(s, btn_id, attr_class(), 5, cls_ctx_item(), 8)
in
  if eq_int_int(vm, 0) then
    set_text_cstr(VT_20() | s, btn_id, 20, 7)    (* "Archive" *)
  else
    set_text_cstr(VT_21() | s, btn_id, 21, 7)    (* "Restore" *)
end

(* Helper: conditionally add hide item to context menu *)
fn _ctx_maybe_hide {l:agz}
  (s: ward_dom_stream(l), show_hide: int, menu_id: int, btn_id: int, vm: int)
  : ward_dom_stream(l) =
  if eq_int_int(show_hide, 1) then _ctx_add_hide_item(s, menu_id, btn_id, vm)
  else s

(* Helper: conditionally add archive item to context menu *)
fn _ctx_maybe_arch {l:agz}
  (s: ward_dom_stream(l), show_archive: int, menu_id: int, btn_id: int, vm: int)
  : ward_dom_stream(l) =
  if eq_int_int(show_archive, 1) then _ctx_add_arch_item(s, menu_id, btn_id, vm)
  else s

(* ========== show_context_menu ========== *)

implement show_context_menu {vm,ss,sh,sa}
  (pf | book_idx, root_id, vm,
   show_hide, show_archive) = let
  (* Dismiss existing menu if open *)
  val () = dismiss_context_menu()

  (* Inject CSS — use root_id (node 0) as parent, not stale node 1 *)
  val () = inject_ctx_css(root_id)

  (* Build menu DOM *)
  val dom = ward_dom_init()
  val s = ward_dom_stream_begin(dom)

  (* Overlay — catches outside clicks for dismiss *)
  val overlay_id = dom_next_id()
  val s = ward_dom_stream_create_element(s, overlay_id, root_id, tag_div(), 3)
  val s = ward_dom_stream_set_attr_safe(s, overlay_id, attr_class(), 5, cls_ctx_overlay(), 11)
  val () = _app_set_ctx_overlay_id(overlay_id)

  (* Menu container *)
  val menu_id = dom_next_id()
  val s = ward_dom_stream_create_element(s, menu_id, overlay_id, tag_div(), 3)
  val s = ward_dom_stream_set_attr_safe(s, menu_id, attr_class(), 5, cls_ctx_menu(), 8)

  (* "Book info" item *)
  val info_btn_id = dom_next_id()
  val s = ward_dom_stream_create_element(s, info_btn_id, menu_id, tag_button(), 6)
  val s = ward_dom_stream_set_attr_safe(s, info_btn_id, attr_class(), 5, cls_ctx_item(), 8)
  val s = set_text_cstr(VT_40() | s, info_btn_id, 40, 9)

  (* Hide/Unhide item — conditional on show_hide *)
  val hide_btn_id = dom_next_id()
  val s = _ctx_maybe_hide(s, show_hide, menu_id, hide_btn_id, vm)

  (* Archive/Unarchive item — conditional on show_archive *)
  val arch_btn_id = dom_next_id()
  val s = _ctx_maybe_arch(s, show_archive, menu_id, arch_btn_id, vm)

  (* "Delete" item — always shown, styled as danger *)
  val del_btn_id = dom_next_id()
  val s = ward_dom_stream_create_element(s, del_btn_id, menu_id, tag_button(), 6)
  val s = ward_dom_stream_set_attr_safe(s, del_btn_id, attr_class(), 5, cls_ctx_danger(), 10)
  val s = set_text_cstr(VT_41() | s, del_btn_id, 41, 6)

  val dom = ward_dom_stream_end(s)
  val () = ward_dom_fini(dom)

  (* Register dismiss listener on overlay *)
  val () = ward_add_event_listener(
    overlay_id, evt_click(), 5, LISTENER_CTX_DISMISS,
    lam (_pl: int): int => let
      val () = dismiss_context_menu()
    in 0 end
  )

  (* Closures capture book_idx, root_id, vm for menu item handlers *)
  val saved_bi = book_idx
  val saved_root = root_id
  val saved_vm = vm
  val saved_sh = show_hide
  val saved_sa = show_archive

  (* Register "Book info" handler — opens info overlay *)
  val () = ward_add_event_listener(
    info_btn_id, evt_click(), 5, LISTENER_CTX_INFO,
    lam (_pl: int): int => let
      val () = dismiss_context_menu()
    in
      if eq_int_int(saved_vm, 0) then let
        val () = show_book_info(INFO_BTN_ACTIVE() | saved_bi, saved_root, 0, 1, 1)
      in 0 end
      else if eq_int_int(saved_vm, 1) then let
        val () = show_book_info(INFO_BTN_ARCHIVED() | saved_bi, saved_root, 1, 0, 1)
      in 0 end
      else let
        val () = show_book_info(INFO_BTN_HIDDEN() | saved_bi, saved_root, 2, 1, 0)
      in 0 end
    end
  )

  (* Register hide/unhide handler — closures capture book_idx *)
  val () =
    if eq_int_int(saved_sh, 1) then
      ward_add_event_listener(
        hide_btn_id, evt_click(), 5, LISTENER_CTX_HIDE,
        lam (_pl: int): int => let
          val () = dismiss_context_menu()
        in
          if eq_int_int(saved_vm, 0) then let
            (* Hide: set shelf_state=2 *)
            val () = library_set_shelf_state(SHELF_HIDDEN() | saved_bi, 2)
            val () = library_save()
            val () = render_library(saved_root)
          in 0 end
          else let
            (* Unhide: set shelf_state=0 *)
            val () = library_set_shelf_state(SHELF_ACTIVE() | saved_bi, 0)
            val () = library_save()
            val () = render_library(saved_root)
          in 0 end
        end
      )
    else ()

  (* Register archive/unarchive handler *)
  val () =
    if eq_int_int(saved_sa, 1) then
      ward_add_event_listener(
        arch_btn_id, evt_click(), 5, LISTENER_CTX_ARCHIVE,
        lam (_pl: int): int => let
          val () = dismiss_context_menu()
        in
          if eq_int_int(saved_vm, 0) then let
            (* Archive: set shelf_state=1 and delete IDB content *)
            val () = library_set_shelf_state(SHELF_ARCHIVED() | saved_bi, 1)
            val bi0 = g1ofg0(saved_bi)
            val cnt = library_get_count()
            val ok = check_book_index(bi0, cnt)
            val () = if eq_g1(ok, 1) then let
              val (pf_ba | biv) = _mk_book_access(saved_bi)
              val _ = epub_set_book_id_from_library(pf_ba | biv)
              val sc0 = library_get_spine_count(saved_bi)
              val sc = (if lte_g1(sc0, 256) then sc0 else 256): int
              val () = epub_delete_book_data(_checked_spine_count(sc))
            in end
            val () = library_save()
            val () = render_library(saved_root)
          in 0 end
          else let
            (* Restore: set shelf_state=0 *)
            val () = library_set_shelf_state(SHELF_ACTIVE() | saved_bi, 0)
            val () = library_save()
            val () = render_library(saved_root)
          in 0 end
        end
      )
    else ()

  (* Register "Delete" handler — opens delete confirmation modal *)
  val () = ward_add_event_listener(
    del_btn_id, evt_click(), 5, LISTENER_CTX_DELETE,
    lam (_pl: int): int => let
      val () = dismiss_context_menu()
      val () = render_delete_modal(saved_bi, saved_root)
    in 0 end
  )
in end
