(* epub.dats - EPUB import pipeline implementation
 *
 * All epub functions implemented in pure ATS2 using app_state.
 * State stored via app_state_load/store pattern.
 *)

#define ATS_DYNLOADFLAG 0

#include "share/atspre_staload.hats"
staload "./epub.sats"
staload "./app_state.sats"

(* ========== Arithmetic primitives ========== *)

extern fun add_int_int(a: int, b: int): int = "mac#quire_add"
extern fun sub_int_int(a: int, b: int): int = "mac#quire_sub"
extern fun mul_int_int(a: int, b: int): int = "mac#quire_mul"
extern fun eq_int_int(a: int, b: int): bool = "mac#quire_eq"
extern fun neq_int_int(a: int, b: int): bool = "mac#quire_neq"
extern fun gt_int_int(a: int, b: int): bool = "mac#quire_gt"
extern fun gte_int_int(a: int, b: int): bool = "mac#quire_gte"
extern fun lt_int_int(a: int, b: int): bool = "mac#quire_lt"
extern fun lte_int_int(a: int, b: int): bool = "mac#quire_lte"

overload + with add_int_int of 10
overload - with sub_int_int of 10
overload * with mul_int_int of 10

(* ========== Byte-level access ========== *)

extern fun buf_get_u8(p: ptr, off: int): int = "mac#"
extern fun buf_set_u8(p: ptr, off: int, v: int): void = "mac#"
extern fun buf_get_i32(p: ptr, idx: int): int = "mac#"
extern fun buf_set_i32(p: ptr, idx: int, v: int): void = "mac#"
extern fun get_string_buffer_ptr(): ptr = "mac#"

(* ========== C-callable epub field accessors (ext# in app_state.dats) ========== *)

extern fun _app_epub_spine_count(): int = "mac#_app_epub_spine_count"
extern fun _app_set_epub_spine_count(v: int): void = "mac#_app_set_epub_spine_count"
extern fun _app_epub_title_ptr(): ptr = "mac#_app_epub_title_ptr"
extern fun _app_epub_title_len(): int = "mac#_app_epub_title_len"
extern fun _app_set_epub_title_len(v: int): void = "mac#_app_set_epub_title_len"
extern fun _app_epub_author_ptr(): ptr = "mac#_app_epub_author_ptr"
extern fun _app_epub_author_len(): int = "mac#_app_epub_author_len"
extern fun _app_set_epub_author_len(v: int): void = "mac#_app_set_epub_author_len"
extern fun _app_epub_book_id_ptr(): ptr = "mac#_app_epub_book_id_ptr"
extern fun _app_epub_book_id_len(): int = "mac#_app_epub_book_id_len"
extern fun _app_set_epub_book_id_len(v: int): void = "mac#_app_set_epub_book_id_len"
extern fun _app_epub_opf_path_ptr(): ptr = "mac#_app_epub_opf_path_ptr"
extern fun _app_epub_opf_path_len(): int = "mac#_app_epub_opf_path_len"
extern fun _app_set_epub_opf_path_len(v: int): void = "mac#_app_set_epub_opf_path_len"
extern fun _app_epub_opf_dir_len(): int = "mac#_app_epub_opf_dir_len"
extern fun _app_set_epub_opf_dir_len(v: int): void = "mac#_app_set_epub_opf_dir_len"
extern fun _app_epub_state(): int = "mac#_app_epub_state"
extern fun _app_set_epub_state(v: int): void = "mac#_app_set_epub_state"
extern fun _app_epub_spine_path_buf(): ptr = "mac#_app_epub_spine_path_buf"
extern fun _app_epub_spine_path_offsets(): ptr = "mac#_app_epub_spine_path_offsets"
extern fun _app_epub_spine_path_lens(): ptr = "mac#_app_epub_spine_path_lens"
extern fun _app_epub_spine_path_count(): int = "mac#_app_epub_spine_path_count"
extern fun _app_set_epub_spine_path_count(v: int): void = "mac#_app_set_epub_spine_path_count"
extern fun _app_epub_spine_path_pos(): int = "mac#_app_epub_spine_path_pos"
extern fun _app_set_epub_spine_path_pos(v: int): void = "mac#_app_set_epub_spine_path_pos"

(* ========== Byte search helper ========== *)

(* Find needle bytes in haystack starting at position start.
 * Returns index of first match, or -1 if not found. *)
fn _find_bytes(hay: ptr, hay_len: int,
               needle: ptr, needle_len: int, start: int): int = let
  val limit = hay_len - needle_len
  fun outer(i: int): int =
    if gt_int_int(i, limit) then 0 - 1
    else let
      fun inner(j: int): bool =
        if gte_int_int(j, needle_len) then true
        else if neq_int_int(buf_get_u8(hay, i + j), buf_get_u8(needle, j)) then false
        else inner(j + 1)
    in
      if inner(0) then i
      else outer(i + 1)
    end
in outer(start) end

(* ========== Needle builder helpers ========== *)

(* Bump allocator — never freed *)
extern fun _calloc(n: int, sz: int): ptr = "mac#calloc"

(* Build a needle buffer from known byte values.
 * Returns ptr to a calloc'd buffer filled with the given bytes. *)

(* "full-path=\"" = 102 117 108 108 45 112 97 116 104 61 34 — 11 bytes *)
fn needle_full_path(): ptr = let
  val p = _calloc(1, 11)
  val () = buf_set_u8(p, 0, 102) (* f *)
  val () = buf_set_u8(p, 1, 117) (* u *)
  val () = buf_set_u8(p, 2, 108) (* l *)
  val () = buf_set_u8(p, 3, 108) (* l *)
  val () = buf_set_u8(p, 4, 45)  (* - *)
  val () = buf_set_u8(p, 5, 112) (* p *)
  val () = buf_set_u8(p, 6, 97)  (* a *)
  val () = buf_set_u8(p, 7, 116) (* t *)
  val () = buf_set_u8(p, 8, 104) (* h *)
  val () = buf_set_u8(p, 9, 61)  (* = *)
  val () = buf_set_u8(p, 10, 34) (* " *)
in p end

(* "<dc:title>" = 60 100 99 58 116 105 116 108 101 62 — 10 bytes *)
fn needle_dc_title_open(): ptr = let
  val p = _calloc(1, 10)
  val () = buf_set_u8(p, 0, 60)  (* < *)
  val () = buf_set_u8(p, 1, 100) (* d *)
  val () = buf_set_u8(p, 2, 99)  (* c *)
  val () = buf_set_u8(p, 3, 58)  (* : *)
  val () = buf_set_u8(p, 4, 116) (* t *)
  val () = buf_set_u8(p, 5, 105) (* i *)
  val () = buf_set_u8(p, 6, 116) (* t *)
  val () = buf_set_u8(p, 7, 108) (* l *)
  val () = buf_set_u8(p, 8, 101) (* e *)
  val () = buf_set_u8(p, 9, 62)  (* > *)
in p end

(* "</dc:title>" = 60 47 100 99 58 116 105 116 108 101 62 — 11 bytes *)
fn needle_dc_title_close(): ptr = let
  val p = _calloc(1, 11)
  val () = buf_set_u8(p, 0, 60)  (* < *)
  val () = buf_set_u8(p, 1, 47)  (* / *)
  val () = buf_set_u8(p, 2, 100) (* d *)
  val () = buf_set_u8(p, 3, 99)  (* c *)
  val () = buf_set_u8(p, 4, 58)  (* : *)
  val () = buf_set_u8(p, 5, 116) (* t *)
  val () = buf_set_u8(p, 6, 105) (* i *)
  val () = buf_set_u8(p, 7, 116) (* t *)
  val () = buf_set_u8(p, 8, 108) (* l *)
  val () = buf_set_u8(p, 9, 101) (* e *)
  val () = buf_set_u8(p, 10, 62) (* > *)
in p end

(* "<dc:creator>" = 60 100 99 58 99 114 101 97 116 111 114 62 — 12 bytes *)
fn needle_dc_creator_open(): ptr = let
  val p = _calloc(1, 12)
  val () = buf_set_u8(p, 0, 60)  (* < *)
  val () = buf_set_u8(p, 1, 100) (* d *)
  val () = buf_set_u8(p, 2, 99)  (* c *)
  val () = buf_set_u8(p, 3, 58)  (* : *)
  val () = buf_set_u8(p, 4, 99)  (* c *)
  val () = buf_set_u8(p, 5, 114) (* r *)
  val () = buf_set_u8(p, 6, 101) (* e *)
  val () = buf_set_u8(p, 7, 97)  (* a *)
  val () = buf_set_u8(p, 8, 116) (* t *)
  val () = buf_set_u8(p, 9, 111) (* o *)
  val () = buf_set_u8(p, 10, 114)(* r *)
  val () = buf_set_u8(p, 11, 62) (* > *)
in p end

(* "</dc:creator>" = 60 47 100 99 58 99 114 101 97 116 111 114 62 — 13 bytes *)
fn needle_dc_creator_close(): ptr = let
  val p = _calloc(1, 13)
  val () = buf_set_u8(p, 0, 60)  (* < *)
  val () = buf_set_u8(p, 1, 47)  (* / *)
  val () = buf_set_u8(p, 2, 100) (* d *)
  val () = buf_set_u8(p, 3, 99)  (* c *)
  val () = buf_set_u8(p, 4, 58)  (* : *)
  val () = buf_set_u8(p, 5, 99)  (* c *)
  val () = buf_set_u8(p, 6, 114) (* r *)
  val () = buf_set_u8(p, 7, 101) (* e *)
  val () = buf_set_u8(p, 8, 97)  (* a *)
  val () = buf_set_u8(p, 9, 116) (* t *)
  val () = buf_set_u8(p, 10, 111)(* o *)
  val () = buf_set_u8(p, 11, 114)(* r *)
  val () = buf_set_u8(p, 12, 62) (* > *)
in p end

(* "<dc:identifier" = 60 100 99 58 105 100 101 110 116 105 102 105 101 114 — 14 bytes *)
fn needle_dc_identifier_open(): ptr = let
  val p = _calloc(1, 14)
  val () = buf_set_u8(p, 0, 60)  (* < *)
  val () = buf_set_u8(p, 1, 100) (* d *)
  val () = buf_set_u8(p, 2, 99)  (* c *)
  val () = buf_set_u8(p, 3, 58)  (* : *)
  val () = buf_set_u8(p, 4, 105) (* i *)
  val () = buf_set_u8(p, 5, 100) (* d *)
  val () = buf_set_u8(p, 6, 101) (* e *)
  val () = buf_set_u8(p, 7, 110) (* n *)
  val () = buf_set_u8(p, 8, 116) (* t *)
  val () = buf_set_u8(p, 9, 105) (* i *)
  val () = buf_set_u8(p, 10, 102)(* f *)
  val () = buf_set_u8(p, 11, 105)(* i *)
  val () = buf_set_u8(p, 12, 101)(* e *)
  val () = buf_set_u8(p, 13, 114)(* r *)
in p end

(* "</dc:identifier>" — 16 bytes *)
fn needle_dc_identifier_close(): ptr = let
  val p = _calloc(1, 16)
  val () = buf_set_u8(p, 0, 60)  (* < *)
  val () = buf_set_u8(p, 1, 47)  (* / *)
  val () = buf_set_u8(p, 2, 100) (* d *)
  val () = buf_set_u8(p, 3, 99)  (* c *)
  val () = buf_set_u8(p, 4, 58)  (* : *)
  val () = buf_set_u8(p, 5, 105) (* i *)
  val () = buf_set_u8(p, 6, 100) (* d *)
  val () = buf_set_u8(p, 7, 101) (* e *)
  val () = buf_set_u8(p, 8, 110) (* n *)
  val () = buf_set_u8(p, 9, 116) (* t *)
  val () = buf_set_u8(p, 10, 105)(* i *)
  val () = buf_set_u8(p, 11, 102)(* f *)
  val () = buf_set_u8(p, 12, 105)(* i *)
  val () = buf_set_u8(p, 13, 101)(* e *)
  val () = buf_set_u8(p, 14, 114)(* r *)
  val () = buf_set_u8(p, 15, 62) (* > *)
in p end

(* "<itemref " — 9 bytes *)
fn needle_itemref(): ptr = let
  val p = _calloc(1, 9)
  val () = buf_set_u8(p, 0, 60)  (* < *)
  val () = buf_set_u8(p, 1, 105) (* i *)
  val () = buf_set_u8(p, 2, 116) (* t *)
  val () = buf_set_u8(p, 3, 101) (* e *)
  val () = buf_set_u8(p, 4, 109) (* m *)
  val () = buf_set_u8(p, 5, 114) (* r *)
  val () = buf_set_u8(p, 6, 101) (* e *)
  val () = buf_set_u8(p, 7, 102) (* f *)
  val () = buf_set_u8(p, 8, 32)  (* space *)
in p end

(* "idref=\"" — 7 bytes *)
fn needle_idref(): ptr = let
  val p = _calloc(1, 7)
  val () = buf_set_u8(p, 0, 105) (* i *)
  val () = buf_set_u8(p, 1, 100) (* d *)
  val () = buf_set_u8(p, 2, 114) (* r *)
  val () = buf_set_u8(p, 3, 101) (* e *)
  val () = buf_set_u8(p, 4, 102) (* f *)
  val () = buf_set_u8(p, 5, 61)  (* = *)
  val () = buf_set_u8(p, 6, 34)  (* " *)
in p end

(* "<item " — 6 bytes *)
fn needle_item(): ptr = let
  val p = _calloc(1, 6)
  val () = buf_set_u8(p, 0, 60)  (* < *)
  val () = buf_set_u8(p, 1, 105) (* i *)
  val () = buf_set_u8(p, 2, 116) (* t *)
  val () = buf_set_u8(p, 3, 101) (* e *)
  val () = buf_set_u8(p, 4, 109) (* m *)
  val () = buf_set_u8(p, 5, 32)  (* space *)
in p end

(* " id=\"" — 5 bytes *)
fn needle_id(): ptr = let
  val p = _calloc(1, 5)
  val () = buf_set_u8(p, 0, 32)  (* space *)
  val () = buf_set_u8(p, 1, 105) (* i *)
  val () = buf_set_u8(p, 2, 100) (* d *)
  val () = buf_set_u8(p, 3, 61)  (* = *)
  val () = buf_set_u8(p, 4, 34)  (* " *)
in p end

(* "href=\"" — 6 bytes *)
fn needle_href(): ptr = let
  val p = _calloc(1, 6)
  val () = buf_set_u8(p, 0, 104) (* h *)
  val () = buf_set_u8(p, 1, 114) (* r *)
  val () = buf_set_u8(p, 2, 101) (* e *)
  val () = buf_set_u8(p, 3, 102) (* f *)
  val () = buf_set_u8(p, 4, 61)  (* = *)
  val () = buf_set_u8(p, 5, 34)  (* " *)
in p end

(* ========== "META-INF/container.xml" constant (22 bytes) ========== *)

(* Build once and cache as a module-level allocation *)
fn _build_str_container(): ptr = let
  val p = _calloc(1, 22)
  val () = buf_set_u8(p, 0, 77)  (* M *)
  val () = buf_set_u8(p, 1, 69)  (* E *)
  val () = buf_set_u8(p, 2, 84)  (* T *)
  val () = buf_set_u8(p, 3, 65)  (* A *)
  val () = buf_set_u8(p, 4, 45)  (* - *)
  val () = buf_set_u8(p, 5, 73)  (* I *)
  val () = buf_set_u8(p, 6, 78)  (* N *)
  val () = buf_set_u8(p, 7, 70)  (* F *)
  val () = buf_set_u8(p, 8, 47)  (* / *)
  val () = buf_set_u8(p, 9, 99)  (* c *)
  val () = buf_set_u8(p, 10, 111)(* o *)
  val () = buf_set_u8(p, 11, 110)(* n *)
  val () = buf_set_u8(p, 12, 116)(* t *)
  val () = buf_set_u8(p, 13, 97) (* a *)
  val () = buf_set_u8(p, 14, 105)(* i *)
  val () = buf_set_u8(p, 15, 110)(* n *)
  val () = buf_set_u8(p, 16, 101)(* e *)
  val () = buf_set_u8(p, 17, 114)(* r *)
  val () = buf_set_u8(p, 18, 46) (* . *)
  val () = buf_set_u8(p, 19, 120)(* x *)
  val () = buf_set_u8(p, 20, 109)(* m *)
  val () = buf_set_u8(p, 21, 108)(* l *)
in p end

(* ========== Scan forward to find closing quote ========== *)

fn _find_quote(data: ptr, len: int, start: int): int = let
  fun loop(i: int): int =
    if gte_int_int(i, len) then len
    else if eq_int_int(buf_get_u8(data, i), 34) then i (* 34 = '"' *)
    else loop(i + 1)
in loop(start) end

(* Scan forward to find closing '>' *)
fn _find_gt(data: ptr, len: int, start: int): int = let
  fun loop(i: int): int =
    if gte_int_int(i, len) then len
    else if eq_int_int(buf_get_u8(data, i), 62) then i (* 62 = '>' *)
    else loop(i + 1)
in loop(start) end

(* Copy bytes from src to dst *)
fn _copy_bytes(dst: ptr, dst_off: int, src: ptr, src_off: int, count: int): void = let
  fun loop(i: int): void =
    if lt_int_int(i, count) then let
      val () = buf_set_u8(dst, dst_off + i, buf_get_u8(src, src_off + i))
    in loop(i + 1) end
in loop(0) end

(* Compare bytes at two locations *)
fn _bytes_equal(a: ptr, a_off: int, b: ptr, b_off: int, count: int): bool = let
  fun loop(i: int): bool =
    if gte_int_int(i, count) then true
    else if neq_int_int(buf_get_u8(a, a_off + i), buf_get_u8(b, b_off + i)) then false
    else loop(i + 1)
in loop(0) end

(* ========== epub_init ========== *)

extern fun epub_init_impl(): void = "ext#epub_init"
implement epub_init_impl() = let
  val () = _app_set_epub_title_len(0)
  val () = _app_set_epub_author_len(0)
  val () = _app_set_epub_book_id_len(0)
  val () = _app_set_epub_opf_path_len(0)
  val () = _app_set_epub_opf_dir_len(0)
  val () = _app_set_epub_spine_count(0)
  val () = _app_set_epub_state(0)
  val () = _app_set_epub_spine_path_count(0)
  val () = _app_set_epub_spine_path_pos(0)
in end

(* ========== Simple accessors ========== *)

extern fun epub_get_state_impl(): int = "ext#epub_get_state"
implement epub_get_state_impl() = _app_epub_state()

extern fun epub_get_progress_impl(): int = "ext#epub_get_progress"
implement epub_get_progress_impl() = 0

extern fun epub_get_error_impl(buf_offset: int): int = "ext#epub_get_error"
implement epub_get_error_impl(_) = 0

extern fun epub_start_import_impl(fid: int): int = "ext#epub_start_import"
implement epub_start_import_impl(_) = 0

extern fun epub_get_title_impl(buf_offset: int): int = "ext#epub_get_title"
implement epub_get_title_impl(buf_offset) = let
  val tptr = _app_epub_title_ptr()
  val tlen = _app_epub_title_len()
  val sbuf = get_string_buffer_ptr()
  val () = _copy_bytes(sbuf, buf_offset, tptr, 0, tlen)
in tlen end

extern fun epub_get_author_impl(buf_offset: int): int = "ext#epub_get_author"
implement epub_get_author_impl(buf_offset) = let
  val aptr = _app_epub_author_ptr()
  val alen = _app_epub_author_len()
  val sbuf = get_string_buffer_ptr()
  val () = _copy_bytes(sbuf, buf_offset, aptr, 0, alen)
in alen end

extern fun epub_get_book_id_impl(buf_offset: int): int = "ext#epub_get_book_id"
implement epub_get_book_id_impl(buf_offset) = let
  val bptr = _app_epub_book_id_ptr()
  val blen = _app_epub_book_id_len()
  val sbuf = get_string_buffer_ptr()
  val () = _copy_bytes(sbuf, buf_offset, bptr, 0, blen)
in blen end

extern fun epub_get_chapter_count_impl(): int = "ext#epub_get_chapter_count"
implement epub_get_chapter_count_impl() = let
  val sc = _app_epub_spine_count()
in
  if lt_int_int(sc, 0) then 0
  else if gt_int_int(sc, 256) then 256
  else sc
end

extern fun epub_get_chapter_key_impl(ci: int, bo: int): int = "ext#epub_get_chapter_key"
implement epub_get_chapter_key_impl(_, _) = 0

extern fun epub_continue_impl(): void = "ext#epub_continue"
implement epub_continue_impl() = ()

extern fun epub_on_file_open_impl(h: int, s: int): void = "ext#epub_on_file_open"
implement epub_on_file_open_impl(_, _) = ()

extern fun epub_on_decompress_impl(bh: int, s: int): void = "ext#epub_on_decompress"
implement epub_on_decompress_impl(_, _) = ()

extern fun epub_on_db_open_impl(s: int): void = "ext#epub_on_db_open"
implement epub_on_db_open_impl(_) = ()

extern fun epub_on_db_put_impl(s: int): void = "ext#epub_on_db_put"
implement epub_on_db_put_impl(_) = ()

extern fun epub_cancel_impl(): void = "ext#epub_cancel"
implement epub_cancel_impl() = _app_set_epub_state(0)

(* TOC stubs *)
extern fun epub_get_toc_count_impl(): int = "ext#epub_get_toc_count"
implement epub_get_toc_count_impl() = 0

extern fun epub_get_toc_label_impl(ti: int, bo: int): int = "ext#epub_get_toc_label"
implement epub_get_toc_label_impl(_, _) = 0

extern fun epub_get_toc_chapter_impl(ti: int): int = "ext#epub_get_toc_chapter"
implement epub_get_toc_chapter_impl(_) = 0 - 1

extern fun epub_get_toc_level_impl(ti: int): int = "ext#epub_get_toc_level"
implement epub_get_toc_level_impl(_) = 0

extern fun epub_get_chapter_title_impl(si: int, bo: int): int = "ext#epub_get_chapter_title"
implement epub_get_chapter_title_impl(_, _) = 0

(* Serialization stubs *)
extern fun epub_serialize_metadata_impl(): int = "ext#epub_serialize_metadata"
implement epub_serialize_metadata_impl() = 0

extern fun epub_restore_metadata_impl(len: int): int = "ext#epub_restore_metadata"
implement epub_restore_metadata_impl(_) = 0

extern fun epub_reset_impl(): void = "ext#epub_reset"
implement epub_reset_impl() = epub_init_impl()

(* ========== epub_parse_container_bytes ========== *)

(* Parse container.xml to extract OPF path from full-path="..." attribute.
 * Stores path and directory prefix in app_state.
 * Returns 1 on success, 0 on failure. *)
extern fun epub_parse_container_bytes_impl(buf: ptr, len: int): int
  = "ext#epub_parse_container_bytes"

implement epub_parse_container_bytes_impl(buf, len) = let
  val ndl = needle_full_path() (* "full-path=\"" 11 bytes *)
  val pos0 = _find_bytes(buf, len, ndl, 11, 0)
in
  if lt_int_int(pos0, 0) then 0
  else let
    val pos = pos0 + 11
    val qend = _find_quote(buf, len, pos)
  in
    if gte_int_int(qend, len) then 0
    else let
      val path_len = qend - pos
    in
      if lte_int_int(path_len, 0) then 0
      else if gte_int_int(path_len, 256) then 0
      else let
        val opf_ptr = _app_epub_opf_path_ptr()
        val () = _copy_bytes(opf_ptr, 0, buf, pos, path_len)
        val () = _app_set_epub_opf_path_len(path_len)
        (* Extract directory prefix up to and including last '/' *)
        fun find_last_slash(i: int, last: int): int =
          if gte_int_int(i, path_len) then last
          else if eq_int_int(buf_get_u8(opf_ptr, i), 47) then find_last_slash(i + 1, i) (* 47 = '/' *)
          else find_last_slash(i + 1, last)
        val last_slash = find_last_slash(0, 0 - 1)
      in
        if gte_int_int(last_slash, 0) then
          _app_set_epub_opf_dir_len(last_slash + 1)
        else
          _app_set_epub_opf_dir_len(0)
        ;
        1
      end
    end
  end
end

(* ========== epub_parse_opf_bytes (split into sub-functions for V8 WASM) ========== *)

(* V8's WASM compiler crashes on very large functions (>2000 WAT lines).
 * The OPF parser is split into 5 separate functions so each generates
 * a reasonably-sized WASM function body. *)

extern fun _opf_extract_title(buf: ptr, len: int): void = "ext#"
implement _opf_extract_title(buf, len) = let
  val ndl_to = needle_dc_title_open()
  val ndl_tc = needle_dc_title_close()
  val pos_t = _find_bytes(buf, len, ndl_to, 10, 0)
in
  if gte_int_int(pos_t, 0) then let
    val tstart = pos_t + 10
    val tend = _find_bytes(buf, len, ndl_tc, 11, tstart)
  in
    if gte_int_int(tend, 0) then let
      val tlen0 = tend - tstart
      val tlen = if gt_int_int(tlen0, 255) then 255 else tlen0
      val tptr = _app_epub_title_ptr()
      val () = _copy_bytes(tptr, 0, buf, tstart, tlen)
    in _app_set_epub_title_len(tlen) end
  end
end

extern fun _opf_extract_author(buf: ptr, len: int): void = "ext#"
implement _opf_extract_author(buf, len) = let
  val ndl_co = needle_dc_creator_open()
  val ndl_cc = needle_dc_creator_close()
  val pos_c = _find_bytes(buf, len, ndl_co, 12, 0)
in
  if gte_int_int(pos_c, 0) then let
    val astart = pos_c + 12
    val aend = _find_bytes(buf, len, ndl_cc, 13, astart)
  in
    if gte_int_int(aend, 0) then let
      val alen0 = aend - astart
      val alen = if gt_int_int(alen0, 255) then 255 else alen0
      val aptr = _app_epub_author_ptr()
      val () = _copy_bytes(aptr, 0, buf, astart, alen)
    in _app_set_epub_author_len(alen) end
  end
end

extern fun _opf_extract_identifier(buf: ptr, len: int): void = "ext#"
implement _opf_extract_identifier(buf, len) = let
  val ndl_io = needle_dc_identifier_open()
  val ndl_ic = needle_dc_identifier_close()
  val pos_i = _find_bytes(buf, len, ndl_io, 14, 0)
in
  if gte_int_int(pos_i, 0) then let
    val gt_pos = _find_gt(buf, len, pos_i + 14)
  in
    if lt_int_int(gt_pos, len) then let
      val id_start = gt_pos + 1
      val id_end = _find_bytes(buf, len, ndl_ic, 16, id_start)
    in
      if gte_int_int(id_end, 0) then let
        val id_len0 = id_end - id_start
        val id_len = if gt_int_int(id_len0, 63) then 63 else id_len0
        val bptr = _app_epub_book_id_ptr()
        val () = _copy_bytes(bptr, 0, buf, id_start, id_len)
      in _app_set_epub_book_id_len(id_len) end
    end
  end
end

extern fun _opf_count_spine(buf: ptr, len: int): int = "ext#"
implement _opf_count_spine(buf, len) = let
  val ndl_ir = needle_itemref()
  fun count_spine(pos: int, cnt: int): int = let
    val found = _find_bytes(buf, len, ndl_ir, 9, pos)
  in
    if lt_int_int(found, 0) then cnt
    else count_spine(found + 9, cnt + 1)
  end
in count_spine(0, 0) end

extern fun _opf_resolve_spine(buf: ptr, len: int, spine_count: int): void = "ext#"
implement _opf_resolve_spine(buf, len, spine_count) = let
  val () = _app_set_epub_spine_path_count(0)
  val () = _app_set_epub_spine_path_pos(0)

  val ndl_ir = needle_itemref()
  val ndl_idref = needle_idref()
  val ndl_item = needle_item()
  val ndl_mid = needle_id()
  val ndl_href = needle_href()
  val opf_ptr = _app_epub_opf_path_ptr()
  val opf_dir_len = _app_epub_opf_dir_len()
  val sp_buf = _app_epub_spine_path_buf()
  val sp_offsets = _app_epub_spine_path_offsets()
  val sp_lens = _app_epub_spine_path_lens()

  fun resolve_spine(si: int, pos: int, sp_count: int, sp_pos: int): void = let
    fun done(): void = let
      val () = _app_set_epub_spine_path_count(sp_count)
      val () = _app_set_epub_spine_path_pos(sp_pos)
    in end
  in
    if gte_int_int(si, spine_count) then done()
    else if gte_int_int(si, 32) then done()
    else let
      val ir_pos = _find_bytes(buf, len, ndl_ir, 9, pos)
    in
      if lt_int_int(ir_pos, 0) then done()
      else let
        val idref_pos = _find_bytes(buf, len, ndl_idref, 7, ir_pos)
      in
        if lt_int_int(idref_pos, 0) then resolve_spine(si + 1, ir_pos + 9, sp_count, sp_pos)
        else if gt_int_int(idref_pos, ir_pos + 200) then resolve_spine(si + 1, ir_pos + 9, sp_count, sp_pos)
        else let
          val id_start = idref_pos + 7
          val id_end = _find_quote(buf, len, id_start)
          val idref_len = id_end - id_start
        in
          if lte_int_int(idref_len, 0) then resolve_spine(si + 1, ir_pos + 9, sp_count, sp_pos)
          else if gt_int_int(idref_len, 63) then resolve_spine(si + 1, ir_pos + 9, sp_count, sp_pos)
          else let
            fun find_item(item_pos: int): void = let
              val found_item = _find_bytes(buf, len, ndl_item, 6, item_pos)
            in
              if lt_int_int(found_item, 0) then
                resolve_spine(si + 1, ir_pos + 9, sp_count, sp_pos)
              else let
                val item_limit0 = found_item + 500
                val item_limit = if gt_int_int(item_limit0, len) then len else item_limit0
                val mid_pos = _find_bytes(buf, item_limit, ndl_mid, 5, found_item)
              in
                if lt_int_int(mid_pos, 0) then find_item(found_item + 6)
                else let
                  val mid_start = mid_pos + 5
                  val mid_end = _find_quote(buf, len, mid_start)
                  val mid_len = mid_end - mid_start
                in
                  if neq_int_int(mid_len, idref_len) then find_item(found_item + 6)
                  else if _bytes_equal(buf, mid_start, buf, id_start, idref_len) then let
                    val href_pos = _find_bytes(buf, item_limit, ndl_href, 6, found_item)
                  in
                    if lt_int_int(href_pos, 0) then
                      resolve_spine(si + 1, ir_pos + 9, sp_count, sp_pos)
                    else let
                      val href_start = href_pos + 6
                      val href_end = _find_quote(buf, len, href_start)
                      val href_len = href_end - href_start
                      val full_len = opf_dir_len + href_len
                    in
                      if lte_int_int(full_len, 0) then
                        resolve_spine(si + 1, ir_pos + 9, sp_count, sp_pos)
                      else if gt_int_int(full_len, 255) then
                        resolve_spine(si + 1, ir_pos + 9, sp_count, sp_pos)
                      else if gt_int_int(sp_pos + full_len, 4096) then
                        resolve_spine(si + 1, ir_pos + 9, sp_count, sp_pos)
                      else let
                        val () = _copy_bytes(sp_buf, sp_pos, opf_ptr, 0, opf_dir_len)
                        val () = _copy_bytes(sp_buf, sp_pos + opf_dir_len, buf, href_start, href_len)
                        val () = buf_set_i32(sp_offsets, sp_count, sp_pos)
                        val () = buf_set_i32(sp_lens, sp_count, full_len)
                      in
                        resolve_spine(si + 1, ir_pos + 9, sp_count + 1, sp_pos + full_len)
                      end
                    end
                  end
                  else find_item(found_item + 6)
                end
              end
            end
          in find_item(0) end
        end
      end
    end
  end

in resolve_spine(0, 0, 0, 0) end

extern fun epub_parse_opf_bytes_impl(buf: ptr, len: int): int
  = "ext#epub_parse_opf_bytes"

implement epub_parse_opf_bytes_impl(buf, len) = let
  val () = _opf_extract_title(buf, len)
  val () = _opf_extract_author(buf, len)
  val () = _opf_extract_identifier(buf, len)
  val spine_count = _opf_count_spine(buf, len)
  val () = _app_set_epub_spine_count(spine_count)
  val () = _opf_resolve_spine(buf, len, spine_count)
in
  _app_set_epub_state(8); (* EPUB_STATE_DONE *)
  spine_count
end

(* ========== OPF path and container string accessors ========== *)

extern fun epub_get_opf_path_ptr_impl(): ptr = "ext#epub_get_opf_path_ptr"
implement epub_get_opf_path_ptr_impl() = _app_epub_opf_path_ptr()

extern fun epub_get_opf_path_len_impl(): int = "ext#epub_get_opf_path_len"
implement epub_get_opf_path_len_impl() = _app_epub_opf_path_len()

extern fun get_str_container_ptr_impl(): ptr = "ext#get_str_container_ptr"
implement get_str_container_ptr_impl() = _build_str_container()

(* ========== Spine path accessors ========== *)

(* Null ptr and ptr arithmetic *)
extern fun _null_ptr(): ptr = "mac#quire_null_ptr"
extern fun _ptr_add(p: ptr, n: int): ptr = "mac#ptr_add_int"

extern fun epub_get_spine_path_ptr_impl(index: int): ptr = "ext#epub_get_spine_path_ptr"
implement epub_get_spine_path_ptr_impl(index) = let
  val count = _app_epub_spine_path_count()
in
  if lt_int_int(index, 0) then _null_ptr()
  else if gte_int_int(index, count) then _null_ptr()
  else let
    val buf = _app_epub_spine_path_buf()
    val offsets = _app_epub_spine_path_offsets()
    val off = buf_get_i32(offsets, index)
  in _ptr_add(buf, off) end
end

extern fun epub_get_spine_path_len_impl(index: int): int = "ext#epub_get_spine_path_len"
implement epub_get_spine_path_len_impl(index) = let
  val count = _app_epub_spine_path_count()
in
  if lt_int_int(index, 0) then 0
  else if gte_int_int(index, count) then 0
  else let
    val lens = _app_epub_spine_path_lens()
  in buf_get_i32(lens, index) end
end
