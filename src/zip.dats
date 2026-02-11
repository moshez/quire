(* zip.dats - ZIP file parser implementation — pure ATS2
 *
 * Parses ZIP central directory to enumerate entries.
 * All byte-level parsing done via ward_arr_get<byte>.
 * Entry storage kept in quire_runtime.c as module-private statics.
 *)

#define ATS_DYNLOADFLAG 0

#include "share/atspre_staload.hats"
staload "./zip.sats"
staload "./app_state.sats"
staload "./../vendor/ward/lib/memory.sats"
staload "./../vendor/ward/lib/file.sats"
staload _ = "./../vendor/ward/lib/memory.dats"
staload _ = "./../vendor/ward/lib/file.dats"

(* ========== Freestanding arithmetic ========== *)

extern fun add_int_int(a: int, b: int): int = "mac#quire_add"
extern fun sub_int_int(a: int, b: int): int = "mac#quire_sub"
extern fun gte_int_int(a: int, b: int): bool = "mac#quire_gte"
extern fun gt_int_int(a: int, b: int): bool = "mac#quire_gt"
extern fun eq_int_int(a: int, b: int): bool = "mac#quire_eq"
extern fun neq_int_int(a: int, b: int): bool = "mac#quire_neq"
extern fun bor(a: int, b: int): int = "mac#quire_bor"
extern fun bsl(a: int, b: int): int = "mac#quire_bsl"
overload + with add_int_int of 10
overload - with sub_int_int of 10

(* Bounds-checked byte read directly from ward_arr.
 * ward_arr erases to ptr at runtime; macro does the bounds check. *)
extern fun ward_arr_byte {l:agz}{n:pos}
  (arr: !ward_arr(byte, l, n), off: int, len: int n): int = "mac#_ward_arr_byte"

(* Runtime-checked positive: used after verifying x > 0 at runtime. *)
extern castfn _checked_pos(x: int): [n:pos] int n

(* Runtime-checked bounded count *)
extern castfn _checked_bounded(x: int): [n:nat | n <= 256] int n

(* ========== C storage accessors (quire_runtime.c) ========== *)

(* Array-backed storage stays in C — only arrays, not simple int globals *)
extern fun _zip_entry_file_handle(i: int): int = "mac#"
extern fun _zip_entry_name_offset(i: int): int = "mac#"
extern fun _zip_entry_name_len(i: int): int = "mac#"
extern fun _zip_entry_compression(i: int): int = "mac#"
extern fun _zip_entry_compressed_size(i: int): int = "mac#"
extern fun _zip_entry_uncompressed_size(i: int): int = "mac#"
extern fun _zip_entry_local_offset(i: int): int = "mac#"
extern fun _zip_name_char(off: int): int = "mac#"
extern fun _zip_name_buf_put(off: int, byte_val: int): int = "mac#"

(* Store entry at a specific index — caller manages count via app_state *)
extern fun _zip_store_entry_at(idx: int, fh: int, no: int, nl: int,
  comp: int, cs: int, us: int, lo: int): int = "mac#"

extern fun quire_get_byte(p: ptr, off: int): int = "mac#"

(* ========== App state wrappers for ZIP int fields ========== *)

fn _get_zip_count(): int = let
  val st = app_state_load()
  val c = app_get_zip_entry_count(st)
  val () = app_state_store(st)
in c end

fn _set_zip_count(v: int): void = let
  val st = app_state_load()
  val () = app_set_zip_entry_count(st, v)
  val () = app_state_store(st)
in end

fn _get_zip_handle(): int = let
  val st = app_state_load()
  val h = app_get_zip_file_handle(st)
  val () = app_state_store(st)
in h end

fn _set_zip_handle(h: int): void = let
  val st = app_state_load()
  val () = app_set_zip_file_handle(st, h)
  val () = app_state_store(st)
in end

fn _get_zip_name_off(): int = let
  val st = app_state_load()
  val o = app_get_zip_name_offset(st)
  val () = app_state_store(st)
in o end

fn _advance_zip_name(n: int): void = let
  val st = app_state_load()
  val o = app_get_zip_name_offset(st)
  val () = app_set_zip_name_offset(st, o + n)
  val () = app_state_store(st)
in end

fn _zip_reset_state(): void = let
  val st = app_state_load()
  val () = app_set_zip_entry_count(st, 0)
  val () = app_set_zip_file_handle(st, 0)
  val () = app_set_zip_name_offset(st, 0)
  val () = app_state_store(st)
in end

(* ========== ZIP signature constants ========== *)

#define EOCD_SIG  101010256  (* 0x06054b50 *)
#define CD_SIG     33639248  (* 0x02014b50 *)
#define LOCAL_SIG  67324752  (* 0x04034b50 *)

(* ========== Multi-byte reading from ward_arr ========== *)

fn arr_u16 {l:agz}{n:pos}
  (arr: !ward_arr(byte, l, n), off: int, len: int n): int = let
  val b0 = ward_arr_byte(arr, off, len)
  val b1 = ward_arr_byte(arr, off + 1, len)
in bor(b0, bsl(b1, 8)) end

fn arr_u32 {l:agz}{n:pos}
  (arr: !ward_arr(byte, l, n), off: int, len: int n): int = let
  val b0 = ward_arr_byte(arr, off, len)
  val b1 = ward_arr_byte(arr, off + 1, len)
  val b2 = ward_arr_byte(arr, off + 2, len)
  val b3 = ward_arr_byte(arr, off + 3, len)
in bor(bor(b0, bsl(b1, 8)), bor(bsl(b2, 16), bsl(b3, 24))) end

(* ========== ZIP parsing functions (pure ATS2) ========== *)

(* Find EOCD by searching backwards. Returns file offset or -1. *)
fn find_eocd {l:agz}{n:pos}
  (arr: !ward_arr(byte, l, n), read_len: int n, search_start: int): int = let
  fun loop {l:agz}{n:pos}
    (arr: !ward_arr(byte, l, n), i: int, len: int n, ss: int): int =
    if gt_int_int(0, i) then 0 - 1
    else if eq_int_int(arr_u32(arr, i, len), EOCD_SIG) then ss + i
    else loop(arr, i - 1, len, ss)
in
  if gt_int_int(22, read_len) then 0 - 1
  else loop(arr, read_len - 22, read_len, search_start)
end

(* Parse EOCD. Returns (cd_offset, entry_count) or (-1, 0). *)
fn parse_eocd {l:agz}{n:pos}
  (arr: !ward_arr(byte, l, n), read_len: int n): @(int, int) =
  if gt_int_int(22, read_len) then @(0 - 1, 0)
  else if neq_int_int(arr_u32(arr, 0, read_len), EOCD_SIG) then @(0 - 1, 0)
  else @(arr_u32(arr, 16, read_len), arr_u16(arr, 10, read_len))

(* Parse one CD entry from buffer. Stores via C storage if valid.
 * Returns total header size or 0 on error. *)
fn parse_cd_entry {l:agz}{n:pos}
  (arr: !ward_arr(byte, l, n), read_len: int n, file_handle: int): int =
  if gt_int_int(46, read_len) then 0
  else if neq_int_int(arr_u32(arr, 0, read_len), CD_SIG) then 0
  else let
    val compression = arr_u16(arr, 10, read_len)
    val compressed_size = arr_u32(arr, 20, read_len)
    val uncompressed_size = arr_u32(arr, 24, read_len)
    val name_len = arr_u16(arr, 28, read_len)
    val extra_len = arr_u16(arr, 30, read_len)
    val comment_len = arr_u16(arr, 32, read_len)
    val local_offset = arr_u32(arr, 42, read_len)
    val name_buf_off = _get_zip_name_off()
    val entry_count = _get_zip_count()
  in
    if gt_int_int(1, name_len) then 46 + extra_len + comment_len
    else if gte_int_int(name_buf_off + name_len, 8192) then
      46 + name_len + extra_len + comment_len
    else if gte_int_int(entry_count, 256) then
      46 + name_len + extra_len + comment_len
    else if gt_int_int(46 + name_len, read_len) then
      46 + name_len + extra_len + comment_len
    else let
      (* Copy name bytes from arr to name buffer *)
      fun copy_name {l:agz}{n:pos}
        (arr: !ward_arr(byte, l, n), j: int, nlen: int,
         dest_off: int, alen: int n): void =
        if gte_int_int(j, nlen) then ()
        else let
          val b = ward_arr_byte(arr, 46 + j, alen)
          val _ = _zip_name_buf_put(dest_off + j, b)
        in copy_name(arr, j + 1, nlen, dest_off, alen) end
      val () = copy_name(arr, 0, name_len, name_buf_off, read_len)
      val _ = _zip_store_entry_at(entry_count, file_handle, name_buf_off,
                name_len, compression, compressed_size, uncompressed_size,
                local_offset)
      val () = _set_zip_count(entry_count + 1)
      val () = _advance_zip_name(name_len)
    in 46 + name_len + extra_len + comment_len end
  end

(* Parse local file header. Returns data offset or -1. *)
fn parse_local_header {l:agz}{n:pos}
  (arr: !ward_arr(byte, l, n), read_len: int n, local_offset: int): int =
  if gt_int_int(30, read_len) then 0 - 1
  else if neq_int_int(arr_u32(arr, 0, read_len), LOCAL_SIG) then 0 - 1
  else let
    val name_len = arr_u16(arr, 26, read_len)
    val extra_len = arr_u16(arr, 28, read_len)
  in local_offset + 30 + name_len + extra_len end

(* ========== Public API implementations ========== *)

implement zip_init() = _zip_reset_state()

implement zip_open(file_handle, file_size) = let
  val () = zip_init()
  val () = _set_zip_handle(file_handle)
  val search_size = (if file_size < 65558 then file_size else 65558): int
in
  if gt_int_int(1, search_size) then _checked_bounded(0)
  else let
    val search_start = file_size - search_size
    val sz = _checked_pos(search_size)
    val buf = ward_arr_alloc<byte>(sz)
    val _read_len = ward_file_read(file_handle, search_start, buf, sz)
    val eocd_file_offset = find_eocd(buf, sz, search_start)
    val () = ward_arr_free<byte>(buf)
  in
    if gt_int_int(0, eocd_file_offset) then _checked_bounded(0)
    else let
      val arr2 = ward_arr_alloc<byte>(22)
      val eocd_len = ward_file_read(file_handle, eocd_file_offset, arr2, 22)
      val @(cd_offset, expected_count) = parse_eocd(arr2, 22)
      val () = ward_arr_free<byte>(arr2)
    in
      if gt_int_int(0, cd_offset) then _checked_bounded(0)
      else let
        fun loop(handle: int, offset: int, remaining: int): void =
          if gt_int_int(1, remaining) then ()
          else if gte_int_int(_get_zip_count(), 256) then ()
          else let
            val arr3 = ward_arr_alloc<byte>(512)
            val rlen = ward_file_read(handle, offset, arr3, 512)
            val entry_size = parse_cd_entry(arr3, 512, handle)
            val () = ward_arr_free<byte>(arr3)
          in
            if gt_int_int(1, entry_size) then ()
            else loop(handle, offset + entry_size, remaining - 1)
          end
        val () = loop(file_handle, cd_offset, expected_count)
      in _checked_bounded(_get_zip_count()) end
    end
  end
end

implement zip_get_entry(index, entry) = let
  val count = _get_zip_count()
  fun set_default(entry: &zip_entry? >> zip_entry): void =
    entry := @{
      file_handle = 0, name_offset = 0, name_len = 0,
      compression = 0, compressed_size = 0, uncompressed_size = 0,
      local_header_offset = 0
    }
in
  if gt_int_int(0, index) then let val () = set_default(entry) in 0 end
  else if gte_int_int(index, count) then let val () = set_default(entry) in 0 end
  else let
    val () = entry := @{
      file_handle = _zip_entry_file_handle(index),
      name_offset = _zip_entry_name_offset(index),
      name_len = _zip_entry_name_len(index),
      compression = _zip_entry_compression(index),
      compressed_size = _zip_entry_compressed_size(index),
      uncompressed_size = _zip_entry_uncompressed_size(index),
      local_header_offset = _zip_entry_local_offset(index)
    }
  in 1 end
end

implement zip_get_entry_name(index, buf_offset) = let
  val count = _get_zip_count()
  extern castfn _to_nat(x: int): [n:nat] int n
in
  if gt_int_int(0, index) then _to_nat(0)
  else if gte_int_int(index, count) then _to_nat(0)
  else _to_nat(_zip_entry_name_len(index))
end

implement zip_entry_name_ends_with(index, suffix_ptr, suffix_len) = let
  val count = _get_zip_count()
in
  if gt_int_int(0, index) then 0
  else if gte_int_int(index, count) then 0
  else let
    val name_len = _zip_entry_name_len(index)
  in
    if gt_int_int(suffix_len, name_len) then 0
    else let
      val name_off = _zip_entry_name_offset(index)
      val start = name_len - suffix_len

      fun cmp(i: int): int =
        if gte_int_int(i, suffix_len) then 1
        else let
          val c1 = _zip_name_char(name_off + start + i)
          val c2 = quire_get_byte(suffix_ptr, i)
          (* Case-insensitive *)
          val c1 = (if gte_int_int(c1, 65) then
            (if gt_int_int(91, c1) then c1 + 32 else c1) else c1): int
          val c2 = (if gte_int_int(c2, 65) then
            (if gt_int_int(91, c2) then c2 + 32 else c2) else c2): int
        in
          if eq_int_int(c1, c2) then cmp(i + 1) else 0
        end
    in cmp(0) end
  end
end

implement zip_entry_name_equals(index, name_ptr, name_len) = let
  val count = _get_zip_count()
in
  if gt_int_int(0, index) then 0
  else if gte_int_int(index, count) then 0
  else let
    val entry_name_len = _zip_entry_name_len(index)
  in
    if neq_int_int(entry_name_len, name_len) then 0
    else let
      val name_off = _zip_entry_name_offset(index)
      fun cmp(i: int): int =
        if gte_int_int(i, name_len) then 1
        else let
          val c1 = _zip_name_char(name_off + i)
          val c2 = quire_get_byte(name_ptr, i)
        in
          if eq_int_int(c1, c2) then cmp(i + 1) else 0
        end
    in cmp(0) end
  end
end

implement zip_find_entry(name_ptr, name_len) = let
  val count = _get_zip_count()
  fun search(i: int): int =
    if gte_int_int(i, count) then 0 - 1
    else if gt_int_int(zip_entry_name_equals(i, name_ptr, name_len), 0) then i
    else search(i + 1)
in search(0) end

implement zip_get_data_offset(index) = let
  val count = _get_zip_count()
in
  if gt_int_int(0, index) then 0 - 1
  else if gte_int_int(index, count) then 0 - 1
  else let
    val local_off = _zip_entry_local_offset(index)
    val handle = _zip_entry_file_handle(index)
    val arr = ward_arr_alloc<byte>(30)
    val rlen = ward_file_read(handle, local_off, arr, 30)
    val result = parse_local_header(arr, 30, local_off)
    val () = ward_arr_free<byte>(arr)
  in result end
end

implement zip_get_entry_count() =
  _checked_bounded(_get_zip_count())

implement zip_close() = zip_init()
