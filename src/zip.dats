(* zip.dats - ZIP file parser implementation
 *
 * Parses ZIP central directory to enumerate entries.
 * Uses js_file_read_chunk from bridge to read file data.
 *)

#define ATS_DYNLOADFLAG 0

staload "zip.sats"

%{^
/* ZIP file parsing implementation
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

#include <stdint.h>

extern unsigned char* get_fetch_buffer_ptr(void);
extern unsigned char* get_string_buffer_ptr(void);

/* Bridge import for reading file chunks */
extern int js_file_read_chunk(int handle, int offset, int length);

/* Maximum entries we can handle */
#define MAX_ZIP_ENTRIES 256

/* ZIP signatures */
#define EOCD_SIGNATURE 0x06054b50
#define CD_SIGNATURE   0x02014b50
#define LOCAL_SIGNATURE 0x04034b50

/* Entry storage */
typedef struct {
    int file_handle;
    int name_offset;        /* offset in our name buffer */
    int name_len;
    int compression;
    int compressed_size;
    int uncompressed_size;
    int local_header_offset;
} zip_entry_t;

static zip_entry_t entries[MAX_ZIP_ENTRIES];
static int entry_count = 0;
static int current_file_handle = 0;

/* Name buffer - stores all entry names concatenated */
#define NAME_BUFFER_SIZE 8192
static char name_buffer[NAME_BUFFER_SIZE];
static int name_buffer_offset = 0;

/* Read uint16 little-endian from buffer */
static uint16_t read_u16(const unsigned char* buf) {
    return (uint16_t)buf[0] | ((uint16_t)buf[1] << 8);
}

/* Read uint32 little-endian from buffer */
static uint32_t read_u32(const unsigned char* buf) {
    return (uint32_t)buf[0] | ((uint32_t)buf[1] << 8) |
           ((uint32_t)buf[2] << 16) | ((uint32_t)buf[3] << 24);
}

/* Find EOCD record by searching backwards
 * Returns offset of EOCD or -1 if not found */
static int find_eocd(int file_handle, int file_size) {
    unsigned char* buf = get_fetch_buffer_ptr();

    /* EOCD is at least 22 bytes, search in last 64KB + 22 bytes */
    int search_size = file_size < 65558 ? file_size : 65558;
    int search_start = file_size - search_size;

    /* Read the search region */
    int read_len = js_file_read_chunk(file_handle, search_start, search_size);
    if (read_len <= 22) return -1;

    /* Search backwards for EOCD signature */
    for (int i = read_len - 22; i >= 0; i--) {
        if (read_u32(buf + i) == EOCD_SIGNATURE) {
            return search_start + i;
        }
    }
    return -1;
}

/* Parse EOCD record and return central directory offset */
static int parse_eocd(int file_handle, int eocd_offset, int* out_entry_count) {
    unsigned char* buf = get_fetch_buffer_ptr();

    /* Read EOCD record (22 bytes minimum) */
    int read_len = js_file_read_chunk(file_handle, eocd_offset, 22);
    if (read_len < 22) return -1;

    /* Verify signature */
    if (read_u32(buf) != EOCD_SIGNATURE) return -1;

    /* EOCD layout:
     * +0: signature (4)
     * +4: disk number (2)
     * +6: disk with CD (2)
     * +8: entries on disk (2)
     * +10: total entries (2)
     * +12: CD size (4)
     * +16: CD offset (4)
     * +20: comment length (2)
     */
    *out_entry_count = read_u16(buf + 10);
    return (int)read_u32(buf + 16);
}

/* Parse central directory entries */
static int parse_central_directory(int file_handle, int cd_offset, int expected_count) {
    unsigned char* buf = get_fetch_buffer_ptr();
    int offset = cd_offset;

    entry_count = 0;
    name_buffer_offset = 0;

    for (int i = 0; i < expected_count && entry_count < MAX_ZIP_ENTRIES; i++) {
        /* Read central directory file header (46 bytes minimum) */
        int read_len = js_file_read_chunk(file_handle, offset, 46);
        if (read_len < 46) break;

        /* Verify signature */
        if (read_u32(buf) != CD_SIGNATURE) break;

        /* CD header layout:
         * +0: signature (4)
         * +4: version made by (2)
         * +6: version needed (2)
         * +8: flags (2)
         * +10: compression (2)
         * +12: mod time (2)
         * +14: mod date (2)
         * +16: crc32 (4)
         * +20: compressed size (4)
         * +24: uncompressed size (4)
         * +28: file name length (2)
         * +30: extra field length (2)
         * +32: comment length (2)
         * +34: disk number (2)
         * +36: internal attrs (2)
         * +38: external attrs (4)
         * +42: local header offset (4)
         */
        int compression = read_u16(buf + 10);
        int compressed_size = (int)read_u32(buf + 20);
        int uncompressed_size = (int)read_u32(buf + 24);
        int name_len = read_u16(buf + 28);
        int extra_len = read_u16(buf + 30);
        int comment_len = read_u16(buf + 32);
        int local_offset = (int)read_u32(buf + 42);

        /* Read filename */
        if (name_len > 0 && name_buffer_offset + name_len < NAME_BUFFER_SIZE) {
            read_len = js_file_read_chunk(file_handle, offset + 46, name_len);
            if (read_len >= name_len) {
                for (int j = 0; j < name_len; j++) {
                    name_buffer[name_buffer_offset + j] = buf[j];
                }

                /* Store entry */
                entries[entry_count].file_handle = file_handle;
                entries[entry_count].name_offset = name_buffer_offset;
                entries[entry_count].name_len = name_len;
                entries[entry_count].compression = compression;
                entries[entry_count].compressed_size = compressed_size;
                entries[entry_count].uncompressed_size = uncompressed_size;
                entries[entry_count].local_header_offset = local_offset;

                entry_count++;
                name_buffer_offset += name_len;
            }
        }

        /* Move to next entry */
        offset += 46 + name_len + extra_len + comment_len;
    }

    return entry_count;
}

/* Get data offset by reading local file header to determine its size */
static int get_data_offset_impl(int index) {
    if (index < 0 || index >= entry_count) return -1;

    unsigned char* buf = get_fetch_buffer_ptr();
    int local_offset = entries[index].local_header_offset;

    /* Read local file header (30 bytes minimum) */
    int read_len = js_file_read_chunk(entries[index].file_handle, local_offset, 30);
    if (read_len < 30) return -1;

    /* Verify signature */
    if (read_u32(buf) != LOCAL_SIGNATURE) return -1;

    /* Local header layout:
     * +0: signature (4)
     * +4: version needed (2)
     * +6: flags (2)
     * +8: compression (2)
     * +10: mod time (2)
     * +12: mod date (2)
     * +14: crc32 (4)
     * +18: compressed size (4)
     * +22: uncompressed size (4)
     * +26: file name length (2)
     * +28: extra field length (2)
     */
    int name_len = read_u16(buf + 26);
    int extra_len = read_u16(buf + 28);

    return local_offset + 30 + name_len + extra_len;
}

/* Public API */

void zip_init(void) {
    entry_count = 0;
    name_buffer_offset = 0;
    current_file_handle = 0;
}

int zip_open(int file_handle, int file_size) {
    zip_init();
    current_file_handle = file_handle;

    /* Find EOCD */
    int eocd_offset = find_eocd(file_handle, file_size);
    if (eocd_offset < 0) return 0;

    /* Parse EOCD to get CD location */
    int expected_count = 0;
    int cd_offset = parse_eocd(file_handle, eocd_offset, &expected_count);
    if (cd_offset < 0) return 0;

    /* Parse central directory */
    return parse_central_directory(file_handle, cd_offset, expected_count);
}

int zip_get_entry(int index, void* entry_ptr) {
    if (index < 0 || index >= entry_count) return 0;

    /* Copy entry data to output struct
     * Layout matches zip_entry typedef in ATS */
    int* out = (int*)entry_ptr;
    out[0] = entries[index].file_handle;
    out[1] = entries[index].name_offset;
    out[2] = entries[index].name_len;
    out[3] = entries[index].compression;
    out[4] = entries[index].compressed_size;
    out[5] = entries[index].uncompressed_size;
    out[6] = entries[index].local_header_offset;

    return 1;
}

int zip_get_entry_name(int index, int buf_offset) {
    if (index < 0 || index >= entry_count) return 0;

    unsigned char* buf = get_string_buffer_ptr();
    int name_offset = entries[index].name_offset;
    int name_len = entries[index].name_len;

    for (int i = 0; i < name_len && buf_offset + i < 4096; i++) {
        buf[buf_offset + i] = name_buffer[name_offset + i];
    }

    return name_len;
}

int zip_entry_name_ends_with(int index, void* suffix_ptr, int suffix_len) {
    if (index < 0 || index >= entry_count) return 0;

    int name_len = entries[index].name_len;
    if (suffix_len > name_len) return 0;

    const char* suffix = (const char*)suffix_ptr;
    int name_offset = entries[index].name_offset;
    int start = name_len - suffix_len;

    for (int i = 0; i < suffix_len; i++) {
        char c1 = name_buffer[name_offset + start + i];
        char c2 = suffix[i];
        /* Case-insensitive comparison */
        if (c1 >= 'A' && c1 <= 'Z') c1 += 32;
        if (c2 >= 'A' && c2 <= 'Z') c2 += 32;
        if (c1 != c2) return 0;
    }
    return 1;
}

int zip_entry_name_equals(int index, void* name_ptr, int name_len) {
    if (index < 0 || index >= entry_count) return 0;
    if (entries[index].name_len != name_len) return 0;

    const char* name = (const char*)name_ptr;
    int entry_offset = entries[index].name_offset;

    for (int i = 0; i < name_len; i++) {
        if (name_buffer[entry_offset + i] != name[i]) return 0;
    }
    return 1;
}

int zip_find_entry(void* name_ptr, int name_len) {
    for (int i = 0; i < entry_count; i++) {
        if (zip_entry_name_equals(i, name_ptr, name_len)) {
            return i;
        }
    }
    return -1;
}

int zip_get_data_offset(int index) {
    return get_data_offset_impl(index);
}

int zip_get_entry_count(void) {
    return entry_count;
}

void zip_close(void) {
    entry_count = 0;
    name_buffer_offset = 0;
    current_file_handle = 0;
}
%}
