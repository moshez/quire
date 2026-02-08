(* zip.dats - ZIP file parser implementation
 *
 * Parses ZIP central directory to enumerate entries.
 * Uses ward_file_read for synchronous chunk reads into ward_arr buffers.
 *
 * Internal state (entries array, name buffer) kept as C statics since
 * they are fixed-size module-private data. The public ATS API provides
 * the type-safe interface.
 *)

#define ATS_DYNLOADFLAG 0

#include "share/atspre_staload.hats"
staload "zip.sats"
staload "./../vendor/ward/lib/memory.sats"
staload "./../vendor/ward/lib/file.sats"
staload _ = "./../vendor/ward/lib/memory.dats"
staload _ = "./../vendor/ward/lib/file.dats"

(* ========== C internals ========== *)

%{
/* ZIP file parsing — internal C implementation
 *
 * ZIP format (simplified for EPUB):
 * - End of Central Directory (EOCD) at end of file: signature 0x06054b50
 * - Central Directory: list of file headers
 * - Local file headers + compressed data throughout file
 *
 * Strategy:
 * 1. Find EOCD by searching backwards from end of file
 * 2. Parse EOCD to get central directory offset
 * 3. Parse central directory to build entry list
 * 4. For each entry, data offset = local_header_offset + local_header_size
 */

/* Maximum entries we can handle */
#define MAX_ZIP_ENTRIES 256

/* ZIP signatures */
#define EOCD_SIGNATURE 0x06054b50u
#define CD_SIGNATURE   0x02014b50u
#define LOCAL_SIGNATURE 0x04034b50u

/* Entry storage */
typedef struct {
    int file_handle;
    int name_offset;
    int name_len;
    int compression;
    int compressed_size;
    int uncompressed_size;
    int local_header_offset;
} zip_entry_t;

static zip_entry_t _zip_entries[MAX_ZIP_ENTRIES];
static int _zip_entry_count = 0;
static int _zip_file_handle = 0;

/* Name buffer - stores all entry names concatenated */
#define NAME_BUFFER_SIZE 8192
static char _zip_name_buffer[NAME_BUFFER_SIZE];
static int _zip_name_offset = 0;

/* Read buffer - ward_arr ptr stashed here for C access */
static unsigned char *_zip_read_buf = 0;
static int _zip_read_buf_len = 0;

void _zip_set_buf(void *p, int len) {
    _zip_read_buf = (unsigned char *)p;
    _zip_read_buf_len = len;
}

/* Read uint16 little-endian from internal buffer at offset */
static int _zip_u16(int off) {
    if (off + 1 >= _zip_read_buf_len) return 0;
    return (int)_zip_read_buf[off] | ((int)_zip_read_buf[off+1] << 8);
}

/* Read uint32 little-endian from internal buffer at offset */
static unsigned int _zip_u32(int off) {
    if (off + 3 >= _zip_read_buf_len) return 0;
    return (unsigned int)_zip_read_buf[off]
         | ((unsigned int)_zip_read_buf[off+1] << 8)
         | ((unsigned int)_zip_read_buf[off+2] << 16)
         | ((unsigned int)_zip_read_buf[off+3] << 24);
}

/* Find EOCD record by searching backwards.
 * Assumes _zip_read_buf has been filled with the search region.
 * read_len = bytes in buffer, search_start = file offset of buffer start.
 * Returns file offset of EOCD or -1. */
int _zip_find_eocd(int read_len, int search_start) {
    if (read_len <= 22) return -1;
    for (int i = read_len - 22; i >= 0; i--) {
        if (_zip_u32(i) == EOCD_SIGNATURE) {
            return search_start + i;
        }
    }
    return -1;
}

/* Parse EOCD from buffer (must be at offset 0 in _zip_read_buf).
 * Returns CD offset, writes entry count to *out_count. */
int _zip_parse_eocd(int read_len, int *out_count) {
    if (read_len < 22) return -1;
    if (_zip_u32(0) != EOCD_SIGNATURE) return -1;
    *out_count = _zip_u16(10);
    return (int)_zip_u32(16);
}

/* Parse one central directory entry from buffer at offset 0.
 * Stores entry in _zip_entries[_zip_entry_count] if valid.
 * Returns total header size (46 + name + extra + comment) or 0 on error. */
int _zip_parse_cd_entry(int read_len, int file_handle) {
    if (read_len < 46) return 0;
    if (_zip_u32(0) != CD_SIGNATURE) return 0;

    int compression = _zip_u16(10);
    int compressed_size = (int)_zip_u32(20);
    int uncompressed_size = (int)_zip_u32(24);
    int name_len = _zip_u16(28);
    int extra_len = _zip_u16(30);
    int comment_len = _zip_u16(32);
    int local_offset = (int)_zip_u32(42);

    /* Copy name from buffer at offset 46 into name buffer */
    if (name_len > 0 && _zip_name_offset + name_len < NAME_BUFFER_SIZE
        && _zip_entry_count < MAX_ZIP_ENTRIES && read_len >= 46 + name_len) {
        for (int j = 0; j < name_len; j++) {
            _zip_name_buffer[_zip_name_offset + j] = _zip_read_buf[46 + j];
        }

        _zip_entries[_zip_entry_count].file_handle = file_handle;
        _zip_entries[_zip_entry_count].name_offset = _zip_name_offset;
        _zip_entries[_zip_entry_count].name_len = name_len;
        _zip_entries[_zip_entry_count].compression = compression;
        _zip_entries[_zip_entry_count].compressed_size = compressed_size;
        _zip_entries[_zip_entry_count].uncompressed_size = uncompressed_size;
        _zip_entries[_zip_entry_count].local_header_offset = local_offset;

        _zip_entry_count++;
        _zip_name_offset += name_len;
    }

    return 46 + name_len + extra_len + comment_len;
}

/* Get data offset by parsing local header.
 * Assumes _zip_read_buf has local header (30 bytes). */
int _zip_local_data_offset(int local_offset, int read_len) {
    if (read_len < 30) return -1;
    if (_zip_u32(0) != LOCAL_SIGNATURE) return -1;
    int name_len = _zip_u16(26);
    int extra_len = _zip_u16(28);
    return local_offset + 30 + name_len + extra_len;
}

/* Entry accessors for ATS */
int _zip_get_entry_count(void) { return _zip_entry_count; }
int _zip_get_file_handle(void) { return _zip_file_handle; }

int _zip_entry_file_handle(int i) { return _zip_entries[i].file_handle; }
int _zip_entry_name_offset(int i) { return _zip_entries[i].name_offset; }
int _zip_entry_name_len(int i) { return _zip_entries[i].name_len; }
int _zip_entry_compression(int i) { return _zip_entries[i].compression; }
int _zip_entry_compressed_size(int i) { return _zip_entries[i].compressed_size; }
int _zip_entry_uncompressed_size(int i) { return _zip_entries[i].uncompressed_size; }
int _zip_entry_local_offset(int i) { return _zip_entries[i].local_header_offset; }

char _zip_name_char(int off) { return _zip_name_buffer[off]; }

void _zip_reset(void) {
    _zip_entry_count = 0;
    _zip_name_offset = 0;
    _zip_file_handle = 0;
}

void _zip_set_file_handle(int h) {
    _zip_file_handle = h;
}
%}

(* ========== C function declarations ========== *)

extern fun _zip_set_buf(p: ptr, len: int): void = "mac#"
extern fun _zip_find_eocd(read_len: int, search_start: int): int = "mac#"
extern fun _zip_parse_eocd(read_len: int, out_count: &int? >> int): int = "mac#"
extern fun _zip_parse_cd_entry(read_len: int, file_handle: int): int = "mac#"
extern fun _zip_local_data_offset(local_offset: int, read_len: int): int = "mac#"

extern fun _zip_get_entry_count(): int = "mac#"
extern fun _zip_get_file_handle(): int = "mac#"
extern fun _zip_reset(): void = "mac#"
extern fun _zip_set_file_handle(h: int): void = "mac#"

extern fun _zip_entry_file_handle(i: int): int = "mac#"
extern fun _zip_entry_name_offset(i: int): int = "mac#"
extern fun _zip_entry_name_len(i: int): int = "mac#"
extern fun _zip_entry_compression(i: int): int = "mac#"
extern fun _zip_entry_compressed_size(i: int): int = "mac#"
extern fun _zip_entry_uncompressed_size(i: int): int = "mac#"
extern fun _zip_entry_local_offset(i: int): int = "mac#"
extern fun _zip_name_char(off: int): int = "mac#"

(* Castfns for dependent return types *)
extern castfn _to_nat(x: int): [n:nat] int n
extern castfn _to_bounded(x: int): [n:nat | n <= 256] int n

(* ========== Helper: read file chunk into ward_arr ========== *)

(* Allocate a ward_arr, read file data into it, stash ptr for C access,
 * and return bytes_read. Caller must free the arr when done. *)
fn zip_read_chunk
  (handle: int, offset: int, len: int)
  : @(int(*bytes_read*), [l:agz] ward_arr(byte, l, 1)) = let
  extern castfn _to_pos(x: int): [n:pos] int n
  val alloc_len = (if len > 0 then len else 1): int
  val alloc_pos = _to_pos(alloc_len)
  val arr = ward_arr_alloc<byte>(alloc_pos)
  val p = $UNSAFE.castvwtp1{ptr}(arr)
  val () = _zip_set_buf(p, alloc_len)
  val bytes = ward_file_read(handle, offset, arr, alloc_pos)
  (* Re-stash after read in case ptr changed — shouldn't, but safe *)
  val p2 = $UNSAFE.castvwtp1{ptr}(arr)
  val () = _zip_set_buf(p2, alloc_len)
in
  @(bytes, $UNSAFE.castvwtp0{[l:agz] ward_arr(byte, l, 1)}(arr))
end

(* Free a read buffer *)
fn zip_free_buf(arr: [l:agz] ward_arr(byte, l, 1)): void =
  ward_arr_free<byte>(arr)

(* ========== Public API implementations ========== *)

implement zip_init() = _zip_reset()

implement zip_open(file_handle, file_size) = let
  (* Reset state *)
  val () = zip_init()
  val () = _zip_set_file_handle(file_handle)

  (* Find EOCD: search last min(file_size, 65558) bytes *)
  val search_size = (if file_size < 65558 then file_size else 65558): int
  val search_start = file_size - search_size

  (* Read search region *)
  val @(read_len, buf) = zip_read_chunk(file_handle, search_start, search_size)
  val eocd_file_offset = _zip_find_eocd(read_len, search_start)
  val () = zip_free_buf(buf)
in
  if eocd_file_offset < 0 then _to_bounded(0)
  else let
    (* Read EOCD record *)
    val @(eocd_len, buf2) = zip_read_chunk(file_handle, eocd_file_offset, 22)
    var expected_count: int
    val cd_offset = _zip_parse_eocd(eocd_len, expected_count)
    val () = zip_free_buf(buf2)
  in
    if cd_offset < 0 then _to_bounded(0)
    else let
      (* Parse central directory entries one by one *)
      fun loop(handle: int, offset: int, remaining: int): void =
        if remaining <= 0 then ()
        else if _zip_get_entry_count() >= 256 then ()
        else let
          (* Read CD header + name (max ~512 bytes typical) *)
          val @(rlen, buf3) = zip_read_chunk(handle, offset, 512)
          val entry_size = _zip_parse_cd_entry(rlen, handle)
          val () = zip_free_buf(buf3)
        in
          if entry_size <= 0 then ()
          else loop(handle, offset + entry_size, remaining - 1)
        end

      val () = loop(file_handle, cd_offset, expected_count)
    in
      _to_bounded(_zip_get_entry_count())
    end
  end
end

implement zip_get_entry(index, entry) = let
  val count = _zip_get_entry_count()
  fun set_default(entry: &zip_entry? >> zip_entry): void =
    entry := @{
      file_handle = 0, name_offset = 0, name_len = 0,
      compression = 0, compressed_size = 0, uncompressed_size = 0,
      local_header_offset = 0
    }
in
  if index < 0 then let val () = set_default(entry) in 0 end
  else if index >= count then let val () = set_default(entry) in 0 end
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
  val count = _zip_get_entry_count()
in
  if index < 0 then _to_nat(0)
  else if index >= count then _to_nat(0)
  else _to_nat(_zip_entry_name_len(index))
end

implement zip_entry_name_ends_with(index, suffix_ptr, suffix_len) = let
  val count = _zip_get_entry_count()
in
  if index < 0 then 0
  else if index >= count then 0
  else let
    val name_len = _zip_entry_name_len(index)
  in
    if suffix_len > name_len then 0
    else let
      val name_off = _zip_entry_name_offset(index)
      val start = name_len - suffix_len

      fun cmp(i: int): int =
        if i >= suffix_len then 1
        else let
          extern fun _get_byte(p: ptr, off: int): int = "mac#quire_get_byte"
          val c1 = _zip_name_char(name_off + start + i)
          val c2 = _get_byte(suffix_ptr, i)
          (* Case-insensitive *)
          val c1 = (if c1 >= 65 then (if c1 <= 90 then c1 + 32 else c1) else c1): int
          val c2 = (if c2 >= 65 then (if c2 <= 90 then c2 + 32 else c2) else c2): int
        in
          if c1 = c2 then cmp(i + 1)
          else 0
        end
    in
      cmp(0)
    end
  end
end

implement zip_entry_name_equals(index, name_ptr, name_len) = let
  val count = _zip_get_entry_count()
in
  if index < 0 then 0
  else if index >= count then 0
  else let
    val entry_name_len = _zip_entry_name_len(index)
  in
    if entry_name_len != name_len then 0
    else let
      val name_off = _zip_entry_name_offset(index)

      fun cmp(i: int): int =
        if i >= name_len then 1
        else let
          extern fun _get_byte(p: ptr, off: int): int = "mac#quire_get_byte"
          val c1 = _zip_name_char(name_off + i)
          val c2 = _get_byte(name_ptr, i)
        in
          if c1 = c2 then cmp(i + 1)
          else 0
        end
    in
      cmp(0)
    end
  end
end

implement zip_find_entry(name_ptr, name_len) = let
  val count = _zip_get_entry_count()

  fun search(i: int): int =
    if i >= count then 0 - 1
    else if zip_entry_name_equals(i, name_ptr, name_len) > 0 then i
    else search(i + 1)
in
  search(0)
end

implement zip_get_data_offset(index) = let
  val count = _zip_get_entry_count()
in
  if index < 0 then 0 - 1
  else if index >= count then 0 - 1
  else let
    val local_off = _zip_entry_local_offset(index)
    val handle = _zip_entry_file_handle(index)
    val @(rlen, buf) = zip_read_chunk(handle, local_off, 30)
    val result = _zip_local_data_offset(local_off, rlen)
    val () = zip_free_buf(buf)
  in
    result
  end
end

implement zip_get_entry_count() =
  _to_bounded(_zip_get_entry_count())

implement zip_close() = zip_init()
