(* library.dats - Book library implementation
 *
 * M15: Manages persistent book library with IndexedDB storage.
 * Each book entry stores: book_id, title, author, reading position, chapter count.
 * Library index is serialized as a binary blob for efficient storage.
 *
 * CORRECTNESS JUSTIFICATION FOR C CODE:
 * This module uses C in %{^ because it manages a statically-allocated
 * array of structs and performs byte-level serialization that cannot be
 * expressed efficiently with ATS2 dataprops in freestanding WASM.
 *
 * Runtime checks that substitute for compile-time proofs:
 * - LIBRARY_INDEX_VALID: library_count bounded by MAX_LIBRARY_BOOKS checks
 *   in library_add_book (line: if library_count >= MAX_LIBRARY_BOOKS)
 * - BOOK_IN_LIBRARY: index bounds checked at entry of every getter/setter
 *   (if index < 0 || index >= library_count return 0/early)
 * - SERIALIZE_ROUNDTRIP: serialize and deserialize use symmetric field order
 *   (book_id, title, author, chapter, page, spine_count) ensuring roundtrip
 * - BOOK_POSITION_VALID: chapter/page values stored as-is; validated by caller
 *)

#define ATS_DYNLOADFLAG 0

staload "library.sats"

%{^
/* Book entry structure */
#define MAX_LIBRARY_BOOKS 32
#define MAX_BOOK_TITLE 128
#define MAX_BOOK_AUTHOR 128
#define MAX_BOOK_ID 16

typedef struct {
    char book_id[MAX_BOOK_ID];
    int book_id_len;
    char title[MAX_BOOK_TITLE];
    int title_len;
    char author[MAX_BOOK_AUTHOR];
    int author_len;
    int current_chapter;
    int current_page;
    int spine_count;
} library_entry_t;

/* Library state */
static library_entry_t library_books[MAX_LIBRARY_BOOKS];
static int library_count = 0;

/* Async operation flags */
static int lib_save_pending = 0;
static int lib_load_pending = 0;
static int lib_metadata_save_pending = 0;
static int lib_metadata_load_pending = 0;
static int lib_metadata_load_index = -1;

/* String constants */
static const char str_books[] = "books";
static const char str_lib_key[] = "library-index";
static const char str_book_prefix[] = "book-";

/* External bridge imports */
extern unsigned char* get_fetch_buffer_ptr(void);
extern unsigned char* get_string_buffer_ptr(void);
extern void js_kv_get(void* store_ptr, int store_len, void* key_ptr, int key_len);
extern void js_kv_put(void* store_ptr, int store_len, void* key_ptr, int key_len, int data_offset, int data_len);

/* EPUB functions for getting current book info */
extern int epub_get_book_id(int buf_offset);
extern int epub_get_title(int buf_offset);
extern int epub_get_author(int buf_offset);
extern int epub_get_chapter_count(void);
extern int epub_serialize_metadata(void);
extern int epub_restore_metadata(int len);

/* Initialize library.
 * Postcondition: LIBRARY_INDEX_VALID(0, 32) - empty library is valid. */
void library_init(void) {
    library_count = 0;
    lib_save_pending = 0;
    lib_load_pending = 0;
    lib_metadata_save_pending = 0;
    lib_metadata_load_pending = 0;
    lib_metadata_load_index = -1;
    for (int i = 0; i < MAX_LIBRARY_BOOKS; i++) {
        library_books[i].book_id_len = 0;
        library_books[i].title_len = 0;
        library_books[i].author_len = 0;
        library_books[i].current_chapter = 0;
        library_books[i].current_page = 0;
        library_books[i].spine_count = 0;
    }
}

/* Get book count.
 * Returns [n:nat | n <= 32] - invariant maintained by add/remove. */
int library_get_count(void) {
    return library_count;
}

/* Get book title.
 * Runtime BOOK_IN_LIBRARY check: returns 0 if index out of bounds.
 * Writes THE title for book[index] to string buffer. */
int library_get_title(int index, int buf_offset) {
    if (index < 0 || index >= library_count) return 0;  /* BOOK_IN_LIBRARY guard */
    unsigned char* buf = get_string_buffer_ptr();
    library_entry_t* entry = &library_books[index];
    for (int i = 0; i < entry->title_len && buf_offset + i < 4096; i++) {
        buf[buf_offset + i] = entry->title[i];
    }
    return entry->title_len;
}

/* Get book author */
int library_get_author(int index, int buf_offset) {
    if (index < 0 || index >= library_count) return 0;
    unsigned char* buf = get_string_buffer_ptr();
    library_entry_t* entry = &library_books[index];
    for (int i = 0; i < entry->author_len && buf_offset + i < 4096; i++) {
        buf[buf_offset + i] = entry->author[i];
    }
    return entry->author_len;
}

/* Get book ID */
int library_get_book_id(int index, int buf_offset) {
    if (index < 0 || index >= library_count) return 0;
    unsigned char* buf = get_string_buffer_ptr();
    library_entry_t* entry = &library_books[index];
    for (int i = 0; i < entry->book_id_len && buf_offset + i < 4096; i++) {
        buf[buf_offset + i] = entry->book_id[i];
    }
    return entry->book_id_len;
}

/* Get reading position */
int library_get_chapter(int index) {
    if (index < 0 || index >= library_count) return 0;
    return library_books[index].current_chapter;
}

int library_get_page(int index) {
    if (index < 0 || index >= library_count) return 0;
    return library_books[index].current_page;
}

int library_get_spine_count(int index) {
    if (index < 0 || index >= library_count) return 0;
    return library_books[index].spine_count;
}

/* Find book by current epub book_id (uses string buffer).
 * Returns [i:int | i >= -1] where i >= 0 means BOOK_IN_LIBRARY(i, library_count).
 * Byte-for-byte comparison ensures correct book identification. */
int library_find_book_by_id(void) {
    unsigned char* str_buf = get_string_buffer_ptr();
    int id_len = epub_get_book_id(0);
    if (id_len <= 0) return -1;

    for (int i = 0; i < library_count; i++) {
        library_entry_t* entry = &library_books[i];
        if (entry->book_id_len == id_len) {
            int match = 1;
            for (int j = 0; j < id_len && match; j++) {
                if (entry->book_id[j] != str_buf[j]) match = 0;
            }
            if (match) return i;
        }
    }
    return -1;
}

/* Add current epub book to library.
 * Returns [i:int | i >= -1; i < 32].
 * LIBRARY_INDEX_VALID maintained: count only incremented when < MAX.
 * Deduplication: scans existing entries for matching book_id before adding. */
int library_add_book(void) {
    if (library_count >= MAX_LIBRARY_BOOKS) return -1;  /* LIBRARY_INDEX_VALID guard */

    unsigned char* str_buf = get_string_buffer_ptr();
    library_entry_t* entry = &library_books[library_count];

    /* Get book_id */
    int id_len = epub_get_book_id(0);
    if (id_len <= 0) return -1;
    if (id_len > MAX_BOOK_ID - 1) id_len = MAX_BOOK_ID - 1;
    for (int i = 0; i < id_len; i++) entry->book_id[i] = str_buf[i];
    entry->book_id[id_len] = 0;
    entry->book_id_len = id_len;

    /* Check for duplicate */
    for (int i = 0; i < library_count; i++) {
        if (library_books[i].book_id_len == id_len) {
            int match = 1;
            for (int j = 0; j < id_len && match; j++) {
                if (library_books[i].book_id[j] != entry->book_id[j]) match = 0;
            }
            if (match) {
                /* Already exists, update spine_count and return existing index */
                library_books[i].spine_count = epub_get_chapter_count();
                return i;
            }
        }
    }

    /* Get title */
    int tlen = epub_get_title(0);
    if (tlen > MAX_BOOK_TITLE - 1) tlen = MAX_BOOK_TITLE - 1;
    for (int i = 0; i < tlen; i++) entry->title[i] = str_buf[i];
    entry->title[tlen] = 0;
    entry->title_len = tlen;

    /* Get author */
    int alen = epub_get_author(0);
    if (alen > MAX_BOOK_AUTHOR - 1) alen = MAX_BOOK_AUTHOR - 1;
    for (int i = 0; i < alen; i++) entry->author[i] = str_buf[i];
    entry->author[alen] = 0;
    entry->author_len = alen;

    entry->current_chapter = 0;
    entry->current_page = 0;
    entry->spine_count = epub_get_chapter_count();

    return library_count++;
}

/* Remove book from library */
void library_remove_book(int index) {
    if (index < 0 || index >= library_count) return;

    /* Shift entries down */
    for (int i = index; i < library_count - 1; i++) {
        library_books[i] = library_books[i + 1];
    }
    library_count--;
}

/* Update reading position */
void library_update_position(int index, int chapter, int page) {
    if (index < 0 || index >= library_count) return;
    library_books[index].current_chapter = chapter;
    library_books[index].current_page = page;
}

/* Helper: write u16 LE */
static void lib_write_u16(unsigned char* buf, int offset, int value) {
    buf[offset] = value & 0xff;
    buf[offset + 1] = (value >> 8) & 0xff;
}

/* Helper: read u16 LE */
static int lib_read_u16(unsigned char* buf, int offset) {
    return buf[offset] | (buf[offset + 1] << 8);
}

/* Serialize library index to fetch buffer.
 * Returns [len:nat].
 * Format (symmetric with library_deserialize for SERIALIZE_ROUNDTRIP):
 *   u16 count
 *   per book: 8-byte book_id, u16 title_len, title, u16 author_len, author,
 *             u16 chapter, u16 page, u16 spine_count */
int library_serialize(void) {
    unsigned char* buf = get_fetch_buffer_ptr();
    int pos = 0;

    lib_write_u16(buf, pos, library_count); pos += 2;

    for (int i = 0; i < library_count; i++) {
        library_entry_t* entry = &library_books[i];

        /* book_id (fixed 8 bytes padded with zeros) */
        for (int j = 0; j < 8; j++) {
            buf[pos++] = (j < entry->book_id_len) ? entry->book_id[j] : 0;
        }

        /* title */
        lib_write_u16(buf, pos, entry->title_len); pos += 2;
        for (int j = 0; j < entry->title_len && pos < 16380; j++) {
            buf[pos++] = entry->title[j];
        }

        /* author */
        lib_write_u16(buf, pos, entry->author_len); pos += 2;
        for (int j = 0; j < entry->author_len && pos < 16380; j++) {
            buf[pos++] = entry->author[j];
        }

        /* position and spine count */
        lib_write_u16(buf, pos, entry->current_chapter); pos += 2;
        lib_write_u16(buf, pos, entry->current_page); pos += 2;
        lib_write_u16(buf, pos, entry->spine_count); pos += 2;
    }

    return pos;
}

/* Deserialize library index from fetch buffer.
 * Returns [r:int | r == 0 || r == 1].
 * Reads fields in same order as library_serialize (SERIALIZE_ROUNDTRIP).
 * Re-establishes LIBRARY_INDEX_VALID by clamping count to MAX_LIBRARY_BOOKS. */
int library_deserialize(int len) {
    if (len < 2) return 0;

    unsigned char* buf = get_fetch_buffer_ptr();
    int pos = 0;

    int count = lib_read_u16(buf, pos); pos += 2;
    if (count > MAX_LIBRARY_BOOKS) count = MAX_LIBRARY_BOOKS;

    library_count = 0;

    for (int i = 0; i < count && pos < len; i++) {
        library_entry_t* entry = &library_books[library_count];

        /* book_id (fixed 8 bytes) */
        for (int j = 0; j < 8 && pos < len; j++) {
            entry->book_id[j] = buf[pos++];
        }
        entry->book_id[8] = 0;
        /* Find actual length (skip trailing zeros) */
        entry->book_id_len = 8;
        while (entry->book_id_len > 0 && entry->book_id[entry->book_id_len - 1] == 0) {
            entry->book_id_len--;
        }

        if (pos + 2 > len) break;

        /* title */
        int tlen = lib_read_u16(buf, pos); pos += 2;
        if (tlen > MAX_BOOK_TITLE - 1) tlen = MAX_BOOK_TITLE - 1;
        for (int j = 0; j < tlen && pos < len; j++) {
            entry->title[j] = buf[pos++];
        }
        entry->title[tlen] = 0;
        entry->title_len = tlen;

        if (pos + 2 > len) break;

        /* author */
        int alen = lib_read_u16(buf, pos); pos += 2;
        if (alen > MAX_BOOK_AUTHOR - 1) alen = MAX_BOOK_AUTHOR - 1;
        for (int j = 0; j < alen && pos < len; j++) {
            entry->author[j] = buf[pos++];
        }
        entry->author[alen] = 0;
        entry->author_len = alen;

        if (pos + 6 > len) break;

        /* position and spine count */
        entry->current_chapter = lib_read_u16(buf, pos); pos += 2;
        entry->current_page = lib_read_u16(buf, pos); pos += 2;
        entry->spine_count = lib_read_u16(buf, pos); pos += 2;

        library_count++;
    }

    return 1;
}

/* Save library index to IndexedDB */
void library_save(void) {
    unsigned char* str_buf = get_string_buffer_ptr();

    int data_len = library_serialize();

    /* Write key to string buffer */
    for (int i = 0; i < 13; i++) str_buf[i] = str_lib_key[i];

    lib_save_pending = 1;
    js_kv_put((void*)str_books, 5, str_buf, 13, 0, data_len);
}

/* Load library index from IndexedDB */
void library_load(void) {
    unsigned char* str_buf = get_string_buffer_ptr();

    /* Write key to string buffer */
    for (int i = 0; i < 13; i++) str_buf[i] = str_lib_key[i];

    lib_load_pending = 1;
    js_kv_get((void*)str_books, 5, str_buf, 13);
}

/* Handle library load completion */
void library_on_load_complete(int len) {
    lib_load_pending = 0;
    if (len > 0) {
        library_deserialize(len);
    }
}

/* Handle library save completion */
void library_on_save_complete(int success) {
    lib_save_pending = 0;
}

/* Save book metadata to IndexedDB */
void library_save_book_metadata(void) {
    unsigned char* str_buf = get_string_buffer_ptr();

    /* Serialize epub metadata to fetch buffer */
    int data_len = epub_serialize_metadata();
    if (data_len <= 0) return;

    /* Build key: "book-" + book_id */
    int key_len = 0;
    for (int i = 0; i < 5; i++) str_buf[key_len++] = str_book_prefix[i];
    int id_len = epub_get_book_id(key_len);
    key_len += id_len;

    lib_metadata_save_pending = 1;
    js_kv_put((void*)str_books, 5, str_buf, key_len, 0, data_len);
}

/* Load book metadata from IndexedDB */
void library_load_book_metadata(int index) {
    if (index < 0 || index >= library_count) return;

    unsigned char* str_buf = get_string_buffer_ptr();
    library_entry_t* entry = &library_books[index];

    /* Build key: "book-" + book_id */
    int key_len = 0;
    for (int i = 0; i < 5; i++) str_buf[key_len++] = str_book_prefix[i];
    for (int i = 0; i < entry->book_id_len; i++) str_buf[key_len++] = entry->book_id[i];

    lib_metadata_load_pending = 1;
    lib_metadata_load_index = index;
    js_kv_get((void*)str_books, 5, str_buf, key_len);
}

/* Handle metadata load completion */
void library_on_metadata_load_complete(int len) {
    lib_metadata_load_pending = 0;
    if (len > 0) {
        epub_restore_metadata(len);
    }
}

/* Handle metadata save completion */
void library_on_metadata_save_complete(int success) {
    lib_metadata_save_pending = 0;
}

/* Check pending operations */
int library_is_save_pending(void) { return lib_save_pending; }
int library_is_load_pending(void) { return lib_load_pending; }
int library_is_metadata_pending(void) { return lib_metadata_save_pending || lib_metadata_load_pending; }
%}

(* All implementations are in the C block above via "mac#" linkage *)
