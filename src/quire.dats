(* quire.dats — Quire application: reader view and entry point.
 *
 * Library view: moved to library_view.dats
 * Reader view: loads chapter from ZIP, decompresses, parses HTML, renders.
 * Navigation: click zones and keyboard (ArrowRight/Left, Space, Escape).
 *)

#define ATS_DYNLOADFLAG 0

#include "share/atspre_staload.hats"
staload "./quire.sats"
staload "./quire_ui.sats"
staload "./quire_text.sats"
staload "./ui_classes.sats"
staload "./quire_css.sats"
staload "./book_info.sats"
staload "./context_menu.sats"
staload "./modals.sats"
staload "./import_ui.sats"
staload "./library_view.sats"
staload "./app_state.sats"
staload "./dom.sats"
staload "./zip.sats"
staload "./epub.sats"
staload "./library.sats"
staload "./reader.sats"
staload "./../vendor/ward/lib/memory.sats"
staload "./../vendor/ward/lib/dom.sats"
staload "./../vendor/ward/lib/listener.sats"
staload "./../vendor/ward/lib/file.sats"
staload "./../vendor/ward/lib/promise.sats"
staload "./../vendor/ward/lib/event.sats"
staload "./../vendor/ward/lib/decompress.sats"
staload "./../vendor/ward/lib/xml.sats"
staload "./../vendor/ward/lib/dom_read.sats"
staload "./../vendor/ward/lib/window.sats"
staload "./../vendor/ward/lib/idb.sats"
staload _ = "./../vendor/ward/lib/memory.dats"
staload _ = "./../vendor/ward/lib/dom.dats"
staload _ = "./../vendor/ward/lib/listener.dats"
staload _ = "./../vendor/ward/lib/file.dats"
staload _ = "./../vendor/ward/lib/promise.dats"
staload _ = "./../vendor/ward/lib/event.dats"
staload _ = "./../vendor/ward/lib/decompress.dats"
staload _ = "./../vendor/ward/lib/xml.dats"
staload _ = "./../vendor/ward/lib/dom_read.dats"
staload _ = "./../vendor/ward/lib/idb.dats"

staload "./arith.sats"
staload "./sha256.sats"
staload "./quire_ext.sats"
staload "./buf.sats"
staload "./settings.sats"

(* Forward declarations for JS imports — suppresses C99 warnings *)
%{
extern int quire_time_now(void);
%}

(* ========== Position persistence proof ========== *)
(* POSITION_PERSISTED proves library_update_position + library_save
 * were called. Required by page_turn_forward/backward and chapter
 * transitions — ensures position is saved on every navigation. *)
dataprop POSITION_PERSISTED() = | POS_PERSISTED()

(* ========== Listener ID constants ========== *)

(* Named listener IDs — single source of truth.
 * Dataprop enum prevents arbitrary IDs in reader event listeners. *)
dataprop READER_LISTENER(id: int) =
  | READER_LISTEN_KEYDOWN(50)
  | READER_LISTEN_VIEWPORT_CLICK(51)
  | READER_LISTEN_BACK(52)
  | READER_LISTEN_PREV(53)
  | READER_LISTEN_NEXT(54)

#define LISTENER_KEYDOWN 50
#define LISTENER_VIEWPORT_CLICK 51
#define LISTENER_BACK 52
#define LISTENER_PREV 53
#define LISTENER_NEXT 54

(* ========== Measurement correctness ========== *)

(* SCROLL_WIDTH_SLOT: proves that scrollWidth lives in ward measurement slot 4.
 * ward_measure_get_top() reads slot 4 = el.scrollWidth.
 * ward_measure_get_left() reads slot 5 = el.scrollHeight.
 * The names are confusing — this dataprop ensures quire code uses the correct slot.
 *
 * BUG PREVENTED: measure_and_set_pages used ward_measure_get_left (scrollHeight)
 * instead of ward_measure_get_top (scrollWidth), giving total_pages=1 always. *)
dataprop SCROLL_WIDTH_SLOT(slot: int) =
  | SLOT_4(4)

(* Safe wrapper: measures a node and returns its scrollWidth.
 * Abstracts over ward's confusing slot naming.
 * Constructs SCROLL_WIDTH_SLOT(4) proof to document correctness. *)
fn measure_node_scroll_width(node_id: int): int = let
  val _found = ward_measure_node(node_id)
  prval _ = SLOT_4()  (* proof: we read slot 4 = scrollWidth *)
in
  ward_measure_get_top()  (* slot 4 = el.scrollWidth *)
end

(* Safe wrapper: measures a node and returns its element width.
 * Uses slot 2 = el.width from getBoundingClientRect. *)
fn measure_node_width(node_id: int): int = let
  val _found = ward_measure_node(node_id)
in
  ward_measure_get_w()  (* slot 2 = rect.width *)
end

(* Castfn for indices proven in-bounds at runtime but not by solver.
 * Used for ward_arr(byte, l, 48) where max write index is 35. *)
extern castfn _idx48(x: int): [i:nat | i < 48] int i

(* Proof construction after runtime validation via check_book_index.
 * The caller MUST verify check_book_index(idx, count) == 1 before calling.
 * Dataprop erased at runtime — cast is identity on int. *)
extern castfn _mk_book_access(x: int): [i:nat | i < 32] (BOOK_ACCESS_SAFE(i) | int(i))

(* Clamp spine count to [0, 256] for epub_delete_book_data.
 * Caller MUST verify value <= 256 before calling. *)
extern castfn _checked_spine_count(x: int): [n:nat | n <= 256] int n

(* Safe byte conversion: value must be 0-255.
 * For static chars: use char2int1('x') which carries the static value.
 * For computed digits: 48 + (v % 10) is always 48-57 — in range. *)
extern castfn _byte {c:int | 0 <= c; c <= 255} (c: int c): byte

(* ========== Chapter load error messages ========== *)

(* mk_ch_err builds "err-ch-XYZ" safe text where XYZ are the 3 suffix chars.
 * Used by load_chapter to log a specific error at each failure point. *)
fn mk_ch_err
  {c1:int | SAFE_CHAR(c1)}
  {c2:int | SAFE_CHAR(c2)}
  {c3:int | SAFE_CHAR(c3)}
  (c1: int(c1), c2: int(c2), c3: int(c3)): ward_safe_text(10) = let
  val b = ward_text_build(10)
  val b = ward_text_putc(b, 0, char2int1('e'))
  val b = ward_text_putc(b, 1, char2int1('r'))
  val b = ward_text_putc(b, 2, char2int1('r'))
  val b = ward_text_putc(b, 3, 45) (* '-' *)
  val b = ward_text_putc(b, 4, char2int1('c'))
  val b = ward_text_putc(b, 5, char2int1('h'))
  val b = ward_text_putc(b, 6, 45) (* '-' *)
  val b = ward_text_putc(b, 7, c1)
  val b = ward_text_putc(b, 8, c2)
  val b = ward_text_putc(b, 9, c3)
in ward_text_done(b) end

(* CHAPTER_DISPLAY_READY: proves that after chapter content is rendered,
 * both pagination measurement AND CSS transform application occurred.
 *
 * BUG PREVENTED: stale CSS transform from previous chapter leaving
 * first page of new chapter invisible. When navigating from Ch 2/3
 * page 11/11 (translateX=-10240px) to Ch 3/3 page 1/8, the old
 * transform persisted because apply_page_transform was only called
 * via apply_resume_page (which skips when resume_pg == 0).
 *
 * finish_chapter_load is the ONLY way to obtain this proof, and it
 * always calls apply_page_transform before apply_resume_page. *)
dataprop CHAPTER_DISPLAY_READY() =
  | MEASURED_AND_TRANSFORMED()

(* PAGE_DISPLAY_UPDATED: proves that after changing the page counter,
 * both the CSS transform AND the page indicator were updated.
 *
 * BUG CLASS PREVENTED: same as CHAPTER_DISPLAY_READY but for within-chapter
 * page turns. If someone adds a new page-changing path and calls
 * reader_next_page/reader_prev_page without applying the transform,
 * content becomes invisible. This proof forces the transform + page info
 * update to be bundled with every page counter change.
 *
 * page_turn_forward/page_turn_backward are the ONLY ways to obtain this proof. *)
dataprop PAGE_DISPLAY_UPDATED() =
  | PAGE_TURNED_AND_SHOWN()

(* ========== Page navigation helpers ========== *)

(* Write non-negative int as decimal digits into ward_arr at offset.
 * Returns number of digits written. Array must be >= 48 bytes.
 * Digit bytes are 48-57 ('0'-'9') — always valid for int2byte0.
 * NOTE: mod_int_int returns plain int so solver can't verify range;
 * the invariant 0 <= (v%10) <= 9 holds by definition of modulo. *)
fn itoa_to_arr {l:agz}
  (arr: !ward_arr(byte, l, 48), v: int, offset: int): int = let
  fun count_digits {k:nat} .<k>.
    (rem: int(k), x: int, acc: int): int =
    if lte_g1(rem, 0) then acc
    else if gt_int_int(x, 0) then count_digits(sub_g1(rem, 1), div_int_int(x, 10), acc + 1)
    else acc
in
  if gt_int_int(1, v) then let
    val () = ward_arr_set<byte>(arr, _idx48(offset),
      _byte(char2int1('0')))
  in 1 end
  else let
    val ndigits = count_digits(_checked_nat(11), v, 0)
    fun write_rev {l:agz}{k:nat} .<k>.
      (rem: int(k), arr: !ward_arr(byte, l, 48), x: int, pos: int): void =
      if lte_g1(rem, 0) then ()
      else if gt_int_int(x, 0) then let
        val digit = mod_int_int(x, 10)
        (* digit is 0-9, so 48+digit is 48-57 — within byte range *)
        val () = ward_arr_set<byte>(arr, _idx48(pos), ward_int2byte(_checked_byte(48 + digit)))
      in write_rev(sub_g1(rem, 1), arr, div_int_int(x, 10), pos - 1) end
      else ()
    val () = write_rev(_checked_nat(11), arr, v, offset + ndigits - 1)
  in ndigits end
end

(* Build "transform:translateX(-Npx)" in a ward_arr(48).
 * Returns total bytes written. Max: 22 prefix + 10 digits + 3 suffix = 35.
 * Static chars use char2int1 + _byte — constraint-solver verified. *)
fn build_transform_arr {l:agz}
  (arr: !ward_arr(byte, l, 48), page: int, page_width: int): int = let
  val pixel_offset = mul_int_int(page, page_width)
  (* "transform:translateX(-" — 22 bytes, all verified via char2int1 *)
  val () = ward_arr_set<byte>(arr, 0, _byte(char2int1('t')))
  val () = ward_arr_set<byte>(arr, 1, _byte(char2int1('r')))
  val () = ward_arr_set<byte>(arr, 2, _byte(char2int1('a')))
  val () = ward_arr_set<byte>(arr, 3, _byte(char2int1('n')))
  val () = ward_arr_set<byte>(arr, 4, _byte(char2int1('s')))
  val () = ward_arr_set<byte>(arr, 5, _byte(char2int1('f')))
  val () = ward_arr_set<byte>(arr, 6, _byte(char2int1('o')))
  val () = ward_arr_set<byte>(arr, 7, _byte(char2int1('r')))
  val () = ward_arr_set<byte>(arr, 8, _byte(char2int1('m')))
  val () = ward_arr_set<byte>(arr, 9, _byte(58))  (* ':' — char2int1 can't parse punctuation *)
  val () = ward_arr_set<byte>(arr, 10, _byte(char2int1('t')))
  val () = ward_arr_set<byte>(arr, 11, _byte(char2int1('r')))
  val () = ward_arr_set<byte>(arr, 12, _byte(char2int1('a')))
  val () = ward_arr_set<byte>(arr, 13, _byte(char2int1('n')))
  val () = ward_arr_set<byte>(arr, 14, _byte(char2int1('s')))
  val () = ward_arr_set<byte>(arr, 15, _byte(char2int1('l')))
  val () = ward_arr_set<byte>(arr, 16, _byte(char2int1('a')))
  val () = ward_arr_set<byte>(arr, 17, _byte(char2int1('t')))
  val () = ward_arr_set<byte>(arr, 18, _byte(char2int1('e')))
  val () = ward_arr_set<byte>(arr, 19, _byte(char2int1('X')))
  val () = ward_arr_set<byte>(arr, 20, _byte(40))  (* '(' *)
  val () = ward_arr_set<byte>(arr, 21, _byte(45))  (* '-' *)
  (* decimal digits *)
  val ndigits = itoa_to_arr(arr, pixel_offset, 22)
  val pos = 22 + ndigits
  (* "px)" — 3 bytes *)
  val () = ward_arr_set<byte>(arr, _idx48(pos), _byte(char2int1('p')))
  val () = ward_arr_set<byte>(arr, _idx48(pos + 1), _byte(char2int1('x')))
  val () = ward_arr_set<byte>(arr, _idx48(pos + 2), _byte(41))  (* ')' *)
in pos + 3 end

(* Apply CSS transform to scroll chapter container to current page.
 * Uses measure_node_width wrapper for clarity. *)
fn apply_page_transform(container_id: int): void = let
  val page_width = measure_node_width(reader_get_viewport_id())
in
  if gt_int_int(page_width, 0) then let
    val cur_page = reader_get_current_page()
    val arr = ward_arr_alloc<byte>(48)
    val slen = build_transform_arr(arr, cur_page, page_width)
    (* Split arr to exact length for set_style *)
    val slen1 = g1ofg0(slen)
  in
    if slen1 > 0 then
      if slen1 <= 48 then let
        val @(used, rest) = ward_arr_split<byte>(arr, slen1)
        val () = ward_arr_free<byte>(rest)
        val @(frozen, borrow) = ward_arr_freeze<byte>(used)
        val dom = ward_dom_init()
        val s = ward_dom_stream_begin(dom)
        val s = ward_dom_stream_set_style(s, container_id, borrow, slen1)
        val dom = ward_dom_stream_end(s)
        val () = ward_dom_fini(dom)
        val () = ward_arr_drop<byte>(frozen, borrow)
        val used = ward_arr_thaw<byte>(frozen)
        val () = ward_arr_free<byte>(used)
      in end
      else let
        val () = ward_arr_free<byte>(arr)
      in end
    else let
      val () = ward_arr_free<byte>(arr)
    in end
  end
  else ()
end

(* Measure chapter container and viewport, compute total pages.
 * Uses safe wrappers to prevent slot confusion (see SCROLL_WIDTH_SLOT). *)
fn measure_and_set_pages(container_id: int): void = let
  val scroll_width = measure_node_scroll_width(container_id)
  val page_width = measure_node_width(reader_get_viewport_id())
in
  if gt_int_int(page_width, 0) then let
    (* ceiling division: (scrollWidth + pageWidth - 1) / pageWidth *)
    val total = div_int_int(scroll_width + page_width - 1, page_width)
    val () = reader_set_total_pages(total)
  in end
  else ()
end

(* Update page indicator text: "Ch X/Y  N/M" showing chapter and page position.
 * Uses standalone DOM stream — safe to call from event handlers.
 * Format: "Ch 1/5  3/10" — chapter 1 of 5, page 3 of 10.
 * Buffer: 48 bytes, max realistic content ~20 chars. *)
fn update_page_info(): void = let
  val nid = reader_get_page_indicator_id()
in
  if gt_int_int(nid, 0) then let
    val cur_ch = reader_get_current_chapter()
    val total_ch = reader_get_chapter_count()
    val cur_pg = reader_get_current_page()
    val total_pg = reader_get_total_pages()
    val arr = ward_arr_alloc<byte>(48)
    (* Write "Ch " prefix — 67='C' 104='h' 32=' ' *)
    val () = ward_arr_set<byte>(arr, _idx48(0), _byte(67))
    val () = ward_arr_set<byte>(arr, _idx48(1), _byte(104))
    val () = ward_arr_set<byte>(arr, _idx48(2), _byte(32))
    (* Chapter number (1-indexed) *)
    val ch_digits = itoa_to_arr(arr, cur_ch + 1, 3)
    val p = 3 + ch_digits
    val () = ward_arr_set<byte>(arr, _idx48(p), _byte(47))     (* '/' *)
    val tch_digits = itoa_to_arr(arr, total_ch, p + 1)
    val p2 = p + 1 + tch_digits
    (* Two-space separator *)
    val () = ward_arr_set<byte>(arr, _idx48(p2), _byte(32))
    val () = ward_arr_set<byte>(arr, _idx48(p2 + 1), _byte(32))
    (* Page number (1-indexed) *)
    val pg_digits = itoa_to_arr(arr, cur_pg + 1, p2 + 2)
    val p3 = p2 + 2 + pg_digits
    val () = ward_arr_set<byte>(arr, _idx48(p3), _byte(47))    (* '/' *)
    val tpg_digits = itoa_to_arr(arr, total_pg, p3 + 1)
    val total_len = p3 + 1 + tpg_digits
    val tl = g1ofg0(total_len)
  in
    if tl > 0 then
      if tl < 48 then let
        val @(used, rest) = ward_arr_split<byte>(arr, tl)
        val () = ward_arr_free<byte>(rest)
        val @(frozen, borrow) = ward_arr_freeze<byte>(used)
        val dom = ward_dom_init()
        val s = ward_dom_stream_begin(dom)
        val s = ward_dom_stream_set_text(s, nid, borrow, tl)
        val dom = ward_dom_stream_end(s)
        val () = ward_dom_fini(dom)
        val () = ward_arr_drop<byte>(frozen, borrow)
        val used = ward_arr_thaw<byte>(frozen)
        val () = ward_arr_free<byte>(used)
      in end
      else let val () = ward_arr_free<byte>(arr) in end
    else let val () = ward_arr_free<byte>(arr) in end
  end
  else ()
end

(* page_turn_forward: advance page within chapter and update display.
 * Bundles reader_next_page + apply_page_transform + update_page_info.
 * Returns PAGE_DISPLAY_UPDATED proof — the ONLY way to obtain it for
 * forward page turns. Caller must destructure the proof.
 *
 * Precondition: caller has already verified pg < total - 1. *)
(* save_reading_position: persist current reading position to IDB.
 * Returns POSITION_PERSISTED proof — compile-time guarantee that
 * library_update_position + library_save were called.
 * Bug class prevented: adding a navigation path that skips save. *)
fn save_reading_position(): (POSITION_PERSISTED() | void) = let
  val () = library_update_position(
    reader_get_book_index(),
    reader_get_current_chapter(),
    reader_get_current_page())
  val () = library_save()
  prval pf = POS_PERSISTED()
in (pf | ()) end

fn page_turn_forward(container_id: int)
  : @(PAGE_DISPLAY_UPDATED(), POSITION_PERSISTED() | void) = let
  val () = reader_next_page()
  val () = apply_page_transform(container_id)
  val () = update_page_info()
  val (pf_pos | ()) = save_reading_position()
  prval pf_pg = PAGE_TURNED_AND_SHOWN()
in @(pf_pg, pf_pos | ()) end

(* page_turn_backward: go to previous page within chapter and update display.
 * Bundles reader_prev_page + apply_page_transform + update_page_info.
 * Returns PAGE_DISPLAY_UPDATED + POSITION_PERSISTED proofs.
 * Caller must destructure both proofs.
 *
 * Precondition: caller has already verified pg > 0. *)
fn page_turn_backward(container_id: int)
  : @(PAGE_DISPLAY_UPDATED(), POSITION_PERSISTED() | void) = let
  val () = reader_prev_page()
  val () = apply_page_transform(container_id)
  val () = update_page_info()
  val (pf_pos | ()) = save_reading_position()
  prval pf_pg = PAGE_TURNED_AND_SHOWN()
in @(pf_pg, pf_pos | ()) end

(* Save reading position and exit reader.
 * Constructs POSITION_SAVED proof required by reader_exit.
 * This is THE only permitted way to exit the reader from ATS code.
 * See POSITION_SAVED dataprop in reader.sats. *)
fn reader_save_and_exit(): void = let
  val () = library_update_position(
    reader_get_book_index(),
    reader_get_current_chapter(),
    reader_get_current_page())
  prval pf = SAVED()
in
  reader_exit(pf)
end

(* Apply resume page after chapter loads.
 * If reader_get_resume_page() > 0, go to that page (clamped to total),
 * apply transform, clear resume page. Called after measure_and_set_pages. *)
fn apply_resume_page(container_id: int): void = let
  val resume_pg = reader_get_resume_page()
in
  if gt_int_int(resume_pg, 0) then let
    val () = reader_go_to_page(resume_pg)
    val () = apply_page_transform(container_id)
    val () = update_page_info()
    val () = reader_set_resume_page(0)
  in end
  else ()
end


(* ========== Chapter loading ========== *)

(* show_chapter_error: Display an error message in the chapter container.
 * Clears existing content and shows a styled <p class="chapter-error">. *)
fn show_chapter_error {tid:nat}{tl:pos | tl < 65536}
  (pf: VALID_TEXT(tid, tl) | container_id: int, text_id: int(tid), text_len: int(tl)): void = let
  val dom = ward_dom_init()
  val s = ward_dom_stream_begin(dom)
  val s = ward_dom_stream_remove_children(s, container_id)
  val error_id = dom_next_id()
  val s = ward_dom_stream_create_element(s, error_id, container_id, tag_p(), 1)
  val s = ward_dom_stream_set_attr_safe(s, error_id, attr_class(), 5,
    cls_chapter_error(), 13)
  val s = set_text_cstr(pf | s, error_id, text_id, text_len)
  val dom = ward_dom_stream_end(s)
  val () = ward_dom_fini(dom)
in end

(* Validate render window after rendering + measuring.
 * Computes elements-per-page (epp) and determines the window tier:
 *   - WINDOW_5: 5*epp <= MAX_RENDER_ELEMENTS (typical — budget covers 5+ pages)
 *   - WINDOW_3: 3*epp <= budget but 5*epp > budget (dense content)
 *   - WINDOW_1: epp <= budget but 3*epp > budget (very dense)
 *   - ADVERSARIAL: epp > budget — show visible error + log
 *
 * Proofs (WINDOW_OPTIMAL, ADVERSARIAL_PAGE) document which tier was selected.
 * Runtime branches verify the arithmetic; comments reference the dataprop
 * constructors since freestanding ATS2 can't track g0int arithmetic. *)
fn validate_render_window(ecnt: int, container_id: int): void = let
  val pages = reader_get_total_pages()
in
  if gt_int_int(pages, 0) then let
    val epp = div_int_int(ecnt, pages)
  in
    if lte_int_int(mul_int_int(5, epp), MAX_RENDER_ELEMENTS) then
      () (* WINDOW_OPTIMAL: WINDOW_5 — budget supports 5+ pages *)
    else if lte_int_int(mul_int_int(3, epp), MAX_RENDER_ELEMENTS) then
      () (* WINDOW_OPTIMAL: WINDOW_3 — budget supports 3 pages *)
    else if lte_int_int(epp, MAX_RENDER_ELEMENTS) then
      () (* WINDOW_OPTIMAL: WINDOW_1 — budget supports 1 page *)
    else let
      (* ADVERSARIAL_PAGE: TOO_DENSE — single page exceeds budget *)
      val () = ward_log(3, mk_ch_err(char2int1('d'), char2int1('n'), char2int1('s')), 10)
    in show_chapter_error(VT_15() | container_id, 15, 14) end
  end
  else () (* no pages — nothing to validate *)
end

(* finish_chapter_load: Complete chapter display after rendering.
 * Bundles ALL steps required to make chapter content visible:
 *   1. measure_and_set_pages — compute pagination from scrollWidth
 *   2. validate_render_window — sanity check rendered element count
 *   3. apply_page_transform — reset CSS transform to current page
 *   4. update_page_info — update "Ch X/Y N/M" UI
 *   5. apply_resume_page — override if resuming saved position
 *
 * Produces CHAPTER_DISPLAY_READY proof, which is the ONLY way to
 * obtain this dataprop. Consolidating all steps here makes it
 * impossible to skip apply_page_transform (the root cause of
 * blank first-page-after-chapter-transition). *)
fn finish_chapter_load(container_id: int)
  : (CHAPTER_DISPLAY_READY() | void) = let
  val () = measure_and_set_pages(container_id)
  val () = validate_render_window(dom_get_render_ecnt(), container_id)
  val () = apply_page_transform(container_id)
  val () = update_page_info()
  val () = apply_resume_page(container_id)
  prval pf = MEASURED_AND_TRANSFORMED()
in (pf | ()) end

(* Extract chapter directory from spine path in sbuf.
 * Scans sbuf[0..path_len-1] backward for last '/'.
 * Returns directory length (including trailing '/'), or 0 if no '/'.
 * E.g., "OEBPS/Text/ch1.xhtml" → dir_len=11 ("OEBPS/Text/") *)
fn find_chapter_dir_len(path_len: int): [d:nat] int(d) = let
  fun scan {k:nat} .<k>.
    (rem: int(k), pos: int): int =
    if lte_g1(rem, 0) then 0
    else if pos < 0 then 0
    else if _app_sbuf_get_u8(pos) = 47 (* '/' *)
    then pos + 1
    else scan(sub_g1(rem, 1), pos - 1)
  val d = scan(_checked_nat(path_len), path_len - 1)
in
  if d >= 0 then _checked_nat(d)
  else _checked_nat(0)
end

(* Allocate a ward_arr and copy sbuf[0..len-1] into it.
 * Used to capture chapter directory before sbuf is reused. *)
fn copy_sbuf_to_arr {dl:pos | dl <= 1048576}
  (dl: int dl): [l:agz] ward_arr(byte, l, dl) = let
  val arr = ward_arr_alloc<byte>(dl)
  fun copy_loop {l:agz}{n:pos}{k:nat} .<k>.
    (rem: int(k), a: !ward_arr(byte, l, n), alen: int n, i: int, count: int): void =
    if lte_g1(rem, 0) then ()
    else if i < count then let
      val b = _app_sbuf_get_u8(i)
      val () = ward_arr_write_byte(a, _ward_idx(i, alen), _checked_byte(b))
    in copy_loop(sub_g1(rem, 1), a, alen, i + 1, count) end
  val () = copy_loop(_checked_nat(_g0(dl)), arr, dl, 0, dl)
in arr end

(*
 * NOTE: load_chapter (ZIP-based direct read) was removed.
 * All chapter loading now goes through load_chapter_from_idb,
 * which reads pre-exploded resources from IDB (M1.2).
 * ZIP_OPEN_OK proof prevents zip_find_entry on empty archives.
 *)

(* ========== IDB-based image loading from IDB ========== *)

(* Detect MIME type from image data magic bytes.
 * Returns: 1=jpeg, 2=png, 3=gif, 4=svg+xml, 0=unknown *)
fn detect_mime_from_magic {lb:agz}{n:pos}
  (arr: !ward_arr(byte, lb, n), len: int n): int =
  if gte_int_int(len, 4) then let
    val b0 = byte2int0(ward_arr_get<byte>(arr, _ward_idx(0, len)))
    val b1 = byte2int0(ward_arr_get<byte>(arr, _ward_idx(1, len)))
    val b2 = byte2int0(ward_arr_get<byte>(arr, _ward_idx(2, len)))
    val b3 = byte2int0(ward_arr_get<byte>(arr, _ward_idx(3, len)))
  in
    if eq_int_int(b0, 255) then (* 0xFF *)
      if eq_int_int(b1, 216) then 1 (* 0xD8 → JPEG *)
      else 0
    else if eq_int_int(b0, 137) then (* 0x89 *)
      if eq_int_int(b1, 80) then (* 0x50 = 'P' *)
        if eq_int_int(b2, 78) then (* 0x4E = 'N' *)
          if eq_int_int(b3, 71) then 2 (* 0x47 = 'G' → PNG *)
          else 0
        else 0
      else 0
    else if eq_int_int(b0, 71) then (* 0x47 = 'G' *)
      if eq_int_int(b1, 73) then (* 0x49 = 'I' *)
        if eq_int_int(b2, 70) then 3 (* 0x46 = 'F' → GIF *)
        else 0
      else 0
    else if eq_int_int(b0, 60) then 4 (* 0x3C = '<' → SVG/XML *)
    else 0
  end
  else 0

(* Set image src on a DOM node from IDB-retrieved data.
 * Detects MIME from magic bytes, creates its own DOM stream.
 * Consumes the data array. *)
fn set_image_src_idb {lb:agz}{n:pos}
  (node_id: int, data: ward_arr(byte, lb, n), data_len: int n): void = let
  val mime_type = detect_mime_from_magic(data, data_len)
in
  if eq_int_int(mime_type, 0) then
    ward_arr_free<byte>(data) (* unknown MIME — skip, free data *)
  else let
    val dom = ward_dom_init()
    val s = ward_dom_stream_begin(dom)
    val @(frozen, borrow) = ward_arr_freeze<byte>(data)
  in
    if eq_int_int(mime_type, 1) then let (* JPEG *)
      val b = ward_content_text_build(10)
      val b = ward_content_text_putc(b, 0, char2int1('i'))
      val b = ward_content_text_putc(b, 1, char2int1('m'))
      val b = ward_content_text_putc(b, 2, char2int1('a'))
      val b = ward_content_text_putc(b, 3, char2int1('g'))
      val b = ward_content_text_putc(b, 4, char2int1('e'))
      val b = ward_content_text_putc(b, 5, 47) (* '/' *)
      val b = ward_content_text_putc(b, 6, char2int1('j'))
      val b = ward_content_text_putc(b, 7, char2int1('p'))
      val b = ward_content_text_putc(b, 8, char2int1('e'))
      val b = ward_content_text_putc(b, 9, char2int1('g'))
      val mime = ward_content_text_done(b)
      val s = ward_dom_stream_set_image_src(s, node_id, borrow, data_len, mime, 10)
      val () = ward_safe_content_text_free(mime)
      val () = ward_arr_drop<byte>(frozen, borrow)
      val data = ward_arr_thaw<byte>(frozen)
      val () = ward_arr_free<byte>(data)
      val dom = ward_dom_stream_end(s)
      val () = ward_dom_fini(dom)
    in end
    else if eq_int_int(mime_type, 2) then let (* PNG *)
      val b = ward_content_text_build(9)
      val b = ward_content_text_putc(b, 0, char2int1('i'))
      val b = ward_content_text_putc(b, 1, char2int1('m'))
      val b = ward_content_text_putc(b, 2, char2int1('a'))
      val b = ward_content_text_putc(b, 3, char2int1('g'))
      val b = ward_content_text_putc(b, 4, char2int1('e'))
      val b = ward_content_text_putc(b, 5, 47) (* '/' *)
      val b = ward_content_text_putc(b, 6, char2int1('p'))
      val b = ward_content_text_putc(b, 7, char2int1('n'))
      val b = ward_content_text_putc(b, 8, char2int1('g'))
      val mime = ward_content_text_done(b)
      val s = ward_dom_stream_set_image_src(s, node_id, borrow, data_len, mime, 9)
      val () = ward_safe_content_text_free(mime)
      val () = ward_arr_drop<byte>(frozen, borrow)
      val data = ward_arr_thaw<byte>(frozen)
      val () = ward_arr_free<byte>(data)
      val dom = ward_dom_stream_end(s)
      val () = ward_dom_fini(dom)
    in end
    else if eq_int_int(mime_type, 3) then let (* GIF *)
      val b = ward_content_text_build(9)
      val b = ward_content_text_putc(b, 0, char2int1('i'))
      val b = ward_content_text_putc(b, 1, char2int1('m'))
      val b = ward_content_text_putc(b, 2, char2int1('a'))
      val b = ward_content_text_putc(b, 3, char2int1('g'))
      val b = ward_content_text_putc(b, 4, char2int1('e'))
      val b = ward_content_text_putc(b, 5, 47) (* '/' *)
      val b = ward_content_text_putc(b, 6, char2int1('g'))
      val b = ward_content_text_putc(b, 7, char2int1('i'))
      val b = ward_content_text_putc(b, 8, char2int1('f'))
      val mime = ward_content_text_done(b)
      val s = ward_dom_stream_set_image_src(s, node_id, borrow, data_len, mime, 9)
      val () = ward_safe_content_text_free(mime)
      val () = ward_arr_drop<byte>(frozen, borrow)
      val data = ward_arr_thaw<byte>(frozen)
      val () = ward_arr_free<byte>(data)
      val dom = ward_dom_stream_end(s)
      val () = ward_dom_fini(dom)
    in end
    else let (* SVG *)
      val b = ward_content_text_build(13)
      val b = ward_content_text_putc(b, 0, char2int1('i'))
      val b = ward_content_text_putc(b, 1, char2int1('m'))
      val b = ward_content_text_putc(b, 2, char2int1('a'))
      val b = ward_content_text_putc(b, 3, char2int1('g'))
      val b = ward_content_text_putc(b, 4, char2int1('e'))
      val b = ward_content_text_putc(b, 5, 47) (* '/' *)
      val b = ward_content_text_putc(b, 6, char2int1('s'))
      val b = ward_content_text_putc(b, 7, char2int1('v'))
      val b = ward_content_text_putc(b, 8, char2int1('g'))
      val b = ward_content_text_putc(b, 9, 43) (* '+' *)
      val b = ward_content_text_putc(b, 10, char2int1('x'))
      val b = ward_content_text_putc(b, 11, char2int1('m'))
      val b = ward_content_text_putc(b, 12, char2int1('l'))
      val mime = ward_content_text_done(b)
      val s = ward_dom_stream_set_image_src(s, node_id, borrow, data_len, mime, 13)
      val () = ward_safe_content_text_free(mime)
      val () = ward_arr_drop<byte>(frozen, borrow)
      val data = ward_arr_thaw<byte>(frozen)
      val () = ward_arr_free<byte>(data)
      val dom = ward_dom_stream_end(s)
      val () = ward_dom_fini(dom)
    in end
  end
end

(* Pre-scan: resolve deferred image paths and find entry indices.
 * For each deferred image in the queue, resolves path via resolve_img_src
 * and looks up the manifest entry via epub_find_resource.
 * Stores (node_id, entry_idx) pairs in app_state deferred image buffers.
 * Returns the count of successfully resolved images. *)
fun prescan_deferred_for_idb {lb:agz}{n:pos}{ld:agz}{nd:pos}{k:nat} .<k>.
  (rem: int(k),
   tree: !ward_arr(byte, lb, n), tlen: int n,
   cdir: !ward_arr(byte, ld, nd), cdlen: int nd,
   i: int, total: int, out: int): int =
  if lte_g1(rem, 0) then out
  else if gte_int_int(i, total) then out
  else let
    val nid = deferred_image_get_node_id(i)
    val src_off = deferred_image_get_src_off(i)
    val src_len = deferred_image_get_src_len(i)
    val path_len = resolve_img_src(tree, tlen, src_off, src_len, cdir, cdlen)
    val entry_idx = epub_find_resource(path_len)
  in
    if gte_g1(entry_idx, 0) then let
      val () = _app_deferred_img_node_id_set(out, nid)
      val () = _app_deferred_img_entry_idx_set(out, _g0(entry_idx))
    in prescan_deferred_for_idb(sub_g1(rem, 1), tree, tlen, cdir, cdlen,
      i + 1, total, out + 1) end
    else prescan_deferred_for_idb(sub_g1(rem, 1), tree, tlen, cdir, cdlen,
      i + 1, total, out)
  end

(* Async chain: load each deferred image from IDB and set its src.
 * For each (node_id, entry_idx) pair, builds IDB key, fetches data,
 * detects MIME from magic bytes, and sets image src. *)
fun load_idb_images_chain {k:nat} .<k>.
  (rem: int(k), idx: int, total: int): void =
  if lte_g1(rem, 0) then ()
  else if gte_int_int(idx, total) then ()
  else let
    val nid = _app_deferred_img_node_id_get(idx)
    val entry_idx = _app_deferred_img_entry_idx_get(idx)
    val key = epub_build_resource_key(entry_idx)
    val p = ward_idb_get(key, 20)
    val saved_nid = nid
    val saved_rem = sub_g1(rem, 1)
    val saved_next = idx + 1
    val saved_total = total
    val p2 = ward_promise_then<int><int>(p,
      llam (data_len: int): ward_promise_chained(int) =>
        if lte_int_int(data_len, 0) then let
          val () = load_idb_images_chain(saved_rem, saved_next, saved_total)
        in ward_promise_return<int>(0) end
        else let
          val dl = _checked_pos(data_len)
          val arr = ward_idb_get_result(dl)
          val () = set_image_src_idb(saved_nid, arr, dl)
          val () = load_idb_images_chain(saved_rem, saved_next, saved_total)
        in ward_promise_return<int>(1) end)
    val () = ward_promise_discard<int>(p2)
  in end

(* ========== IDB-based chapter loading ========== *)

(* Load chapter from IDB — no file handle needed.
 * Looks up spine→entry index from manifest, builds IDB key,
 * fetches decompressed XHTML from IDB, parses and renders. *)
fn load_chapter_from_idb {c,t:nat | c < t}
  (pf: SPINE_ORDERED(c, t) |
   chapter_idx: int(c), spine_count: int(t), container_id: int): void = let
  val entry_idx = _app_epub_spine_entry_idx_get(chapter_idx)
  val key = epub_build_resource_key(entry_idx)
  val p = ward_idb_get(key, 20)
  val saved_cid = container_id
  (* Copy spine path to sbuf[0..] and extract chapter dir *)
  val path_len = epub_copy_spine_path(pf | chapter_idx, spine_count, 0)
  val dir_len = find_chapter_dir_len(path_len)
in
  if gt_int_int(dir_len, 0) then let
    val dl_pos = _checked_arr_size(dir_len)
    val dir_arr = copy_sbuf_to_arr(dl_pos)
    val p2 = ward_promise_then<int><int>(p,
      llam (data_len: int): ward_promise_chained(int) =>
        if lte_int_int(data_len, 0) then let
          val () = ward_arr_free<byte>(dir_arr)
          val () = ward_log(3, mk_ch_err(char2int1('g'), char2int1('e'), char2int1('t')), 10)
          val () = show_chapter_error(VT_9() | saved_cid, 9, 17)
        in ward_promise_return<int>(0) end
        else let
          val dl = _checked_pos(data_len)
          val arr = ward_idb_get_result(dl)
          val @(frozen, borrow) = ward_arr_freeze<byte>(arr)
          val sax_len = ward_xml_parse_html(borrow, dl)
          val () = ward_arr_drop<byte>(frozen, borrow)
          val arr = ward_arr_thaw<byte>(frozen)
          val () = ward_arr_free<byte>(arr)
        in
          if gt_int_int(sax_len, 0) then let
            val sl = _checked_pos(sax_len)
            val sax_buf = ward_xml_get_result(sl)
            val dom = ward_dom_init()
            val s = ward_dom_stream_begin(dom)
            val s = render_tree_with_images(s, saved_cid, sax_buf, sl,
              0, dir_arr, dl_pos)
            val dom = ward_dom_stream_end(s)
            val () = ward_dom_fini(dom)
            (* Pre-scan: resolve deferred image paths → entry indices *)
            val img_q_count = deferred_image_get_count()
            val img_count = prescan_deferred_for_idb(
              _checked_nat(img_q_count), sax_buf, sl,
              dir_arr, dl_pos, 0, img_q_count, 0)
            val () = _app_set_deferred_img_count(img_count)
            val () = ward_arr_free<byte>(sax_buf)
            val () = ward_arr_free<byte>(dir_arr)
            val (pf_disp | ()) = finish_chapter_load(saved_cid)
            prval MEASURED_AND_TRANSFORMED() = pf_disp
            (* Async: load images from IDB *)
            val () = load_idb_images_chain(
              _checked_nat(img_count), 0, img_count)
          in ward_promise_return<int>(1) end
          else let
            val () = ward_arr_free<byte>(dir_arr)
            val () = show_chapter_error(VT_13() | saved_cid, 13, 21)
          in ward_promise_return<int>(0) end
        end)
    val () = ward_promise_discard<int>(p2)
  in end
  else let
    (* No directory prefix *)
    val p2 = ward_promise_then<int><int>(p,
      llam (data_len: int): ward_promise_chained(int) =>
        if lte_int_int(data_len, 0) then let
          val () = ward_log(3, mk_ch_err(char2int1('g'), char2int1('t'), char2int1('2')), 10)
          val () = show_chapter_error(VT_9() | saved_cid, 9, 17)
        in ward_promise_return<int>(0) end
        else let
          val dl = _checked_pos(data_len)
          val arr = ward_idb_get_result(dl)
          val @(frozen, borrow) = ward_arr_freeze<byte>(arr)
          val sax_len = ward_xml_parse_html(borrow, dl)
          val () = ward_arr_drop<byte>(frozen, borrow)
          val arr = ward_arr_thaw<byte>(frozen)
          val () = ward_arr_free<byte>(arr)
        in
          if gt_int_int(sax_len, 0) then let
            val sl = _checked_pos(sax_len)
            val sax_buf = ward_xml_get_result(sl)
            val dom = ward_dom_init()
            val s = ward_dom_stream_begin(dom)
            val s = render_tree(s, saved_cid, sax_buf, sl)
            val dom = ward_dom_stream_end(s)
            val () = ward_dom_fini(dom)
            val () = ward_arr_free<byte>(sax_buf)
            val (pf_disp | ()) = finish_chapter_load(saved_cid)
            prval MEASURED_AND_TRANSFORMED() = pf_disp
          in ward_promise_return<int>(1) end
          else let
            val () = show_chapter_error(VT_13() | saved_cid, 13, 21)
          in ward_promise_return<int>(0) end
        end)
    val () = ward_promise_discard<int>(p2)
  in end
end

(* ========== Chapter navigation ========== *)

(* Navigate forward: advance page within chapter, or load next chapter.
 * When on the last page of the current chapter and there IS a next chapter,
 * clears the container and loads the next chapter asynchronously. *)
fn navigate_next(container_id: int): void = let
  val pg = reader_get_current_page()
  val total = reader_get_total_pages()
in
  if lt_int_int(pg, total - 1) then let
    (* Within chapter — advance page *)
    val @(pf_pg, pf_pos | ()) = page_turn_forward(container_id)
    prval PAGE_TURNED_AND_SHOWN() = pf_pg
    prval POS_PERSISTED() = pf_pos
  in end
  else let
    (* At last page — try advancing chapter *)
    val ch = reader_get_current_chapter()
    val spine = epub_get_chapter_count()
    val next_ch = ch + 1
  in
    if lt_int_int(next_ch, spine) then let
      val spine_g1 = g1ofg0(spine)
      val next_g1 = _checked_nat(next_ch)
    in
      if lt1_int_int(next_g1, spine_g1) then let
        prval pf = SPINE_ENTRY()
        val () = reader_go_to_chapter(next_g1, spine_g1)
        val () = reader_set_total_pages(1)
        val (pf_pos | ()) = save_reading_position()
        prval POS_PERSISTED() = pf_pos
        (* Clear container and load next chapter *)
        val dom = ward_dom_init()
        val s = ward_dom_stream_begin(dom)
        val s = ward_dom_stream_remove_children(s, container_id)
        val dom = ward_dom_stream_end(s)
        val () = ward_dom_fini(dom)
        val () = load_chapter_from_idb(pf | next_g1, spine_g1, container_id)
      in end
      else ()
    end
    else ()
  end
end

(* Navigate backward: go to previous page, or load previous chapter.
 * When on page 0 and there IS a previous chapter, loads it. *)
fn navigate_prev(container_id: int): void = let
  val pg = reader_get_current_page()
in
  if gt_int_int(pg, 0) then let
    (* Within chapter — go back a page *)
    val @(pf_pg, pf_pos | ()) = page_turn_backward(container_id)
    prval PAGE_TURNED_AND_SHOWN() = pf_pg
    prval POS_PERSISTED() = pf_pos
  in end
  else let
    (* At first page — try going to previous chapter *)
    val ch = reader_get_current_chapter()
  in
    if gt_int_int(ch, 0) then let
      val prev_ch = ch - 1
      val spine = epub_get_chapter_count()
      val spine_g1 = g1ofg0(spine)
      val prev_g1 = _checked_nat(prev_ch)
    in
      if lt1_int_int(prev_g1, spine_g1) then let
        prval pf = SPINE_ENTRY()
        val () = reader_go_to_chapter(prev_g1, spine_g1)
        val () = reader_set_total_pages(1)
        val (pf_pos | ()) = save_reading_position()
        prval POS_PERSISTED() = pf_pos
        (* Clear container and load previous chapter *)
        val dom = ward_dom_init()
        val s = ward_dom_stream_begin(dom)
        val s = ward_dom_stream_remove_children(s, container_id)
        val dom = ward_dom_stream_end(s)
        val () = ward_dom_fini(dom)
        val () = load_chapter_from_idb(pf | prev_g1, spine_g1, container_id)
      in end
      else ()
    end
    else ()
  end
end

(* ========== Reader keyboard handler ========== *)

fn on_reader_keydown(payload_len: int, root_id: int): void = let
  val pl = g1ofg0(payload_len)
in
  (* Keydown payload: [u8:keyLen][bytes:key][u8:flags]
   * Minimum payload sizes: Space=3, Escape=8, ArrowLeft=11, ArrowRight=12 *)
  if gt1_int_int(pl, 2) then let
    val payload = ward_event_get_payload(pl)
    val key_len = byte2int0(ward_arr_get<byte>(payload, 0))
    val k0 = byte2int0(ward_arr_get<byte>(payload, 1))
    val () = ward_arr_free<byte>(payload)
    val cid = reader_get_container_id()
  in
    if eq_int_int(key_len, 6) then
      (* "Escape": key_len=6, k0='E' (69) *)
      if eq_int_int(k0, 69) then let
        val () = reader_save_and_exit()
        val () = render_library(root_id)
      in end
      else ()
    else if eq_int_int(key_len, 10) then
      (* "ArrowRight": key_len=10, k0='A' (65) *)
      if eq_int_int(k0, 65) then navigate_next(cid)
      else ()
    else if eq_int_int(key_len, 9) then
      (* "ArrowLeft": key_len=9, k0='A' (65) *)
      if eq_int_int(k0, 65) then navigate_prev(cid)
      else ()
    else if eq_int_int(key_len, 1) then
      (* " " (Space): key_len=1, k0=' ' (32) *)
      if eq_int_int(k0, 32) then navigate_next(cid)
      else ()
    else ()
  end
  else ()
end

(* ========== Enter reader view ========== *)

implement enter_reader(root_id, book_index) = let
  val () = reader_enter(root_id, 0)
  val () = reader_set_book_index(book_index)
  val bi = g1ofg0(book_index)
  val cnt = library_get_count()
  val ok = check_book_index(bi, cnt)
  val () = if eq_g1(ok, 1) then let
    val (pf_ba | biv) = _mk_book_access(book_index)
    val _ = epub_set_book_id_from_library(pf_ba | biv)
  in end

  val dom = ward_dom_init()
  val s = ward_dom_stream_begin(dom)
  val s = ward_dom_stream_remove_children(s, root_id)
  val s = inject_app_css(s, root_id)
  val s = inject_nav_css(s, root_id)

  (* Create nav bar: <div class="reader-nav">
   *   <button class="back-btn">Back</button>
   *   <div class="nav-controls">
   *     <button class="prev-btn">Prev</button>
   *     <span class="page-info"></span>
   *     <button class="next-btn">Next</button>
   *   </div>
   * </div> *)
  val nav_id = dom_next_id()
  val s = ward_dom_stream_create_element(s, nav_id, root_id, tag_div(), 3)
  val s = ward_dom_stream_set_attr_safe(s, nav_id, attr_class(), 5,
    cls_reader_nav(), 10)

  val back_btn_id = dom_next_id()
  val s = ward_dom_stream_create_element(s, back_btn_id, nav_id, tag_button(), 6)
  val s = ward_dom_stream_set_attr_safe(s, back_btn_id, attr_class(), 5,
    cls_back_btn(), 8)
  (* "Back" = 4 chars *)
  val back_st = let
    val b = ward_text_build(4)
    val b = ward_text_putc(b, 0, char2int1('B'))
    val b = ward_text_putc(b, 1, char2int1('a'))
    val b = ward_text_putc(b, 2, char2int1('c'))
    val b = ward_text_putc(b, 3, char2int1('k'))
  in ward_text_done(b) end
  val s = ward_dom_stream_set_safe_text(s, back_btn_id, back_st, 4)

  (* Nav controls wrapper *)
  val controls_id = dom_next_id()
  val s = ward_dom_stream_create_element(s, controls_id, nav_id, tag_div(), 3)
  val s = ward_dom_stream_set_attr_safe(s, controls_id, attr_class(), 5,
    cls_nav_controls(), 12)

  (* Prev button *)
  val prev_btn_id = dom_next_id()
  val s = ward_dom_stream_create_element(s, prev_btn_id, controls_id, tag_button(), 6)
  val s = ward_dom_stream_set_attr_safe(s, prev_btn_id, attr_class(), 5,
    cls_prev_btn(), 8)
  val prev_st = let
    val b = ward_text_build(4)
    val b = ward_text_putc(b, 0, char2int1('P'))
    val b = ward_text_putc(b, 1, char2int1('r'))
    val b = ward_text_putc(b, 2, char2int1('e'))
    val b = ward_text_putc(b, 3, char2int1('v'))
  in ward_text_done(b) end
  val s = ward_dom_stream_set_safe_text(s, prev_btn_id, prev_st, 4)

  (* Page info *)
  val page_info_id = dom_next_id()
  val s = ward_dom_stream_create_element(s, page_info_id, controls_id, tag_span(), 4)
  val s = ward_dom_stream_set_attr_safe(s, page_info_id, attr_class(), 5,
    cls_page_info(), 9)

  (* Next button *)
  val next_btn_id = dom_next_id()
  val s = ward_dom_stream_create_element(s, next_btn_id, controls_id, tag_button(), 6)
  val s = ward_dom_stream_set_attr_safe(s, next_btn_id, attr_class(), 5,
    cls_next_btn(), 8)
  val next_st = let
    val b = ward_text_build(4)
    val b = ward_text_putc(b, 0, char2int1('N'))
    val b = ward_text_putc(b, 1, char2int1('e'))
    val b = ward_text_putc(b, 2, char2int1('x'))
    val b = ward_text_putc(b, 3, char2int1('t'))
  in ward_text_done(b) end
  val s = ward_dom_stream_set_safe_text(s, next_btn_id, next_st, 4)

  (* Create .reader-viewport with tabindex="0" for keyboard focus *)
  val viewport_id = dom_next_id()
  val s = ward_dom_stream_create_element(s, viewport_id, root_id, tag_div(), 3)
  val s = ward_dom_stream_set_attr_safe(s, viewport_id, attr_class(), 5,
    cls_reader_viewport(), 15)
  val s = ward_dom_stream_set_attr_safe(s, viewport_id, attr_tabindex(), 8,
    val_zero(), 1)

  (* Create .chapter-container *)
  val container_id = dom_next_id()
  val s = ward_dom_stream_create_element(s, container_id, viewport_id, tag_div(), 3)
  val s = ward_dom_stream_set_attr_safe(s, container_id, attr_class(), 5,
    cls_chapter_container(), 17)

  val dom = ward_dom_stream_end(s)
  val () = ward_dom_fini(dom)

  (* Store IDs *)
  val () = reader_set_viewport_id(viewport_id)
  val () = reader_set_container_id(container_id)
  val () = reader_set_nav_id(nav_id)
  val () = reader_set_page_info_id(page_info_id)

  (* Register click listener on back button *)
  val saved_root = root_id
  val saved_container = container_id
  val () = ward_add_event_listener(
    back_btn_id, evt_click(), 5, LISTENER_BACK,
    lam (_pl: int): int => let
      val () = reader_save_and_exit()
      val () = render_library(saved_root)
    in 0 end
  )

  (* Register click listener on prev button *)
  val () = ward_add_event_listener(
    prev_btn_id, evt_click(), 5, LISTENER_PREV,
    lam (_pl: int): int => let
      val () = navigate_prev(saved_container)
    in 0 end
  )

  (* Register click listener on next button *)
  val () = ward_add_event_listener(
    next_btn_id, evt_click(), 5, LISTENER_NEXT,
    lam (_pl: int): int => let
      val () = navigate_next(saved_container)
    in 0 end
  )

  (* Register keydown listener on viewport *)
  val () = ward_add_event_listener(
    viewport_id, evt_keydown(), 7, LISTENER_KEYDOWN,
    lam (payload_len: int): int => let
      val () = on_reader_keydown(payload_len, saved_root)
    in 0 end
  )

  (* Register click listener on viewport for page navigation *)
  val () = ward_add_event_listener(
    viewport_id, evt_click(), 5, LISTENER_VIEWPORT_CLICK,
    lam (pl: int): int => let
      val pl1 = g1ofg0(pl)
    in
      if gt1_int_int(pl1, 19) then let
        (* Click payload: f64 clientX (0-7), f64 clientY (8-15), i32 target (16-19) *)
        val payload = ward_event_get_payload(pl1)
        val click_x = read_payload_click_x(payload)
        val () = ward_arr_free<byte>(payload)
        val vw = measure_node_width(reader_get_viewport_id())
      in
        if gt_int_int(vw, 0) then let
          (* Right 75% → next page, left 25% → prev page *)
          val threshold = div_int_int(vw, 4)
        in
          if gt_int_int(click_x, threshold) then let
            val () = navigate_next(saved_container)
          in 0 end
          else let
            val () = navigate_prev(saved_container)
          in 0 end
        end
        else 0
      end
      else 0
    end
  )

  (* Load manifest from IDB, then restore chapter/page position *)
  val saved_bi = book_index
  val saved_cid = container_id
  val p_manifest = epub_load_manifest()
  val p2 = ward_promise_then<int><int>(p_manifest,
    llam (ok: int): ward_promise_chained(int) =>
      if lte_int_int(ok, 0) then let
        val () = ward_log(3, mk_ch_err(char2int1('m'), char2int1('a'), char2int1('n')), 10)
        val () = show_chapter_error(VT_9() | saved_cid, 9, 17)
      in ward_promise_return<int>(0) end
      else let
        val now = quire_time_now()
        val now_g1 = _checked_nat(now)
        val () = library_set_last_opened(VALID_TIMESTAMP() | saved_bi, now_g1)
        val () = library_save()
        val spine = epub_get_chapter_count()
        val spine_g1 = g1ofg0(spine)
        val saved_ch = library_get_chapter(saved_bi)
        val saved_pg = library_get_page(saved_bi)
        val start_ch: int = if lt_int_int(saved_ch, spine) then saved_ch else 0
        val start_ch_nat = _checked_nat(start_ch)
      in
        if lt1_int_int(start_ch_nat, spine_g1) then let
          prval pf = SPINE_ENTRY()
          val () = reader_go_to_chapter(start_ch_nat, spine_g1)
          val () = reader_set_resume_page(saved_pg)
          val () = load_chapter_from_idb(pf | start_ch_nat, spine_g1, saved_cid)
        in ward_promise_return<int>(1) end
        else let
          val () = ward_log(3, mk_ch_err(char2int1('s'), char2int1('p'), char2int1('n')), 10)
          val () = show_chapter_error(VT_14() | saved_cid, 14, 19)
        in ward_promise_return<int>(0) end
      end)
  val () = ward_promise_discard<int>(p2)
in end

(* ========== Entry point ========== *)

implement ward_node_init(root_id) = let
  val st = app_state_init()
  val () = app_state_register(st)
  val p = library_load()
  val saved_root = root_id
  val p2 = ward_promise_then<int><int>(p,
    llam (_ok: int): ward_promise_chained(int) => let
      val () = render_library(saved_root)
    in ward_promise_return<int>(0) end)
  val () = ward_promise_discard<int>(p2)
in end

(* Legacy callback stubs *)
implement init() = ()
implement process_event() = ()
implement on_fetch_complete(status, len) = ()
implement on_timer_complete(callback_id) = ()
implement on_file_open_complete(handle, size) = ()
implement on_decompress_complete(handle, size) = ()
implement on_kv_complete(success) = ()
implement on_kv_get_complete(len) = ()
implement on_kv_get_blob_complete(handle, size) = ()
implement on_clipboard_copy_complete(success) = ()
implement on_kv_open_complete(success) = ()
