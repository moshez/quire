(* xml.dats - Minimal XML parser implementation
 *
 * Simple forward-only parser for EPUB XML files.
 * Not a full XML parser - handles the subset needed for EPUB.
 *)

#define ATS_DYNLOADFLAG 0

staload "xml.sats"

%{^
/* Minimal XML parser for EPUB metadata files
 *
 * Supports:
 * - Element tags (opening, closing, self-closing)
 * - Attributes with single or double quotes
 * - Basic text content
 *
 * Does NOT support:
 * - CDATA sections (treated as text)
 * - Processing instructions (skipped)
 * - Comments (skipped)
 * - Entities (passed through as-is)
 * - Namespaces (treated as part of element name)
 */

#include <stdint.h>

extern unsigned char* get_fetch_buffer_ptr(void);
extern unsigned char* get_string_buffer_ptr(void);

typedef struct {
    const unsigned char* data;
    int len;
    int pos;

    /* Current element info */
    int elem_start;     /* start of element name */
    int elem_len;       /* length of element name */
    int is_closing;     /* is this a closing tag */
    int is_self_closing;/* is this self-closing */
    int attrs_start;    /* start of attributes */
    int attrs_end;      /* end of attributes */
} xml_context_t;

static int is_whitespace(unsigned char c) {
    return c == ' ' || c == '\t' || c == '\n' || c == '\r';
}

static int is_name_char(unsigned char c) {
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
           (c >= '0' && c <= '9') || c == '_' || c == '-' || c == '.' || c == ':';
}

static void skip_whitespace(xml_context_t* ctx) {
    while (ctx->pos < ctx->len && is_whitespace(ctx->data[ctx->pos])) {
        ctx->pos++;
    }
}

/* Skip comment: <!-- ... --> */
static void skip_comment(xml_context_t* ctx) {
    if (ctx->pos + 4 > ctx->len) return;
    if (ctx->data[ctx->pos] != '<' || ctx->data[ctx->pos+1] != '!' ||
        ctx->data[ctx->pos+2] != '-' || ctx->data[ctx->pos+3] != '-') return;

    ctx->pos += 4;
    while (ctx->pos + 2 < ctx->len) {
        if (ctx->data[ctx->pos] == '-' && ctx->data[ctx->pos+1] == '-' &&
            ctx->data[ctx->pos+2] == '>') {
            ctx->pos += 3;
            return;
        }
        ctx->pos++;
    }
    ctx->pos = ctx->len;
}

/* Skip processing instruction: <? ... ?> */
static void skip_pi(xml_context_t* ctx) {
    if (ctx->pos + 2 > ctx->len) return;
    if (ctx->data[ctx->pos] != '<' || ctx->data[ctx->pos+1] != '?') return;

    ctx->pos += 2;
    while (ctx->pos + 1 < ctx->len) {
        if (ctx->data[ctx->pos] == '?' && ctx->data[ctx->pos+1] == '>') {
            ctx->pos += 2;
            return;
        }
        ctx->pos++;
    }
    ctx->pos = ctx->len;
}

/* Skip DOCTYPE: <!DOCTYPE ... > */
static void skip_doctype(xml_context_t* ctx) {
    if (ctx->pos + 9 > ctx->len) return;
    if (ctx->data[ctx->pos] != '<' || ctx->data[ctx->pos+1] != '!') return;

    /* Check for DOCTYPE (case insensitive D) */
    if ((ctx->data[ctx->pos+2] != 'D' && ctx->data[ctx->pos+2] != 'd')) return;

    ctx->pos += 2;
    int depth = 1;
    while (ctx->pos < ctx->len && depth > 0) {
        if (ctx->data[ctx->pos] == '<') depth++;
        else if (ctx->data[ctx->pos] == '>') depth--;
        ctx->pos++;
    }
}

/* Parse next element tag */
static int parse_element(xml_context_t* ctx) {
    skip_whitespace(ctx);

    /* Skip non-element content */
    while (ctx->pos < ctx->len) {
        if (ctx->data[ctx->pos] != '<') {
            ctx->pos++;
            continue;
        }

        /* Check for special tags */
        if (ctx->pos + 1 < ctx->len) {
            if (ctx->data[ctx->pos+1] == '!') {
                if (ctx->pos + 3 < ctx->len && ctx->data[ctx->pos+2] == '-' &&
                    ctx->data[ctx->pos+3] == '-') {
                    skip_comment(ctx);
                    continue;
                }
                skip_doctype(ctx);
                continue;
            }
            if (ctx->data[ctx->pos+1] == '?') {
                skip_pi(ctx);
                continue;
            }
        }
        break;
    }

    if (ctx->pos >= ctx->len) return 0;
    if (ctx->data[ctx->pos] != '<') return 0;

    ctx->pos++;  /* skip '<' */

    /* Check for closing tag */
    ctx->is_closing = 0;
    if (ctx->pos < ctx->len && ctx->data[ctx->pos] == '/') {
        ctx->is_closing = 1;
        ctx->pos++;
    }

    /* Parse element name */
    skip_whitespace(ctx);
    ctx->elem_start = ctx->pos;
    while (ctx->pos < ctx->len && is_name_char(ctx->data[ctx->pos])) {
        ctx->pos++;
    }
    ctx->elem_len = ctx->pos - ctx->elem_start;

    if (ctx->elem_len == 0) return 0;

    /* Parse attributes region */
    skip_whitespace(ctx);
    ctx->attrs_start = ctx->pos;

    /* Find end of tag */
    ctx->is_self_closing = 0;
    while (ctx->pos < ctx->len) {
        if (ctx->data[ctx->pos] == '>') {
            ctx->attrs_end = ctx->pos;
            ctx->pos++;
            break;
        }
        if (ctx->data[ctx->pos] == '/' && ctx->pos + 1 < ctx->len &&
            ctx->data[ctx->pos+1] == '>') {
            ctx->is_self_closing = 1;
            ctx->attrs_end = ctx->pos;
            ctx->pos += 2;
            break;
        }
        /* Skip over quoted attribute values */
        if (ctx->data[ctx->pos] == '"') {
            ctx->pos++;
            while (ctx->pos < ctx->len && ctx->data[ctx->pos] != '"') ctx->pos++;
            if (ctx->pos < ctx->len) ctx->pos++;
        } else if (ctx->data[ctx->pos] == '\'') {
            ctx->pos++;
            while (ctx->pos < ctx->len && ctx->data[ctx->pos] != '\'') ctx->pos++;
            if (ctx->pos < ctx->len) ctx->pos++;
        } else {
            ctx->pos++;
        }
    }

    return 1;
}

/* Find attribute value within attrs region */
static int find_attr_value(xml_context_t* ctx, const char* name, int name_len,
                           int* out_start, int* out_len) {
    int pos = ctx->attrs_start;

    while (pos < ctx->attrs_end) {
        /* Skip whitespace */
        while (pos < ctx->attrs_end && is_whitespace(ctx->data[pos])) pos++;
        if (pos >= ctx->attrs_end) break;

        /* Parse attribute name */
        int attr_name_start = pos;
        while (pos < ctx->attrs_end && is_name_char(ctx->data[pos])) pos++;
        int attr_name_len = pos - attr_name_start;

        /* Skip whitespace around '=' */
        while (pos < ctx->attrs_end && is_whitespace(ctx->data[pos])) pos++;
        if (pos >= ctx->attrs_end || ctx->data[pos] != '=') continue;
        pos++;
        while (pos < ctx->attrs_end && is_whitespace(ctx->data[pos])) pos++;

        /* Get quote char */
        if (pos >= ctx->attrs_end) break;
        char quote = ctx->data[pos];
        if (quote != '"' && quote != '\'') continue;
        pos++;

        /* Find value end */
        int value_start = pos;
        while (pos < ctx->attrs_end && ctx->data[pos] != quote) pos++;
        int value_len = pos - value_start;
        if (pos < ctx->attrs_end) pos++;

        /* Check if this is the attribute we want */
        if (attr_name_len == name_len) {
            int match = 1;
            for (int i = 0; i < name_len && match; i++) {
                if (ctx->data[attr_name_start + i] != (unsigned char)name[i]) {
                    match = 0;
                }
            }
            if (match) {
                *out_start = value_start;
                *out_len = value_len;
                return 1;
            }
        }
    }

    return 0;
}

/* Public API */

void* xml_init(int data_len) {
    xml_context_t* ctx = (xml_context_t*)malloc(sizeof(xml_context_t));
    if (!ctx) return 0;

    ctx->data = get_fetch_buffer_ptr();
    ctx->len = data_len;
    ctx->pos = 0;
    ctx->elem_start = 0;
    ctx->elem_len = 0;
    ctx->is_closing = 0;
    ctx->is_self_closing = 0;
    ctx->attrs_start = 0;
    ctx->attrs_end = 0;

    return ctx;
}

void xml_free(void* ctx_ptr) {
    /* Note: malloc'd memory, but we use bump allocator so free is no-op */
    (void)ctx_ptr;
}

int xml_next_element(void* ctx_ptr) {
    xml_context_t* ctx = (xml_context_t*)ctx_ptr;
    return parse_element(ctx);
}

int xml_get_element_name(void* ctx_ptr, int buf_offset) {
    xml_context_t* ctx = (xml_context_t*)ctx_ptr;
    unsigned char* buf = get_string_buffer_ptr();

    for (int i = 0; i < ctx->elem_len && buf_offset + i < 4096; i++) {
        buf[buf_offset + i] = ctx->data[ctx->elem_start + i];
    }

    return ctx->elem_len;
}

int xml_element_is(void* ctx_ptr, void* name_ptr, int name_len) {
    xml_context_t* ctx = (xml_context_t*)ctx_ptr;
    const char* name = (const char*)name_ptr;

    if (ctx->elem_len != name_len) return 0;

    for (int i = 0; i < name_len; i++) {
        unsigned char c1 = ctx->data[ctx->elem_start + i];
        unsigned char c2 = (unsigned char)name[i];
        /* Case-sensitive comparison */
        if (c1 != c2) return 0;
    }

    return 1;
}

int xml_get_attr(void* ctx_ptr, void* name_ptr, int name_len, int buf_offset) {
    xml_context_t* ctx = (xml_context_t*)ctx_ptr;
    unsigned char* buf = get_string_buffer_ptr();

    int value_start, value_len;
    if (!find_attr_value(ctx, (const char*)name_ptr, name_len, &value_start, &value_len)) {
        return 0;
    }

    for (int i = 0; i < value_len && buf_offset + i < 4096; i++) {
        buf[buf_offset + i] = ctx->data[value_start + i];
    }

    return value_len;
}

int xml_is_closing(void* ctx_ptr) {
    xml_context_t* ctx = (xml_context_t*)ctx_ptr;
    return ctx->is_closing;
}

int xml_is_self_closing(void* ctx_ptr) {
    xml_context_t* ctx = (xml_context_t*)ctx_ptr;
    return ctx->is_self_closing;
}

int xml_get_text_content(void* ctx_ptr, int buf_offset) {
    xml_context_t* ctx = (xml_context_t*)ctx_ptr;
    unsigned char* buf = get_string_buffer_ptr();

    int start = ctx->pos;
    int len = 0;

    /* Read until next tag or end */
    while (ctx->pos < ctx->len && ctx->data[ctx->pos] != '<') {
        if (buf_offset + len < 4096) {
            buf[buf_offset + len] = ctx->data[ctx->pos];
            len++;
        }
        ctx->pos++;
    }

    return len;
}

void xml_skip_element(void* ctx_ptr) {
    xml_context_t* ctx = (xml_context_t*)ctx_ptr;

    if (ctx->is_self_closing || ctx->is_closing) return;

    /* Remember element name to match closing tag */
    int target_start = ctx->elem_start;
    int target_len = ctx->elem_len;
    int depth = 1;

    while (depth > 0 && parse_element(ctx)) {
        /* Check if name matches */
        int matches = (ctx->elem_len == target_len);
        if (matches) {
            for (int i = 0; i < target_len && matches; i++) {
                if (ctx->data[ctx->elem_start + i] != ctx->data[target_start + i]) {
                    matches = 0;
                }
            }
        }

        if (matches) {
            if (ctx->is_closing) depth--;
            else if (!ctx->is_self_closing) depth++;
        }
    }
}
%}
