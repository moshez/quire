/* quire_runtime.c — Minimal C extensions for quire */

/* quire_ptr_add and quire_get_byte are defined as macros in quire_prelude.h.
 * No function definitions needed here. */

/* Legacy buffer support for xml.dats and epub.dats (pre-ward modules).
 * These buffers were in the old runtime.c. They'll be eliminated
 * when these modules are fully migrated to ward APIs. */
#define STRING_BUFFER_SIZE 4096
#define FETCH_BUFFER_SIZE 16384
#define DIFF_BUFFER_SIZE 4096

static unsigned char _string_buffer[STRING_BUFFER_SIZE];
static unsigned char _fetch_buffer[FETCH_BUFFER_SIZE];
static unsigned char _diff_buffer[DIFF_BUFFER_SIZE];

unsigned char *get_string_buffer_ptr(void) { return _string_buffer; }
unsigned char *get_fetch_buffer_ptr(void) { return _fetch_buffer; }
unsigned char *get_diff_buffer_ptr(void) { return _diff_buffer; }

/* parseHTML result stash */
static void *_parse_html_ptr = 0;

void ward_parse_html_stash(void *p) {
    _parse_html_ptr = p;
}

void *ward_parse_html_get_ptr(void) {
    return _parse_html_ptr;
}
