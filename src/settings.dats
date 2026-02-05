(* settings.dats - Reader settings implementation
 *
 * M14: Manages font size, font family, theme, line height, and margins.
 * Settings are applied as CSS variables and persisted to IndexedDB.
 *
 * Functional correctness: settings are clamped to valid ranges,
 * ensuring SETTINGS_VALID proof can always be constructed.
 *)

#define ATS_DYNLOADFLAG 0

staload "settings.sats"
staload "dom.sats"

%{^
/* Settings state */
static int setting_font_size = 18;
static int setting_font_family = 0;   /* FONT_SERIF */
static int setting_theme = 0;         /* THEME_LIGHT */
static int setting_line_height_tenths = 16;  /* 1.6 */
static int setting_margin = 2;        /* 2rem */

/* Settings UI state */
static int settings_visible = 0;
static int settings_overlay_id = 0;
static int settings_close_id = 0;
static int settings_root_id = 1;

/* Button IDs for click handling */
static int btn_font_minus_id = 0;
static int btn_font_plus_id = 0;
static int btn_font_family_id = 0;
static int btn_theme_light_id = 0;
static int btn_theme_dark_id = 0;
static int btn_theme_sepia_id = 0;
static int btn_lh_minus_id = 0;
static int btn_lh_plus_id = 0;
static int btn_margin_minus_id = 0;
static int btn_margin_plus_id = 0;

/* Display IDs for updating values */
static int disp_font_size_id = 0;
static int disp_font_family_id = 0;
static int disp_line_height_id = 0;
static int disp_margin_id = 0;

/* Save/load state */
static int settings_save_pending = 0;
static int settings_load_pending = 0;

/* String constants */
static const char str_div[] = "div";
static const char str_span[] = "span";
static const char str_class[] = "class";
static const char str_style[] = "style";

/* Overlay and container classes */
static const char str_settings_overlay[] = "settings-overlay";
static const char str_settings_modal[] = "settings-modal";
static const char str_settings_header[] = "settings-header";
static const char str_settings_title[] = "Reader Settings";
static const char str_settings_close[] = "settings-close";
static const char str_close_x[] = "\xc3\x97";  /* UTF-8 x */
static const char str_settings_body[] = "settings-body";
static const char str_settings_row[] = "settings-row";
static const char str_settings_label[] = "settings-label";
static const char str_settings_controls[] = "settings-controls";
static const char str_settings_btn[] = "settings-btn";
static const char str_settings_btn_active[] = "settings-btn active";
static const char str_settings_value[] = "settings-value";

/* Setting labels */
static const char str_font_size_label[] = "Font Size";
static const char str_font_family_label[] = "Font";
static const char str_theme_label[] = "Theme";
static const char str_line_height_label[] = "Line Spacing";
static const char str_margin_label[] = "Margins";

/* Font family names */
static const char str_serif[] = "Serif";
static const char str_sans[] = "Sans";
static const char str_mono[] = "Mono";

/* Theme names */
static const char str_light[] = "Light";
static const char str_dark[] = "Dark";
static const char str_sepia[] = "Sepia";

/* Button text */
static const char str_minus[] = "\xe2\x88\x92";  /* UTF-8 minus */
static const char str_plus[] = "+";
static const char str_px[] = "px";
static const char str_rem[] = "rem";

/* Theme colors */
static const char str_light_bg[] = "#fafaf8";
static const char str_light_fg[] = "#2a2a2a";
static const char str_dark_bg[] = "#1a1a1a";
static const char str_dark_fg[] = "#e0e0e0";
static const char str_sepia_bg[] = "#f4ecd8";
static const char str_sepia_fg[] = "#5b4636";

/* Font family CSS */
static const char str_serif_css[] = "Georgia,serif";
static const char str_sans_css[] = "system-ui,-apple-system,sans-serif";
static const char str_mono_css[] = "'Courier New',monospace";

/* External bridge imports */
extern unsigned char* get_fetch_buffer_ptr(void);
extern unsigned char* get_string_buffer_ptr(void);
extern void js_kv_get(void* store_ptr, int store_len, void* key_ptr, int key_len);
extern void js_kv_put(void* store_ptr, int store_len, void* key_ptr, int key_len, int data_offset, int data_len);

/* DOM functions */
extern void dom_init(void);
extern void* dom_root_proof(void);
extern void* dom_create_element(void*, int, int, void*, int);
extern void* dom_set_text_offset(void*, int, int, int);
extern void* dom_set_attr(void*, int, void*, int, void*, int);
extern void dom_remove_child(void*, int);
extern int dom_next_id(void);
extern void dom_drop_proof(void*);

/* Reader functions for re-measure after settings change */
extern int reader_is_active(void);
extern void reader_remeasure_all(void);

/* Forward declarations */
static void update_display_values(void);
static void apply_theme_to_body(void);
void settings_apply(void);
void settings_save(void);

/* Helper: clamp value to range */
static int clamp(int val, int min, int max) {
    if (val < min) return min;
    if (val > max) return max;
    return val;
}

/* Helper: append string to buffer */
static int append_str(unsigned char* buf, int pos, const char* str) {
    while (*str && pos < 16380) {
        buf[pos++] = *str++;
    }
    return pos;
}

/* Helper: append int to buffer */
static int append_int(unsigned char* buf, int pos, int val) {
    if (val >= 100) {
        buf[pos++] = '0' + (val / 100);
        buf[pos++] = '0' + ((val / 10) % 10);
        buf[pos++] = '0' + (val % 10);
    } else if (val >= 10) {
        buf[pos++] = '0' + (val / 10);
        buf[pos++] = '0' + (val % 10);
    } else {
        buf[pos++] = '0' + val;
    }
    return pos;
}

/* Initialize settings to defaults */
void settings_init(void) {
    setting_font_size = 18;
    setting_font_family = 0;
    setting_theme = 0;
    setting_line_height_tenths = 16;
    setting_margin = 2;
    settings_visible = 0;
    settings_overlay_id = 0;
}

/* Getters */
int settings_get_font_size(void) { return setting_font_size; }
int settings_get_font_family(void) { return setting_font_family; }
int settings_get_theme(void) { return setting_theme; }
int settings_get_line_height_tenths(void) { return setting_line_height_tenths; }
int settings_get_margin(void) { return setting_margin; }

/* Setters with clamping - enforce SETTINGS_VALID invariants */
void settings_set_font_size(int size) {
    setting_font_size = clamp(size, 14, 32);
}

void settings_set_font_family(int family) {
    setting_font_family = clamp(family, 0, 2);
}

void settings_set_theme(int theme) {
    setting_theme = clamp(theme, 0, 2);
}

void settings_set_line_height_tenths(int tenths) {
    setting_line_height_tenths = clamp(tenths, 14, 24);
}

void settings_set_margin(int margin) {
    setting_margin = clamp(margin, 1, 4);
}

/* Increment/decrement helpers */
void settings_increase_font_size(void) {
    settings_set_font_size(setting_font_size + 2);
    settings_apply();
    update_display_values();
    settings_save();
}

void settings_decrease_font_size(void) {
    settings_set_font_size(setting_font_size - 2);
    settings_apply();
    update_display_values();
    settings_save();
}

void settings_next_font_family(void) {
    setting_font_family = (setting_font_family + 1) % 3;
    settings_apply();
    update_display_values();
    settings_save();
}

void settings_next_theme(void) {
    setting_theme = (setting_theme + 1) % 3;
    settings_apply();
    apply_theme_to_body();
    update_display_values();
    settings_save();
}

void settings_increase_line_height(void) {
    settings_set_line_height_tenths(setting_line_height_tenths + 1);
    settings_apply();
    update_display_values();
    settings_save();
}

void settings_decrease_line_height(void) {
    settings_set_line_height_tenths(setting_line_height_tenths - 1);
    settings_apply();
    update_display_values();
    settings_save();
}

void settings_increase_margin(void) {
    settings_set_margin(setting_margin + 1);
    settings_apply();
    update_display_values();
    settings_save();
}

void settings_decrease_margin(void) {
    settings_set_margin(setting_margin - 1);
    settings_apply();
    update_display_values();
    settings_save();
}

/* Build CSS variables string into fetch buffer
 * Returns: length of CSS string */
int settings_build_css_vars(int buf_offset) {
    unsigned char* buf = get_fetch_buffer_ptr() + buf_offset;
    int len = 0;

    /* --font-size: XXpx */
    len = append_str(buf, len, "--font-size:");
    len = append_int(buf, len, setting_font_size);
    len = append_str(buf, len, "px;");

    /* --font-family: ... */
    len = append_str(buf, len, "--font-family:");
    switch (setting_font_family) {
        case 0: len = append_str(buf, len, str_serif_css); break;
        case 1: len = append_str(buf, len, str_sans_css); break;
        case 2: len = append_str(buf, len, str_mono_css); break;
        default: len = append_str(buf, len, str_serif_css); break;
    }
    len = append_str(buf, len, ";");

    /* --line-height: X.X */
    len = append_str(buf, len, "--line-height:");
    len = append_int(buf, len, setting_line_height_tenths / 10);
    buf[len++] = '.';
    len = append_int(buf, len, setting_line_height_tenths % 10);
    len = append_str(buf, len, ";");

    /* --margin: Xrem */
    len = append_str(buf, len, "--margin:");
    len = append_int(buf, len, setting_margin);
    len = append_str(buf, len, "rem;");

    /* Theme colors */
    const char* bg_color;
    const char* fg_color;
    switch (setting_theme) {
        case 0:  /* Light */
            bg_color = str_light_bg;
            fg_color = str_light_fg;
            break;
        case 1:  /* Dark */
            bg_color = str_dark_bg;
            fg_color = str_dark_fg;
            break;
        case 2:  /* Sepia */
            bg_color = str_sepia_bg;
            fg_color = str_sepia_fg;
            break;
        default:
            bg_color = str_light_bg;
            fg_color = str_light_fg;
            break;
    }

    len = append_str(buf, len, "--bg-color:");
    len = append_str(buf, len, bg_color);
    len = append_str(buf, len, ";");

    len = append_str(buf, len, "--text-color:");
    len = append_str(buf, len, fg_color);

    return len;
}

/* Apply theme to body element directly */
static void apply_theme_to_body(void) {
    unsigned char* str_buf = get_string_buffer_ptr();
    void* pf = dom_root_proof();

    /* Build style string */
    int len = 0;
    const char* bg;
    const char* fg;

    switch (setting_theme) {
        case 0: bg = str_light_bg; fg = str_light_fg; break;
        case 1: bg = str_dark_bg; fg = str_dark_fg; break;
        case 2: bg = str_sepia_bg; fg = str_sepia_fg; break;
        default: bg = str_light_bg; fg = str_light_fg; break;
    }

    len = append_str(str_buf, len, "background:");
    len = append_str(str_buf, len, bg);
    len = append_str(str_buf, len, ";color:");
    len = append_str(str_buf, len, fg);

    dom_set_attr(pf, 1, (void*)str_style, 5, str_buf, len);
    dom_drop_proof(pf);
}

/* Apply settings - called after any setting change */
void settings_apply(void) {
    /* If reader is active, tell it to re-measure all chapters */
    if (reader_is_active()) {
        reader_remeasure_all();
    }
}

/* Save settings to IndexedDB */
void settings_save(void) {
    unsigned char* buf = get_fetch_buffer_ptr();
    unsigned char* str_buf = get_string_buffer_ptr();

    /* Serialize settings: 5 x int16 little-endian = 10 bytes */
    buf[0] = setting_font_size & 0xff;
    buf[1] = (setting_font_size >> 8) & 0xff;
    buf[2] = setting_font_family & 0xff;
    buf[3] = (setting_font_family >> 8) & 0xff;
    buf[4] = setting_theme & 0xff;
    buf[5] = (setting_theme >> 8) & 0xff;
    buf[6] = setting_line_height_tenths & 0xff;
    buf[7] = (setting_line_height_tenths >> 8) & 0xff;
    buf[8] = setting_margin & 0xff;
    buf[9] = (setting_margin >> 8) & 0xff;

    /* Key: "reader-settings" */
    static const char key[] = "reader-settings";
    for (int i = 0; i < 15; i++) {
        str_buf[i] = key[i];
    }

    /* Store: "settings" */
    static const char store[] = "settings";
    settings_save_pending = 1;
    js_kv_put((void*)store, 8, str_buf, 15, 0, 10);
}

/* Load settings from IndexedDB */
void settings_load(void) {
    unsigned char* str_buf = get_string_buffer_ptr();

    /* Key: "reader-settings" */
    static const char key[] = "reader-settings";
    for (int i = 0; i < 15; i++) {
        str_buf[i] = key[i];
    }

    /* Store: "settings" */
    static const char store[] = "settings";
    settings_load_pending = 1;
    js_kv_get((void*)store, 8, str_buf, 15);
}

/* Handle settings load completion */
void settings_on_load_complete(int len) {
    settings_load_pending = 0;

    if (len < 10) {
        /* No settings saved, use defaults */
        return;
    }

    unsigned char* buf = get_fetch_buffer_ptr();

    /* Deserialize settings */
    int fs = buf[0] | (buf[1] << 8);
    int ff = buf[2] | (buf[3] << 8);
    int th = buf[4] | (buf[5] << 8);
    int lh = buf[6] | (buf[7] << 8);
    int mg = buf[8] | (buf[9] << 8);

    /* Apply with validation (clamp enforces SETTINGS_VALID) */
    settings_set_font_size(fs);
    settings_set_font_family(ff);
    settings_set_theme(th);
    settings_set_line_height_tenths(lh);
    settings_set_margin(mg);

    /* Apply to UI */
    apply_theme_to_body();
    settings_apply();
}

/* Handle settings save completion */
void settings_on_save_complete(int success) {
    settings_save_pending = 0;
    /* Silently ignore save failures - settings still applied in memory */
}

/* Check if settings modal is visible */
int settings_is_visible(void) {
    return settings_visible;
}

/* Get settings overlay ID */
int settings_get_overlay_id(void) {
    return settings_overlay_id;
}

/* Update display values in settings UI */
static void update_display_values(void) {
    if (!settings_visible) return;

    unsigned char* buf = get_fetch_buffer_ptr();
    void* pf = dom_root_proof();
    int len;

    /* Font size: "XXpx" */
    if (disp_font_size_id > 0) {
        len = 0;
        len = append_int(buf, len, setting_font_size);
        len = append_str(buf, len, "px");
        dom_set_text_offset(pf, disp_font_size_id, 0, len);
    }

    /* Font family name */
    if (disp_font_family_id > 0) {
        const char* family_name;
        int family_len;
        switch (setting_font_family) {
            case 0: family_name = str_serif; family_len = 5; break;
            case 1: family_name = str_sans; family_len = 4; break;
            case 2: family_name = str_mono; family_len = 4; break;
            default: family_name = str_serif; family_len = 5; break;
        }
        for (int i = 0; i < family_len; i++) buf[i] = family_name[i];
        dom_set_text_offset(pf, disp_font_family_id, 0, family_len);
    }

    /* Line height: "X.X" */
    if (disp_line_height_id > 0) {
        len = 0;
        len = append_int(buf, len, setting_line_height_tenths / 10);
        buf[len++] = '.';
        len = append_int(buf, len, setting_line_height_tenths % 10);
        dom_set_text_offset(pf, disp_line_height_id, 0, len);
    }

    /* Margin: "Xrem" */
    if (disp_margin_id > 0) {
        len = 0;
        len = append_int(buf, len, setting_margin);
        len = append_str(buf, len, "rem");
        dom_set_text_offset(pf, disp_margin_id, 0, len);
    }

    /* Update theme button active states */
    unsigned char* str_buf = get_string_buffer_ptr();
    if (btn_theme_light_id > 0) {
        if (setting_theme == 0) {
            dom_set_attr(pf, btn_theme_light_id, (void*)str_class, 5,
                        (void*)str_settings_btn_active, 19);
        } else {
            dom_set_attr(pf, btn_theme_light_id, (void*)str_class, 5,
                        (void*)str_settings_btn, 12);
        }
    }
    if (btn_theme_dark_id > 0) {
        if (setting_theme == 1) {
            dom_set_attr(pf, btn_theme_dark_id, (void*)str_class, 5,
                        (void*)str_settings_btn_active, 19);
        } else {
            dom_set_attr(pf, btn_theme_dark_id, (void*)str_class, 5,
                        (void*)str_settings_btn, 12);
        }
    }
    if (btn_theme_sepia_id > 0) {
        if (setting_theme == 2) {
            dom_set_attr(pf, btn_theme_sepia_id, (void*)str_class, 5,
                        (void*)str_settings_btn_active, 19);
        } else {
            dom_set_attr(pf, btn_theme_sepia_id, (void*)str_class, 5,
                        (void*)str_settings_btn, 12);
        }
    }

    dom_drop_proof(pf);
}

/* Show settings modal */
void settings_show(void) {
    if (settings_visible) return;

    unsigned char* buf = get_fetch_buffer_ptr();
    void* pf = dom_root_proof();
    int len;

    /* Create overlay */
    int overlay_id = dom_next_id();
    settings_overlay_id = overlay_id;
    void* pf_overlay = dom_create_element(pf, settings_root_id, overlay_id, (void*)str_div, 3);
    pf_overlay = dom_set_attr(pf_overlay, overlay_id, (void*)str_class, 5,
                              (void*)str_settings_overlay, 16);

    /* Create modal container */
    int modal_id = dom_next_id();
    void* pf_modal = dom_create_element(pf_overlay, overlay_id, modal_id, (void*)str_div, 3);
    pf_modal = dom_set_attr(pf_modal, modal_id, (void*)str_class, 5,
                            (void*)str_settings_modal, 14);

    /* Header */
    int header_id = dom_next_id();
    void* pf_header = dom_create_element(pf_modal, modal_id, header_id, (void*)str_div, 3);
    pf_header = dom_set_attr(pf_header, header_id, (void*)str_class, 5,
                             (void*)str_settings_header, 15);
    len = 0;
    len = append_str(buf, len, str_settings_title);
    dom_set_text_offset(pf_header, header_id, 0, len);

    /* Close button */
    int close_id = dom_next_id();
    settings_close_id = close_id;
    void* pf_close = dom_create_element(pf_header, header_id, close_id, (void*)str_div, 3);
    pf_close = dom_set_attr(pf_close, close_id, (void*)str_class, 5,
                            (void*)str_settings_close, 14);
    len = 0;
    len = append_str(buf, len, str_close_x);
    dom_set_text_offset(pf_close, close_id, 0, len);
    dom_drop_proof(pf_close);
    dom_drop_proof(pf_header);

    /* Body */
    int body_id = dom_next_id();
    void* pf_body = dom_create_element(pf_modal, modal_id, body_id, (void*)str_div, 3);
    pf_body = dom_set_attr(pf_body, body_id, (void*)str_class, 5,
                           (void*)str_settings_body, 13);

    /* === Font Size Row === */
    int row1_id = dom_next_id();
    void* pf_row1 = dom_create_element(pf_body, body_id, row1_id, (void*)str_div, 3);
    pf_row1 = dom_set_attr(pf_row1, row1_id, (void*)str_class, 5,
                           (void*)str_settings_row, 12);

    /* Label */
    int lbl1_id = dom_next_id();
    void* pf_lbl1 = dom_create_element(pf_row1, row1_id, lbl1_id, (void*)str_div, 3);
    pf_lbl1 = dom_set_attr(pf_lbl1, lbl1_id, (void*)str_class, 5,
                           (void*)str_settings_label, 14);
    len = 0;
    len = append_str(buf, len, str_font_size_label);
    dom_set_text_offset(pf_lbl1, lbl1_id, 0, len);
    dom_drop_proof(pf_lbl1);

    /* Controls */
    int ctrl1_id = dom_next_id();
    void* pf_ctrl1 = dom_create_element(pf_row1, row1_id, ctrl1_id, (void*)str_div, 3);
    pf_ctrl1 = dom_set_attr(pf_ctrl1, ctrl1_id, (void*)str_class, 5,
                            (void*)str_settings_controls, 17);

    /* Minus button */
    btn_font_minus_id = dom_next_id();
    void* pf_btn = dom_create_element(pf_ctrl1, ctrl1_id, btn_font_minus_id, (void*)str_div, 3);
    pf_btn = dom_set_attr(pf_btn, btn_font_minus_id, (void*)str_class, 5,
                          (void*)str_settings_btn, 12);
    len = 0;
    len = append_str(buf, len, str_minus);
    dom_set_text_offset(pf_btn, btn_font_minus_id, 0, len);
    dom_drop_proof(pf_btn);

    /* Value display */
    disp_font_size_id = dom_next_id();
    void* pf_val = dom_create_element(pf_ctrl1, ctrl1_id, disp_font_size_id, (void*)str_div, 3);
    pf_val = dom_set_attr(pf_val, disp_font_size_id, (void*)str_class, 5,
                          (void*)str_settings_value, 14);
    len = 0;
    len = append_int(buf, len, setting_font_size);
    len = append_str(buf, len, "px");
    dom_set_text_offset(pf_val, disp_font_size_id, 0, len);
    dom_drop_proof(pf_val);

    /* Plus button */
    btn_font_plus_id = dom_next_id();
    pf_btn = dom_create_element(pf_ctrl1, ctrl1_id, btn_font_plus_id, (void*)str_div, 3);
    pf_btn = dom_set_attr(pf_btn, btn_font_plus_id, (void*)str_class, 5,
                          (void*)str_settings_btn, 12);
    len = 0;
    len = append_str(buf, len, str_plus);
    dom_set_text_offset(pf_btn, btn_font_plus_id, 0, len);
    dom_drop_proof(pf_btn);

    dom_drop_proof(pf_ctrl1);
    dom_drop_proof(pf_row1);

    /* === Font Family Row === */
    int row2_id = dom_next_id();
    void* pf_row2 = dom_create_element(pf_body, body_id, row2_id, (void*)str_div, 3);
    pf_row2 = dom_set_attr(pf_row2, row2_id, (void*)str_class, 5,
                           (void*)str_settings_row, 12);

    int lbl2_id = dom_next_id();
    void* pf_lbl2 = dom_create_element(pf_row2, row2_id, lbl2_id, (void*)str_div, 3);
    pf_lbl2 = dom_set_attr(pf_lbl2, lbl2_id, (void*)str_class, 5,
                           (void*)str_settings_label, 14);
    len = 0;
    len = append_str(buf, len, str_font_family_label);
    dom_set_text_offset(pf_lbl2, lbl2_id, 0, len);
    dom_drop_proof(pf_lbl2);

    int ctrl2_id = dom_next_id();
    void* pf_ctrl2 = dom_create_element(pf_row2, row2_id, ctrl2_id, (void*)str_div, 3);
    pf_ctrl2 = dom_set_attr(pf_ctrl2, ctrl2_id, (void*)str_class, 5,
                            (void*)str_settings_controls, 17);

    /* Font family cycle button */
    btn_font_family_id = dom_next_id();
    disp_font_family_id = btn_font_family_id;  /* Button IS the display */
    pf_btn = dom_create_element(pf_ctrl2, ctrl2_id, btn_font_family_id, (void*)str_div, 3);
    pf_btn = dom_set_attr(pf_btn, btn_font_family_id, (void*)str_class, 5,
                          (void*)str_settings_btn, 12);
    const char* family_name;
    int family_len;
    switch (setting_font_family) {
        case 0: family_name = str_serif; family_len = 5; break;
        case 1: family_name = str_sans; family_len = 4; break;
        case 2: family_name = str_mono; family_len = 4; break;
        default: family_name = str_serif; family_len = 5; break;
    }
    for (int i = 0; i < family_len; i++) buf[i] = family_name[i];
    dom_set_text_offset(pf_btn, btn_font_family_id, 0, family_len);
    dom_drop_proof(pf_btn);

    dom_drop_proof(pf_ctrl2);
    dom_drop_proof(pf_row2);

    /* === Theme Row === */
    int row3_id = dom_next_id();
    void* pf_row3 = dom_create_element(pf_body, body_id, row3_id, (void*)str_div, 3);
    pf_row3 = dom_set_attr(pf_row3, row3_id, (void*)str_class, 5,
                           (void*)str_settings_row, 12);

    int lbl3_id = dom_next_id();
    void* pf_lbl3 = dom_create_element(pf_row3, row3_id, lbl3_id, (void*)str_div, 3);
    pf_lbl3 = dom_set_attr(pf_lbl3, lbl3_id, (void*)str_class, 5,
                           (void*)str_settings_label, 14);
    len = 0;
    len = append_str(buf, len, str_theme_label);
    dom_set_text_offset(pf_lbl3, lbl3_id, 0, len);
    dom_drop_proof(pf_lbl3);

    int ctrl3_id = dom_next_id();
    void* pf_ctrl3 = dom_create_element(pf_row3, row3_id, ctrl3_id, (void*)str_div, 3);
    pf_ctrl3 = dom_set_attr(pf_ctrl3, ctrl3_id, (void*)str_class, 5,
                            (void*)str_settings_controls, 17);

    /* Light button */
    btn_theme_light_id = dom_next_id();
    pf_btn = dom_create_element(pf_ctrl3, ctrl3_id, btn_theme_light_id, (void*)str_div, 3);
    pf_btn = dom_set_attr(pf_btn, btn_theme_light_id, (void*)str_class, 5,
                          setting_theme == 0 ? (void*)str_settings_btn_active : (void*)str_settings_btn,
                          setting_theme == 0 ? 19 : 12);
    len = 0;
    len = append_str(buf, len, str_light);
    dom_set_text_offset(pf_btn, btn_theme_light_id, 0, len);
    dom_drop_proof(pf_btn);

    /* Dark button */
    btn_theme_dark_id = dom_next_id();
    pf_btn = dom_create_element(pf_ctrl3, ctrl3_id, btn_theme_dark_id, (void*)str_div, 3);
    pf_btn = dom_set_attr(pf_btn, btn_theme_dark_id, (void*)str_class, 5,
                          setting_theme == 1 ? (void*)str_settings_btn_active : (void*)str_settings_btn,
                          setting_theme == 1 ? 19 : 12);
    len = 0;
    len = append_str(buf, len, str_dark);
    dom_set_text_offset(pf_btn, btn_theme_dark_id, 0, len);
    dom_drop_proof(pf_btn);

    /* Sepia button */
    btn_theme_sepia_id = dom_next_id();
    pf_btn = dom_create_element(pf_ctrl3, ctrl3_id, btn_theme_sepia_id, (void*)str_div, 3);
    pf_btn = dom_set_attr(pf_btn, btn_theme_sepia_id, (void*)str_class, 5,
                          setting_theme == 2 ? (void*)str_settings_btn_active : (void*)str_settings_btn,
                          setting_theme == 2 ? 19 : 12);
    len = 0;
    len = append_str(buf, len, str_sepia);
    dom_set_text_offset(pf_btn, btn_theme_sepia_id, 0, len);
    dom_drop_proof(pf_btn);

    dom_drop_proof(pf_ctrl3);
    dom_drop_proof(pf_row3);

    /* === Line Height Row === */
    int row4_id = dom_next_id();
    void* pf_row4 = dom_create_element(pf_body, body_id, row4_id, (void*)str_div, 3);
    pf_row4 = dom_set_attr(pf_row4, row4_id, (void*)str_class, 5,
                           (void*)str_settings_row, 12);

    int lbl4_id = dom_next_id();
    void* pf_lbl4 = dom_create_element(pf_row4, row4_id, lbl4_id, (void*)str_div, 3);
    pf_lbl4 = dom_set_attr(pf_lbl4, lbl4_id, (void*)str_class, 5,
                           (void*)str_settings_label, 14);
    len = 0;
    len = append_str(buf, len, str_line_height_label);
    dom_set_text_offset(pf_lbl4, lbl4_id, 0, len);
    dom_drop_proof(pf_lbl4);

    int ctrl4_id = dom_next_id();
    void* pf_ctrl4 = dom_create_element(pf_row4, row4_id, ctrl4_id, (void*)str_div, 3);
    pf_ctrl4 = dom_set_attr(pf_ctrl4, ctrl4_id, (void*)str_class, 5,
                            (void*)str_settings_controls, 17);

    btn_lh_minus_id = dom_next_id();
    pf_btn = dom_create_element(pf_ctrl4, ctrl4_id, btn_lh_minus_id, (void*)str_div, 3);
    pf_btn = dom_set_attr(pf_btn, btn_lh_minus_id, (void*)str_class, 5,
                          (void*)str_settings_btn, 12);
    len = 0;
    len = append_str(buf, len, str_minus);
    dom_set_text_offset(pf_btn, btn_lh_minus_id, 0, len);
    dom_drop_proof(pf_btn);

    disp_line_height_id = dom_next_id();
    pf_val = dom_create_element(pf_ctrl4, ctrl4_id, disp_line_height_id, (void*)str_div, 3);
    pf_val = dom_set_attr(pf_val, disp_line_height_id, (void*)str_class, 5,
                          (void*)str_settings_value, 14);
    len = 0;
    len = append_int(buf, len, setting_line_height_tenths / 10);
    buf[len++] = '.';
    len = append_int(buf, len, setting_line_height_tenths % 10);
    dom_set_text_offset(pf_val, disp_line_height_id, 0, len);
    dom_drop_proof(pf_val);

    btn_lh_plus_id = dom_next_id();
    pf_btn = dom_create_element(pf_ctrl4, ctrl4_id, btn_lh_plus_id, (void*)str_div, 3);
    pf_btn = dom_set_attr(pf_btn, btn_lh_plus_id, (void*)str_class, 5,
                          (void*)str_settings_btn, 12);
    len = 0;
    len = append_str(buf, len, str_plus);
    dom_set_text_offset(pf_btn, btn_lh_plus_id, 0, len);
    dom_drop_proof(pf_btn);

    dom_drop_proof(pf_ctrl4);
    dom_drop_proof(pf_row4);

    /* === Margin Row === */
    int row5_id = dom_next_id();
    void* pf_row5 = dom_create_element(pf_body, body_id, row5_id, (void*)str_div, 3);
    pf_row5 = dom_set_attr(pf_row5, row5_id, (void*)str_class, 5,
                           (void*)str_settings_row, 12);

    int lbl5_id = dom_next_id();
    void* pf_lbl5 = dom_create_element(pf_row5, row5_id, lbl5_id, (void*)str_div, 3);
    pf_lbl5 = dom_set_attr(pf_lbl5, lbl5_id, (void*)str_class, 5,
                           (void*)str_settings_label, 14);
    len = 0;
    len = append_str(buf, len, str_margin_label);
    dom_set_text_offset(pf_lbl5, lbl5_id, 0, len);
    dom_drop_proof(pf_lbl5);

    int ctrl5_id = dom_next_id();
    void* pf_ctrl5 = dom_create_element(pf_row5, row5_id, ctrl5_id, (void*)str_div, 3);
    pf_ctrl5 = dom_set_attr(pf_ctrl5, ctrl5_id, (void*)str_class, 5,
                            (void*)str_settings_controls, 17);

    btn_margin_minus_id = dom_next_id();
    pf_btn = dom_create_element(pf_ctrl5, ctrl5_id, btn_margin_minus_id, (void*)str_div, 3);
    pf_btn = dom_set_attr(pf_btn, btn_margin_minus_id, (void*)str_class, 5,
                          (void*)str_settings_btn, 12);
    len = 0;
    len = append_str(buf, len, str_minus);
    dom_set_text_offset(pf_btn, btn_margin_minus_id, 0, len);
    dom_drop_proof(pf_btn);

    disp_margin_id = dom_next_id();
    pf_val = dom_create_element(pf_ctrl5, ctrl5_id, disp_margin_id, (void*)str_div, 3);
    pf_val = dom_set_attr(pf_val, disp_margin_id, (void*)str_class, 5,
                          (void*)str_settings_value, 14);
    len = 0;
    len = append_int(buf, len, setting_margin);
    len = append_str(buf, len, "rem");
    dom_set_text_offset(pf_val, disp_margin_id, 0, len);
    dom_drop_proof(pf_val);

    btn_margin_plus_id = dom_next_id();
    pf_btn = dom_create_element(pf_ctrl5, ctrl5_id, btn_margin_plus_id, (void*)str_div, 3);
    pf_btn = dom_set_attr(pf_btn, btn_margin_plus_id, (void*)str_class, 5,
                          (void*)str_settings_btn, 12);
    len = 0;
    len = append_str(buf, len, str_plus);
    dom_set_text_offset(pf_btn, btn_margin_plus_id, 0, len);
    dom_drop_proof(pf_btn);

    dom_drop_proof(pf_ctrl5);
    dom_drop_proof(pf_row5);

    dom_drop_proof(pf_body);
    dom_drop_proof(pf_modal);
    dom_drop_proof(pf_overlay);
    dom_drop_proof(pf);

    settings_visible = 1;
}

/* Hide settings modal */
void settings_hide(void) {
    if (!settings_visible || settings_overlay_id == 0) return;

    void* pf = dom_root_proof();
    dom_remove_child(pf, settings_overlay_id);
    dom_drop_proof(pf);

    settings_visible = 0;
    settings_overlay_id = 0;
    settings_close_id = 0;

    /* Clear button IDs */
    btn_font_minus_id = 0;
    btn_font_plus_id = 0;
    btn_font_family_id = 0;
    btn_theme_light_id = 0;
    btn_theme_dark_id = 0;
    btn_theme_sepia_id = 0;
    btn_lh_minus_id = 0;
    btn_lh_plus_id = 0;
    btn_margin_minus_id = 0;
    btn_margin_plus_id = 0;

    /* Clear display IDs */
    disp_font_size_id = 0;
    disp_font_family_id = 0;
    disp_line_height_id = 0;
    disp_margin_id = 0;
}

/* Toggle settings modal */
void settings_toggle(void) {
    if (settings_visible) {
        settings_hide();
    } else {
        settings_show();
    }
}

/* Handle click on settings UI element
 * Returns 1 if handled, 0 if not */
int settings_handle_click(int node_id) {
    if (!settings_visible) return 0;

    /* Close button */
    if (node_id == settings_close_id) {
        settings_hide();
        return 1;
    }

    /* Font size */
    if (node_id == btn_font_minus_id) {
        settings_decrease_font_size();
        return 1;
    }
    if (node_id == btn_font_plus_id) {
        settings_increase_font_size();
        return 1;
    }

    /* Font family */
    if (node_id == btn_font_family_id) {
        settings_next_font_family();
        return 1;
    }

    /* Theme */
    if (node_id == btn_theme_light_id) {
        settings_set_theme(0);
        settings_apply();
        apply_theme_to_body();
        update_display_values();
        settings_save();
        return 1;
    }
    if (node_id == btn_theme_dark_id) {
        settings_set_theme(1);
        settings_apply();
        apply_theme_to_body();
        update_display_values();
        settings_save();
        return 1;
    }
    if (node_id == btn_theme_sepia_id) {
        settings_set_theme(2);
        settings_apply();
        apply_theme_to_body();
        update_display_values();
        settings_save();
        return 1;
    }

    /* Line height */
    if (node_id == btn_lh_minus_id) {
        settings_decrease_line_height();
        return 1;
    }
    if (node_id == btn_lh_plus_id) {
        settings_increase_line_height();
        return 1;
    }

    /* Margin */
    if (node_id == btn_margin_minus_id) {
        settings_decrease_margin();
        return 1;
    }
    if (node_id == btn_margin_plus_id) {
        settings_increase_margin();
        return 1;
    }

    return 0;
}

/* Set the root node ID for creating overlays */
void settings_set_root_id(int id) {
    settings_root_id = id;
}

/* Check if settings save is pending */
int settings_is_save_pending(void) {
    return settings_save_pending;
}

/* Check if settings load is pending */
int settings_is_load_pending(void) {
    return settings_load_pending;
}
%}

(* All implementations are in the C block above via "mac#" linkage *)
