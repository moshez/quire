/* quire_decls.h — C forward declarations for cross-module mac# functions.
 *
 * ATS2 mac# declarations don't generate C prototypes (ATSdyncst_mac is a
 * no-op in ward's runtime.h). Functions implemented via ext# in one .dats
 * file and called via mac# from others need explicit C prototypes to avoid
 * -Wimplicit-function-declaration warnings.
 *
 * These functions are implemented in buf.dats (buf_*) and app_state.dats
 * (get_*_buffer_ptr). The ATS-level typed APIs live in buf.sats. */

#ifndef QUIRE_DECLS_H
#define QUIRE_DECLS_H

/* buf.dats ext# — raw byte/i32 buffer access */
int buf_get_u8(void *p, int off);
void buf_set_u8(void *p, int off, int v);
int buf_get_i32(void *p, int idx);
void buf_set_i32(void *p, int idx, int v);

/* app_state.dats ext# — buffer pointer accessors */
void *get_string_buffer_ptr(void);
void *get_fetch_buffer_ptr(void);
void *get_diff_buffer_ptr(void);

/* App CSS — injected as <style> text content from WASM.
 * reader.css only has loading-screen styles; everything else lives here. */
static const char _app_css[] =
  "html,body{margin:0;padding:0;background:#fafaf8;color:#2a2a2a;"
  "font-family:Georgia,serif;font-size:18px;line-height:1.6}"
  ".import-btn{display:inline-block;padding:.5rem 1.2rem;margin:1rem;"
  "background:#4a7c59;color:#fff;border-radius:4px;cursor:pointer;font-size:1rem}"
  ".import-btn input[type=file]{display:none}"
  ".library-list{padding:1rem}"
  ".empty-lib{color:#888;text-align:center;padding:2rem;font-style:italic}"
  ".book-card{display:flex;align-items:center;padding:.75rem 1rem;"
  "margin-bottom:.5rem;background:#fff;border:1px solid #e0e0e0;border-radius:6px}"
  ".book-title{font-weight:bold;margin-right:.5rem}"
  ".book-author{color:#666;margin-right:auto}"
  ".book-position{color:#999;font-size:.85rem;margin-right:1rem}"
  ".read-btn{padding:.4rem 1rem;background:#4a7c59;color:#fff;"
  "border:none;border-radius:4px;cursor:pointer}"
  ".reader-viewport{width:100vw;height:100vh;overflow:hidden;position:relative}"
  ".chapter-container{column-width:100vw;column-gap:0;"
  "height:calc(100vh - 4rem);overflow:visible;"
  "padding:2rem 1.5rem;box-sizing:border-box}"
  ".chapter-container h1,.chapter-container h2,.chapter-container h3"
  "{margin-top:1.5em;margin-bottom:.5em;line-height:1.3}"
  ".chapter-container p{margin:0 0 .8em;text-align:justify}"
  ".chapter-container blockquote{margin:1em 2em;padding-left:1em;"
  "border-left:3px solid #ccc;color:#555}"
  ".chapter-container pre{background:#f4f4f4;padding:.8em;"
  "border-radius:4px;overflow-x:auto;font-size:.9em}"
  ".chapter-container code{background:#f4f4f4;padding:.1em .3em;"
  "border-radius:2px;font-size:.9em}"
  ".chapter-container img{max-width:100%;height:auto}"
  ".chapter-container a{color:#4a7c59}"
  ".chapter-container table{border-collapse:collapse;margin:1em 0}"
  ".chapter-container td,.chapter-container th"
  "{border:1px solid #ddd;padding:.4em .8em}";
#define _app_css_len() ((int)(sizeof(_app_css) - 1))
static inline void _fill_css(void *dst) {
  memcpy(dst, _app_css, sizeof(_app_css) - 1);
}

#endif
