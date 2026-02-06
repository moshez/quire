(* epub.dats - EPUB import pipeline implementation
 *
 * State machine for asynchronous EPUB import:
 * 1. Open file
 * 2. Parse ZIP
 * 3. Read container.xml to find OPF
 * 4. Read OPF for metadata and spine
 * 5. Open IndexedDB
 * 6. Decompress and store each entry
 * 7. Complete
 *)

#define ATS_DYNLOADFLAG 0

staload "epub.sats"
staload "zip.sats"
staload "xml.sats"

%{^
#include <stdint.h>

extern unsigned char* get_fetch_buffer_ptr(void);
extern unsigned char* get_string_buffer_ptr(void);

/* Bridge imports */
extern void js_file_open(int node_id);
extern int js_file_read_chunk(int handle, int offset, int length);
extern void js_file_close(int handle);
extern void js_decompress(int file_handle, int offset, int compressed_size, int method);
extern int js_blob_read_chunk(int handle, int offset, int length);
extern int js_blob_size(int handle);
extern void js_blob_free(int handle);
extern void js_kv_open(void* name_ptr, int name_len, int version, void* stores_ptr, int stores_len);
extern void js_kv_put_blob(void* store_ptr, int store_len, void* key_ptr, int key_len, int blob_handle);
extern void js_kv_put(void* store_ptr, int store_len, void* key_ptr, int key_len, int data_offset, int data_len);

/* ZIP functions (from zip.dats) */
extern void zip_init(void);
extern int zip_open(int file_handle, int file_size);
extern int zip_get_entry(int index, void* entry);
extern int zip_get_entry_name(int index, int buf_offset);
extern int zip_entry_name_ends_with(int index, void* suffix, int suffix_len);
extern int zip_entry_name_equals(int index, void* name, int name_len);
extern int zip_find_entry(void* name, int name_len);
extern int zip_get_data_offset(int index);
extern int zip_get_entry_count(void);
extern void zip_close(void);

/* XML functions (from xml.dats) */
extern void* xml_init(int data_len);
extern void xml_free(void* ctx);
extern int xml_next_element(void* ctx);
extern int xml_get_element_name(void* ctx, int buf_offset);
extern int xml_element_is(void* ctx, void* name, int name_len);
extern int xml_get_attr(void* ctx, void* name, int name_len, int buf_offset);
extern int xml_is_closing(void* ctx);
extern int xml_is_self_closing(void* ctx);
extern int xml_get_text_content(void* ctx, int buf_offset);
extern void xml_skip_element(void* ctx);

/* Forward declarations */
static void process_next_entry(void);
void epub_continue(void);

/* Constants */
#define MAX_TITLE_LEN 256
#define MAX_AUTHOR_LEN 256
#define MAX_OPF_PATH_LEN 256
#define MAX_BOOK_ID_LEN 64
#define MAX_SPINE_ITEMS 256
#define MAX_MANIFEST_ITEMS 512

/* String constants */
static const char str_container_path[] = "META-INF/container.xml";
static const char str_rootfile[] = "rootfile";
static const char str_full_path[] = "full-path";
static const char str_metadata[] = "metadata";
static const char str_dc_title[] = "dc:title";
static const char str_title[] = "title";
static const char str_dc_creator[] = "dc:creator";
static const char str_creator[] = "creator";
static const char str_manifest[] = "manifest";
static const char str_item[] = "item";
static const char str_id[] = "id";
static const char str_href[] = "href";
static const char str_media_type[] = "media-type";
static const char str_spine[] = "spine";
static const char str_itemref[] = "itemref";
static const char str_idref[] = "idref";
static const char str_books[] = "books";
static const char str_chapters[] = "chapters";
static const char str_resources[] = "resources";
static const char str_stores[] = "books,chapters,resources,settings";
static const char str_quire_db[] = "quire";
static const char str_xhtml[] = "application/xhtml+xml";
static const char str_html[] = "text/html";
static const char str_opf_suffix[] = ".opf";
static const char str_ncx_suffix[] = ".ncx";
static const char str_unknown[] = "Unknown";

/* M13: NCX/TOC parsing string constants */
static const char str_navMap[] = "navMap";
static const char str_navPoint[] = "navPoint";
static const char str_navLabel[] = "navLabel";
static const char str_text[] = "text";
static const char str_content[] = "content";
static const char str_src[] = "src";

/* Manifest item */
typedef struct {
    int id_offset;          /* Offset in manifest_strings */
    int id_len;
    int href_offset;
    int href_len;
    int media_type;         /* 0=other, 1=xhtml, 2=css, 3=image, 4=font */
    int zip_index;          /* Index in ZIP central directory */
} manifest_item_t;

/* M13: TOC entry */
#define MAX_TOC_ENTRIES 256
#define MAX_TOC_LABEL_LEN 128

typedef struct {
    int label_offset;       /* Offset in toc_strings */
    int label_len;
    int href_offset;        /* Offset in toc_strings */
    int href_len;
    int spine_index;        /* Index into spine (-1 if not found) */
    int nesting_level;      /* 0 = top level, 1 = nested, etc. */
} toc_entry_t;

/* EPUB import state */
static int epub_state = 0;  /* EPUB_STATE_IDLE */
static int epub_progress = 0;
static char epub_error[128] = {0};
static int epub_error_len = 0;

/* File and book info */
static int file_handle = 0;
static int file_size = 0;
static char book_title[MAX_TITLE_LEN] = {0};
static int book_title_len = 0;
static char book_author[MAX_AUTHOR_LEN] = {0};
static int book_author_len = 0;
static char book_id[MAX_BOOK_ID_LEN] = {0};
static int book_id_len = 0;
static char opf_path[MAX_OPF_PATH_LEN] = {0};
static int opf_path_len = 0;
static char opf_dir[MAX_OPF_PATH_LEN] = {0};
static int opf_dir_len = 0;

/* Manifest and spine */
static char manifest_strings[4096] = {0};
static int manifest_strings_offset = 0;
static manifest_item_t manifest_items[MAX_MANIFEST_ITEMS];
static int manifest_count = 0;
static int spine_manifest_indices[MAX_SPINE_ITEMS];
static int spine_count = 0;

/* M13: TOC storage */
static char toc_strings[8192] = {0};
static int toc_strings_offset = 0;
static toc_entry_t toc_entries[MAX_TOC_ENTRIES];
static int toc_count = 0;
static int ncx_zip_index = -1;  /* ZIP index of NCX file */

/* Processing state */
static int current_entry_index = 0;
static int total_entries = 0;
static int current_blob_handle = 0;

/* Helper: Set error message */
static void set_error(const char* msg) {
    int i = 0;
    while (msg[i] && i < 127) {
        epub_error[i] = msg[i];
        i++;
    }
    epub_error[i] = 0;
    epub_error_len = i;
    epub_state = 99;  /* EPUB_STATE_ERROR */
}

/* Helper: Copy string from source to dest */
static int copy_string(const unsigned char* src, int src_len, char* dest, int max_len) {
    int len = src_len < max_len ? src_len : max_len - 1;
    for (int i = 0; i < len; i++) {
        dest[i] = src[i];
    }
    dest[len] = 0;
    return len;
}

/* Helper: Simple hash for book ID */
static void generate_book_id(void) {
    uint32_t hash = 5381;
    for (int i = 0; i < book_title_len; i++) {
        hash = ((hash << 5) + hash) + (unsigned char)book_title[i];
    }
    for (int i = 0; i < book_author_len; i++) {
        hash = ((hash << 5) + hash) + (unsigned char)book_author[i];
    }

    /* Convert hash to hex string */
    static const char hex[] = "0123456789abcdef";
    for (int i = 0; i < 8; i++) {
        book_id[i] = hex[(hash >> (28 - i * 4)) & 0xf];
    }
    book_id[8] = 0;
    book_id_len = 8;
}

/* Helper: Find manifest item by ID */
static int find_manifest_by_id(const unsigned char* id, int id_len) {
    for (int i = 0; i < manifest_count; i++) {
        if (manifest_items[i].id_len == id_len) {
            int match = 1;
            for (int j = 0; j < id_len && match; j++) {
                if (manifest_strings[manifest_items[i].id_offset + j] != id[j]) {
                    match = 0;
                }
            }
            if (match) return i;
        }
    }
    return -1;
}

/* M13: Helper: Find spine index from href (handles fragment identifiers) */
static int find_spine_index_by_href(const unsigned char* href, int href_len) {
    /* Extract path without fragment (e.g., "chapter1.xhtml" from "chapter1.xhtml#section1") */
    int path_len = href_len;
    for (int i = 0; i < href_len; i++) {
        if (href[i] == '#') {
            path_len = i;
            break;
        }
    }

    /* Try to find matching manifest item by href */
    for (int i = 0; i < manifest_count; i++) {
        manifest_item_t* item = &manifest_items[i];
        if (item->href_len == path_len) {
            int match = 1;
            for (int j = 0; j < path_len && match; j++) {
                if (manifest_strings[item->href_offset + j] != href[j]) {
                    match = 0;
                }
            }
            if (match) {
                /* Found manifest item, now find in spine */
                for (int s = 0; s < spine_count; s++) {
                    if (spine_manifest_indices[s] == i) {
                        return s;
                    }
                }
            }
        }
    }

    return -1;
}

/* Helper: Get OPF directory path */
static void extract_opf_dir(void) {
    opf_dir_len = 0;
    /* Find last '/' in OPF path */
    int last_slash = -1;
    for (int i = 0; i < opf_path_len; i++) {
        if (opf_path[i] == '/') last_slash = i;
    }
    if (last_slash > 0) {
        for (int i = 0; i <= last_slash; i++) {
            opf_dir[i] = opf_path[i];
        }
        opf_dir_len = last_slash + 1;
    }
    opf_dir[opf_dir_len] = 0;
}

/* Parse container.xml to find OPF path */
static int parse_container(void) {
    unsigned char* buf = get_fetch_buffer_ptr();

    /* Find container.xml in ZIP */
    int entry_idx = zip_find_entry((void*)str_container_path, 22);
    if (entry_idx < 0) {
        set_error("Missing container.xml");
        return 0;
    }

    /* Get entry info */
    int entry_data[7];
    if (!zip_get_entry(entry_idx, entry_data)) {
        set_error("Failed to read container entry");
        return 0;
    }

    int compression = entry_data[3];
    int compressed_size = entry_data[4];
    int data_offset = zip_get_data_offset(entry_idx);

    if (compression == 0) {
        /* Stored - read directly */
        int read_len = js_file_read_chunk(file_handle, data_offset, compressed_size);
        if (read_len <= 0) {
            set_error("Failed to read container.xml");
            return 0;
        }

        void* xml = xml_init(read_len);
        if (!xml) {
            set_error("XML init failed");
            return 0;
        }

        /* Find <rootfile full-path="..."> */
        while (xml_next_element(xml)) {
            if (xml_element_is(xml, (void*)str_rootfile, 8)) {
                int path_len = xml_get_attr(xml, (void*)str_full_path, 9, 0);
                if (path_len > 0) {
                    unsigned char* str_buf = get_string_buffer_ptr();
                    opf_path_len = copy_string(str_buf, path_len, opf_path, MAX_OPF_PATH_LEN);
                    extract_opf_dir();
                    xml_free(xml);
                    return 1;
                }
            }
        }
        xml_free(xml);
        set_error("No rootfile in container.xml");
        return 0;
    } else {
        /* Deflated - need async decompression */
        set_error("Compressed container.xml not yet supported");
        return 0;
    }
}

/* Parse OPF file for metadata, manifest, and spine */
static int parse_opf(void) {
    unsigned char* buf = get_fetch_buffer_ptr();
    unsigned char* str_buf = get_string_buffer_ptr();

    /* Find OPF in ZIP */
    int entry_idx = zip_find_entry(opf_path, opf_path_len);
    if (entry_idx < 0) {
        set_error("OPF file not found in ZIP");
        return 0;
    }

    /* Get entry info */
    int entry_data[7];
    if (!zip_get_entry(entry_idx, entry_data)) {
        set_error("Failed to read OPF entry");
        return 0;
    }

    int compression = entry_data[3];
    int compressed_size = entry_data[4];
    int data_offset = zip_get_data_offset(entry_idx);

    if (compression != 0) {
        set_error("Compressed OPF not yet supported");
        return 0;
    }

    /* Read OPF content */
    int read_len = js_file_read_chunk(file_handle, data_offset, compressed_size);
    if (read_len <= 0) {
        set_error("Failed to read OPF content");
        return 0;
    }

    void* xml = xml_init(read_len);
    if (!xml) {
        set_error("XML init failed for OPF");
        return 0;
    }

    /* Reset manifest and spine */
    manifest_count = 0;
    manifest_strings_offset = 0;
    spine_count = 0;

    int in_metadata = 0;
    int in_manifest = 0;
    int in_spine = 0;

    while (xml_next_element(xml)) {
        if (xml_is_closing(xml)) {
            /* Check for section end */
            if (xml_element_is(xml, (void*)str_metadata, 8)) in_metadata = 0;
            else if (xml_element_is(xml, (void*)str_manifest, 8)) in_manifest = 0;
            else if (xml_element_is(xml, (void*)str_spine, 5)) in_spine = 0;
            continue;
        }

        /* Section starts */
        if (xml_element_is(xml, (void*)str_metadata, 8)) {
            in_metadata = 1;
            continue;
        }
        if (xml_element_is(xml, (void*)str_manifest, 8)) {
            in_manifest = 1;
            continue;
        }
        if (xml_element_is(xml, (void*)str_spine, 5)) {
            in_spine = 1;
            continue;
        }

        /* Parse metadata */
        if (in_metadata) {
            if (xml_element_is(xml, (void*)str_dc_title, 8) ||
                xml_element_is(xml, (void*)str_title, 5)) {
                if (!xml_is_self_closing(xml)) {
                    int len = xml_get_text_content(xml, 0);
                    if (len > 0 && book_title_len == 0) {
                        book_title_len = copy_string(str_buf, len, book_title, MAX_TITLE_LEN);
                    }
                }
            } else if (xml_element_is(xml, (void*)str_dc_creator, 10) ||
                       xml_element_is(xml, (void*)str_creator, 7)) {
                if (!xml_is_self_closing(xml)) {
                    int len = xml_get_text_content(xml, 0);
                    if (len > 0 && book_author_len == 0) {
                        book_author_len = copy_string(str_buf, len, book_author, MAX_AUTHOR_LEN);
                    }
                }
            }
        }

        /* Parse manifest items */
        if (in_manifest && xml_element_is(xml, (void*)str_item, 4)) {
            if (manifest_count >= MAX_MANIFEST_ITEMS) continue;

            manifest_item_t* item = &manifest_items[manifest_count];

            /* Get id attribute */
            int id_len = xml_get_attr(xml, (void*)str_id, 2, 0);
            if (id_len > 0 && manifest_strings_offset + id_len < 4096) {
                item->id_offset = manifest_strings_offset;
                item->id_len = id_len;
                for (int i = 0; i < id_len; i++) {
                    manifest_strings[manifest_strings_offset++] = str_buf[i];
                }
            } else {
                continue;
            }

            /* Get href attribute */
            int href_len = xml_get_attr(xml, (void*)str_href, 4, 0);
            if (href_len > 0 && manifest_strings_offset + href_len < 4096) {
                item->href_offset = manifest_strings_offset;
                item->href_len = href_len;
                for (int i = 0; i < href_len; i++) {
                    manifest_strings[manifest_strings_offset++] = str_buf[i];
                }
            } else {
                continue;
            }

            /* Get media-type */
            int mt_len = xml_get_attr(xml, (void*)str_media_type, 10, 0);
            item->media_type = 0;
            if (mt_len > 0) {
                /* Check for xhtml */
                int is_xhtml = 1;
                const char* xhtml = str_xhtml;
                for (int i = 0; i < 20 && i < mt_len && is_xhtml; i++) {
                    if (str_buf[i] != xhtml[i]) is_xhtml = 0;
                }
                if (is_xhtml && mt_len >= 20) item->media_type = 1;

                /* Check for text/html */
                if (item->media_type == 0) {
                    int is_html = 1;
                    const char* html = str_html;
                    for (int i = 0; i < 9 && i < mt_len && is_html; i++) {
                        if (str_buf[i] != html[i]) is_html = 0;
                    }
                    if (is_html && mt_len >= 9) item->media_type = 1;
                }
            }

            /* Find corresponding ZIP entry */
            /* Build full path: opf_dir + href */
            char full_path[512];
            int full_len = 0;
            for (int i = 0; i < opf_dir_len && full_len < 511; i++) {
                full_path[full_len++] = opf_dir[i];
            }
            for (int i = 0; i < item->href_len && full_len < 511; i++) {
                full_path[full_len++] = manifest_strings[item->href_offset + i];
            }
            full_path[full_len] = 0;

            item->zip_index = zip_find_entry(full_path, full_len);

            manifest_count++;
        }

        /* Parse spine itemrefs */
        if (in_spine && xml_element_is(xml, (void*)str_itemref, 7)) {
            if (spine_count >= MAX_SPINE_ITEMS) continue;

            int idref_len = xml_get_attr(xml, (void*)str_idref, 5, 0);
            if (idref_len > 0) {
                int manifest_idx = find_manifest_by_id(str_buf, idref_len);
                if (manifest_idx >= 0) {
                    spine_manifest_indices[spine_count++] = manifest_idx;
                }
            }
        }
    }

    xml_free(xml);

    /* Set defaults if metadata missing */
    if (book_title_len == 0) {
        book_title_len = copy_string((const unsigned char*)str_unknown, 7, book_title, MAX_TITLE_LEN);
    }
    if (book_author_len == 0) {
        book_author_len = copy_string((const unsigned char*)str_unknown, 7, book_author, MAX_AUTHOR_LEN);
    }

    generate_book_id();

    /* Find NCX file in manifest */
    ncx_zip_index = -1;
    for (int i = 0; i < zip_get_entry_count(); i++) {
        if (zip_entry_name_ends_with(i, (void*)str_ncx_suffix, 4)) {
            ncx_zip_index = i;
            break;
        }
    }

    return 1;
}

/* M13: Parse NCX file for Table of Contents */
static int parse_ncx(void) {
    if (ncx_zip_index < 0) return 0;  /* No NCX file found */

    unsigned char* buf = get_fetch_buffer_ptr();
    unsigned char* str_buf = get_string_buffer_ptr();

    /* Get NCX entry info */
    int entry_data[7];
    if (!zip_get_entry(ncx_zip_index, entry_data)) {
        return 0;
    }

    int compression = entry_data[3];
    int compressed_size = entry_data[4];
    int data_offset = zip_get_data_offset(ncx_zip_index);

    if (compression != 0) {
        /* Compressed NCX not supported for now */
        return 0;
    }

    /* Read NCX content */
    int read_len = js_file_read_chunk(file_handle, data_offset, compressed_size);
    if (read_len <= 0) {
        return 0;
    }

    void* xml = xml_init(read_len);
    if (!xml) {
        return 0;
    }

    /* Reset TOC state */
    toc_count = 0;
    toc_strings_offset = 0;

    int in_navMap = 0;
    int current_level = 0;
    int pending_label = 0;
    int pending_label_offset = 0;
    int pending_label_len = 0;
    int navPoint_depth = 0;  /* Track nested navPoints */

    while (xml_next_element(xml)) {
        if (xml_is_closing(xml)) {
            if (xml_element_is(xml, (void*)str_navMap, 6)) {
                in_navMap = 0;
            } else if (xml_element_is(xml, (void*)str_navPoint, 8)) {
                if (navPoint_depth > 0) navPoint_depth--;
            }
            continue;
        }

        if (xml_element_is(xml, (void*)str_navMap, 6)) {
            in_navMap = 1;
            continue;
        }

        if (in_navMap) {
            if (xml_element_is(xml, (void*)str_navPoint, 8)) {
                /* Start of a new navPoint */
                current_level = navPoint_depth;
                navPoint_depth++;
                pending_label = 0;
            } else if (xml_element_is(xml, (void*)str_text, 4)) {
                /* Get the label text */
                if (!xml_is_self_closing(xml)) {
                    int len = xml_get_text_content(xml, 0);
                    if (len > 0 && toc_strings_offset + len < 8190) {
                        pending_label_offset = toc_strings_offset;
                        pending_label_len = len < MAX_TOC_LABEL_LEN ? len : MAX_TOC_LABEL_LEN;
                        for (int i = 0; i < pending_label_len; i++) {
                            toc_strings[toc_strings_offset++] = str_buf[i];
                        }
                        pending_label = 1;
                    }
                }
            } else if (xml_element_is(xml, (void*)str_content, 7)) {
                /* Get the content src and create TOC entry */
                int src_len = xml_get_attr(xml, (void*)str_src, 3, 0);
                if (src_len > 0 && pending_label && toc_count < MAX_TOC_ENTRIES) {
                    toc_entry_t* entry = &toc_entries[toc_count];
                    entry->label_offset = pending_label_offset;
                    entry->label_len = pending_label_len;

                    /* Store href */
                    entry->href_offset = toc_strings_offset;
                    entry->href_len = src_len < 256 ? src_len : 255;
                    if (toc_strings_offset + entry->href_len < 8190) {
                        for (int i = 0; i < entry->href_len; i++) {
                            toc_strings[toc_strings_offset++] = str_buf[i];
                        }
                    }

                    /* Find spine index */
                    entry->spine_index = find_spine_index_by_href(str_buf, src_len);
                    entry->nesting_level = current_level;

                    toc_count++;
                    pending_label = 0;
                }
            }
        }
    }

    xml_free(xml);
    return toc_count > 0 ? 1 : 0;
}

/* Start storing entries in IndexedDB */
static void start_storing(void) {
    epub_state = 6;  /* EPUB_STATE_DECOMPRESSING */
    current_entry_index = 0;
    total_entries = zip_get_entry_count();
    epub_progress = 0;

    epub_continue();
}

/* Process next entry */
static void process_next_entry(void) {
    while (current_entry_index < total_entries) {
        int idx = current_entry_index;

        /* Get entry info */
        int entry_data[7];
        if (!zip_get_entry(idx, entry_data)) {
            current_entry_index++;
            continue;
        }

        int compression = entry_data[3];
        int compressed_size = entry_data[4];
        int uncompressed_size = entry_data[5];

        /* Skip directories (end with /) and empty files */
        unsigned char* str_buf = get_string_buffer_ptr();
        int name_len = zip_get_entry_name(idx, 0);
        if (name_len > 0 && str_buf[name_len - 1] == '/') {
            current_entry_index++;
            continue;
        }
        if (uncompressed_size == 0 && compressed_size == 0) {
            current_entry_index++;
            continue;
        }

        /* Skip OPF and container.xml - we don't need to store them */
        if (zip_entry_name_ends_with(idx, (void*)str_opf_suffix, 4) ||
            zip_entry_name_ends_with(idx, (void*)str_ncx_suffix, 4) ||
            zip_entry_name_equals(idx, (void*)str_container_path, 22)) {
            current_entry_index++;
            continue;
        }

        int data_offset = zip_get_data_offset(idx);
        if (data_offset < 0) {
            current_entry_index++;
            continue;
        }

        if (compression == 8) {
            /* Deflate - need async decompression */
            js_decompress(file_handle, data_offset, compressed_size, 0);
            return;  /* Wait for callback */
        } else if (compression == 0) {
            /* Stored - read and store directly */
            /* For stored files, we need to create a blob handle */
            /* Read into fetch buffer and create blob */
            int read_len = js_file_read_chunk(file_handle, data_offset, uncompressed_size);
            if (read_len > 0) {
                /* Store directly from fetch buffer */
                unsigned char* str_buf2 = get_string_buffer_ptr();
                int name_len2 = zip_get_entry_name(idx, 0);

                /* Build key: book_id/path */
                char key[600];
                int key_len = 0;
                for (int i = 0; i < book_id_len && key_len < 599; i++) {
                    key[key_len++] = book_id[i];
                }
                key[key_len++] = '/';
                for (int i = 0; i < name_len2 && key_len < 599; i++) {
                    key[key_len++] = str_buf2[i];
                }

                /* Determine store based on content type */
                const char* store = str_resources;
                int store_len = 9;

                /* Check if this is a chapter (in spine) */
                for (int i = 0; i < manifest_count; i++) {
                    if (manifest_items[i].zip_index == idx && manifest_items[i].media_type == 1) {
                        /* Check if in spine */
                        for (int j = 0; j < spine_count; j++) {
                            if (spine_manifest_indices[j] == i) {
                                store = str_chapters;
                                store_len = 8;
                                break;
                            }
                        }
                        break;
                    }
                }

                js_kv_put((void*)store, store_len, key, key_len, 0, read_len);
                epub_state = 7;  /* EPUB_STATE_STORING */
                return;  /* Wait for callback */
            }
        }

        current_entry_index++;
    }

    /* All entries processed */
    epub_state = 8;  /* EPUB_STATE_DONE */
    epub_progress = 100;
}

/* Public API */

void epub_init(void) {
    epub_state = 0;
    epub_progress = 0;
    epub_error[0] = 0;
    epub_error_len = 0;
    file_handle = 0;
    file_size = 0;
    book_title[0] = 0;
    book_title_len = 0;
    book_author[0] = 0;
    book_author_len = 0;
    book_id[0] = 0;
    book_id_len = 0;
    opf_path[0] = 0;
    opf_path_len = 0;
    opf_dir[0] = 0;
    opf_dir_len = 0;
    manifest_count = 0;
    manifest_strings_offset = 0;
    spine_count = 0;
    current_entry_index = 0;
    total_entries = 0;
    current_blob_handle = 0;
    /* M13: Reset TOC state */
    toc_count = 0;
    toc_strings_offset = 0;
    ncx_zip_index = -1;
}

int epub_start_import(int file_input_node_id) {
    epub_init();
    epub_state = 1;  /* EPUB_STATE_OPENING_FILE */
    js_file_open(file_input_node_id);
    return 1;
}

int epub_get_state(void) {
    return epub_state;
}

int epub_get_progress(void) {
    return epub_progress;
}

int epub_get_error(int buf_offset) {
    unsigned char* buf = get_string_buffer_ptr();
    for (int i = 0; i < epub_error_len && buf_offset + i < 4096; i++) {
        buf[buf_offset + i] = epub_error[i];
    }
    return epub_error_len;
}

int epub_get_title(int buf_offset) {
    unsigned char* buf = get_string_buffer_ptr();
    for (int i = 0; i < book_title_len && buf_offset + i < 4096; i++) {
        buf[buf_offset + i] = book_title[i];
    }
    return book_title_len;
}

int epub_get_author(int buf_offset) {
    unsigned char* buf = get_string_buffer_ptr();
    for (int i = 0; i < book_author_len && buf_offset + i < 4096; i++) {
        buf[buf_offset + i] = book_author[i];
    }
    return book_author_len;
}

int epub_get_book_id(int buf_offset) {
    unsigned char* buf = get_string_buffer_ptr();
    for (int i = 0; i < book_id_len && buf_offset + i < 4096; i++) {
        buf[buf_offset + i] = book_id[i];
    }
    return book_id_len;
}

int epub_get_chapter_count(void) {
    return spine_count;
}

int epub_get_chapter_key(int chapter_index, int buf_offset) {
    if (chapter_index < 0 || chapter_index >= spine_count) return 0;

    unsigned char* buf = get_string_buffer_ptr();
    int key_len = 0;

    /* Add book_id prefix */
    for (int i = 0; i < book_id_len && key_len + buf_offset < 4096; i++) {
        buf[buf_offset + key_len++] = book_id[i];
    }

    /* Add separator */
    if (key_len + buf_offset < 4096) {
        buf[buf_offset + key_len++] = '/';
    }

    /* Get manifest item for this spine entry */
    int manifest_idx = spine_manifest_indices[chapter_index];
    if (manifest_idx < 0 || manifest_idx >= manifest_count) return 0;

    manifest_item_t* item = &manifest_items[manifest_idx];

    /* Add OPF directory prefix (chapters are stored with full path from ZIP root) */
    for (int i = 0; i < opf_dir_len && key_len + buf_offset < 4096; i++) {
        buf[buf_offset + key_len++] = opf_dir[i];
    }

    /* Add chapter href */
    for (int i = 0; i < item->href_len && key_len + buf_offset < 4096; i++) {
        buf[buf_offset + key_len++] = manifest_strings[item->href_offset + i];
    }

    return key_len;
}

void epub_continue(void) {
    switch (epub_state) {
        case 6:  /* EPUB_STATE_DECOMPRESSING */
        case 7:  /* EPUB_STATE_STORING */
            process_next_entry();
            break;
        default:
            break;
    }
}

void epub_on_file_open(int handle, int size) {
    if (handle == 0) {
        set_error("Failed to open file");
        return;
    }

    file_handle = handle;
    file_size = size;
    epub_state = 2;  /* EPUB_STATE_PARSING_ZIP */

    /* Parse ZIP */
    zip_init();
    int entry_count = zip_open(handle, size);
    if (entry_count == 0) {
        set_error("Invalid ZIP file");
        return;
    }

    epub_state = 3;  /* EPUB_STATE_READING_CONTAINER */

    /* Parse container.xml */
    if (!parse_container()) {
        return;  /* Error already set */
    }

    epub_state = 4;  /* EPUB_STATE_READING_OPF */

    /* Parse OPF */
    if (!parse_opf()) {
        return;  /* Error already set */
    }

    /* M13: Parse NCX for TOC (optional - don't fail if missing) */
    parse_ncx();

    epub_state = 5;  /* EPUB_STATE_OPENING_DB */

    /* Open IndexedDB */
    js_kv_open((void*)str_quire_db, 5, 1, (void*)str_stores, 24);
}

void epub_on_decompress(int blob_handle, int size) {
    if (blob_handle == 0) {
        /* Decompression failed - skip this entry */
        current_entry_index++;
        process_next_entry();
        return;
    }

    current_blob_handle = blob_handle;

    /* Get entry name for key */
    unsigned char* str_buf = get_string_buffer_ptr();
    int name_len = zip_get_entry_name(current_entry_index, 0);

    /* Build key: book_id/path */
    char key[600];
    int key_len = 0;
    for (int i = 0; i < book_id_len && key_len < 599; i++) {
        key[key_len++] = book_id[i];
    }
    key[key_len++] = '/';
    for (int i = 0; i < name_len && key_len < 599; i++) {
        key[key_len++] = str_buf[i];
    }

    /* Determine store */
    const char* store = str_resources;
    int store_len = 9;

    /* Check if this is a chapter */
    for (int i = 0; i < manifest_count; i++) {
        if (manifest_items[i].zip_index == current_entry_index && manifest_items[i].media_type == 1) {
            for (int j = 0; j < spine_count; j++) {
                if (spine_manifest_indices[j] == i) {
                    store = str_chapters;
                    store_len = 8;
                    break;
                }
            }
            break;
        }
    }

    epub_state = 7;  /* EPUB_STATE_STORING */
    js_kv_put_blob((void*)store, store_len, key, key_len, blob_handle);
}

void epub_on_db_open(int success) {
    if (!success) {
        set_error("Failed to open database");
        return;
    }

    /* Start storing entries */
    start_storing();
}

void epub_on_db_put(int success) {
    /* Free blob handle if we have one */
    if (current_blob_handle > 0) {
        js_blob_free(current_blob_handle);
        current_blob_handle = 0;
    }

    /* Update progress */
    current_entry_index++;
    if (total_entries > 0) {
        epub_progress = (current_entry_index * 100) / total_entries;
    }

    /* Continue with next entry */
    epub_state = 6;  /* EPUB_STATE_DECOMPRESSING */
    process_next_entry();
}

void epub_cancel(void) {
    if (current_blob_handle > 0) {
        js_blob_free(current_blob_handle);
        current_blob_handle = 0;
    }
    if (file_handle > 0) {
        js_file_close(file_handle);
        file_handle = 0;
    }
    zip_close();
    epub_state = 0;
}

/* M13: TOC API functions */

int epub_get_toc_count(void) {
    return toc_count;
}

int epub_get_toc_label(int toc_index, int buf_offset) {
    if (toc_index < 0 || toc_index >= toc_count) return 0;

    unsigned char* buf = get_string_buffer_ptr();
    toc_entry_t* entry = &toc_entries[toc_index];

    for (int i = 0; i < entry->label_len && buf_offset + i < 4096; i++) {
        buf[buf_offset + i] = toc_strings[entry->label_offset + i];
    }
    return entry->label_len;
}

int epub_get_toc_chapter(int toc_index) {
    if (toc_index < 0 || toc_index >= toc_count) return -1;
    return toc_entries[toc_index].spine_index;
}

int epub_get_toc_level(int toc_index) {
    if (toc_index < 0 || toc_index >= toc_count) return 0;
    return toc_entries[toc_index].nesting_level;
}

int epub_get_chapter_title(int spine_index, int buf_offset) {
    if (spine_index < 0 || spine_index >= spine_count) return 0;

    unsigned char* buf = get_string_buffer_ptr();

    /* Find first TOC entry that matches this spine index */
    for (int i = 0; i < toc_count; i++) {
        if (toc_entries[i].spine_index == spine_index) {
            toc_entry_t* entry = &toc_entries[i];
            for (int j = 0; j < entry->label_len && buf_offset + j < 4096; j++) {
                buf[buf_offset + j] = toc_strings[entry->label_offset + j];
            }
            return entry->label_len;
        }
    }

    return 0;  /* No TOC entry found for this chapter */
}

/* M15: Helper to write uint16 LE to buffer */
static void write_u16(unsigned char* buf, int offset, int value) {
    buf[offset] = value & 0xff;
    buf[offset + 1] = (value >> 8) & 0xff;
}

/* M15: Helper to read uint16 LE from buffer */
static int read_u16(unsigned char* buf, int offset) {
    return buf[offset] | (buf[offset + 1] << 8);
}

/* M15: Helper to read int16 LE from buffer (signed) */
static int read_i16(unsigned char* buf, int offset) {
    int v = buf[offset] | (buf[offset + 1] << 8);
    if (v >= 0x8000) v -= 0x10000;
    return v;
}

/* M15: Serialize book metadata to fetch buffer.
 * Returns [len:nat] total bytes written.
 *
 * Format (symmetric with epub_restore_metadata for METADATA_ROUNDTRIP):
 *   u16: book_id_len, bytes: book_id
 *   u16: title_len, bytes: title
 *   u16: author_len, bytes: author
 *   u16: opf_dir_len, bytes: opf_dir
 *   u16: spine_count
 *   for each spine entry: u16: href_len, bytes: href
 *   u16: toc_count
 *   for each toc entry: u16: label_len, i16: spine_index, u16: level, bytes: label
 *
 * CORRECTNESS: Field order matches epub_restore_metadata exactly.
 * Each field is read back in the same order it was written.
 * This symmetric structure establishes METADATA_ROUNDTRIP. */
int epub_serialize_metadata(void) {
    unsigned char* buf = get_fetch_buffer_ptr();
    int pos = 0;
    int max = 16384;

    /* book_id */
    write_u16(buf, pos, book_id_len); pos += 2;
    for (int i = 0; i < book_id_len && pos < max; i++) buf[pos++] = book_id[i];

    /* title */
    write_u16(buf, pos, book_title_len); pos += 2;
    for (int i = 0; i < book_title_len && pos < max; i++) buf[pos++] = book_title[i];

    /* author */
    write_u16(buf, pos, book_author_len); pos += 2;
    for (int i = 0; i < book_author_len && pos < max; i++) buf[pos++] = book_author[i];

    /* opf_dir */
    write_u16(buf, pos, opf_dir_len); pos += 2;
    for (int i = 0; i < opf_dir_len && pos < max; i++) buf[pos++] = opf_dir[i];

    /* spine */
    write_u16(buf, pos, spine_count); pos += 2;
    for (int s = 0; s < spine_count; s++) {
        int mi = spine_manifest_indices[s];
        if (mi >= 0 && mi < manifest_count) {
            manifest_item_t* item = &manifest_items[mi];
            write_u16(buf, pos, item->href_len); pos += 2;
            for (int i = 0; i < item->href_len && pos < max; i++) {
                buf[pos++] = manifest_strings[item->href_offset + i];
            }
        } else {
            write_u16(buf, pos, 0); pos += 2;
        }
    }

    /* toc */
    write_u16(buf, pos, toc_count); pos += 2;
    for (int t = 0; t < toc_count; t++) {
        toc_entry_t* entry = &toc_entries[t];
        write_u16(buf, pos, entry->label_len); pos += 2;
        write_u16(buf, pos, (unsigned int)(entry->spine_index) & 0xffff); pos += 2;
        write_u16(buf, pos, entry->nesting_level); pos += 2;
        for (int i = 0; i < entry->label_len && pos < max; i++) {
            buf[pos++] = toc_strings[entry->label_offset + i];
        }
    }

    return pos;
}

/* M15: Restore book metadata from fetch buffer.
 * Returns [r:int | r == 0 || r == 1].
 *
 * CORRECTNESS: Reads fields in same order as epub_serialize_metadata
 * (METADATA_ROUNDTRIP). On success:
 * - epub_state set to EPUB_STATE_DONE (8), establishing EPUB_STATE_VALID
 * - spine/manifest/TOC arrays populated matching original import state
 * - epub_get_chapter_count(), epub_get_toc_count() return correct values
 * - Reader can load chapters and navigate TOC correctly */
int epub_restore_metadata(int len) {
    unsigned char* buf = get_fetch_buffer_ptr();
    int pos = 0;

    if (len < 12) return 0;  /* Minimum: 6 u16 headers */

    /* Reset state */
    epub_state = 8;  /* EPUB_STATE_DONE - ready to read */
    epub_progress = 100;
    manifest_count = 0;
    manifest_strings_offset = 0;
    spine_count = 0;
    toc_count = 0;
    toc_strings_offset = 0;

    /* book_id */
    int id_len = read_u16(buf, pos); pos += 2;
    if (id_len > MAX_BOOK_ID_LEN - 1) id_len = MAX_BOOK_ID_LEN - 1;
    for (int i = 0; i < id_len; i++) book_id[i] = buf[pos++];
    book_id[id_len] = 0;
    book_id_len = id_len;

    /* title */
    int tlen = read_u16(buf, pos); pos += 2;
    if (tlen > MAX_TITLE_LEN - 1) tlen = MAX_TITLE_LEN - 1;
    for (int i = 0; i < tlen; i++) book_title[i] = buf[pos++];
    book_title[tlen] = 0;
    book_title_len = tlen;

    /* author */
    int alen = read_u16(buf, pos); pos += 2;
    if (alen > MAX_AUTHOR_LEN - 1) alen = MAX_AUTHOR_LEN - 1;
    for (int i = 0; i < alen; i++) book_author[i] = buf[pos++];
    book_author[alen] = 0;
    book_author_len = alen;

    /* opf_dir */
    int dlen = read_u16(buf, pos); pos += 2;
    if (dlen > MAX_OPF_PATH_LEN - 1) dlen = MAX_OPF_PATH_LEN - 1;
    for (int i = 0; i < dlen; i++) opf_dir[i] = buf[pos++];
    opf_dir[dlen] = 0;
    opf_dir_len = dlen;

    /* spine: create one manifest item per spine entry */
    int sc = read_u16(buf, pos); pos += 2;
    if (sc > MAX_SPINE_ITEMS) sc = MAX_SPINE_ITEMS;
    spine_count = sc;
    manifest_count = 0;
    manifest_strings_offset = 0;

    for (int s = 0; s < sc; s++) {
        int href_len = read_u16(buf, pos); pos += 2;
        if (manifest_count < MAX_MANIFEST_ITEMS && manifest_strings_offset + href_len < 4096) {
            manifest_item_t* item = &manifest_items[manifest_count];
            item->id_offset = 0;
            item->id_len = 0;
            item->href_offset = manifest_strings_offset;
            item->href_len = href_len;
            item->media_type = 1;  /* xhtml */
            item->zip_index = -1;
            for (int i = 0; i < href_len; i++) {
                manifest_strings[manifest_strings_offset++] = buf[pos++];
            }
            spine_manifest_indices[s] = manifest_count;
            manifest_count++;
        } else {
            pos += href_len;
            spine_manifest_indices[s] = -1;
        }
    }

    /* toc */
    int tc = read_u16(buf, pos); pos += 2;
    if (tc > MAX_TOC_ENTRIES) tc = MAX_TOC_ENTRIES;
    toc_count = tc;
    toc_strings_offset = 0;

    for (int t = 0; t < tc; t++) {
        int label_len = read_u16(buf, pos); pos += 2;
        int spine_idx = read_i16(buf, pos); pos += 2;
        int level = read_u16(buf, pos); pos += 2;

        toc_entry_t* entry = &toc_entries[t];
        entry->label_offset = toc_strings_offset;
        entry->label_len = label_len;
        entry->href_offset = 0;
        entry->href_len = 0;
        entry->spine_index = spine_idx;
        entry->nesting_level = level;

        for (int i = 0; i < label_len && toc_strings_offset < 8192; i++) {
            toc_strings[toc_strings_offset++] = buf[pos++];
        }
    }

    return 1;
}

/* M15: Reset epub state to idle.
 * Postcondition: EPUB_RESET_TO_IDLE - state == 0, all metadata cleared.
 * After reset, epub module is equivalent to post-epub_init state. */
void epub_reset(void) {
    epub_state = 0;
    epub_progress = 0;
    epub_error_len = 0;
    file_handle = 0;
    file_size = 0;
    book_title_len = 0;
    book_author_len = 0;
    book_id_len = 0;
    opf_path_len = 0;
    opf_dir_len = 0;
    manifest_count = 0;
    manifest_strings_offset = 0;
    spine_count = 0;
    toc_count = 0;
    toc_strings_offset = 0;
    ncx_zip_index = -1;
    current_entry_index = 0;
    total_entries = 0;
    current_blob_handle = 0;
}
%}
