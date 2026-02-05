(* quire.dats - Implementation for Quire e-reader *)
(* Minimal freestanding version - no stdlib dependencies *)

staload "quire.sats"

%{^
/* C implementation of init - emits SET_TEXT diff */
extern unsigned char* get_diff_buffer_ptr(void);
extern unsigned char* get_fetch_buffer_ptr(void);

static void write_u32_le(unsigned char* buf, unsigned int v) {
    buf[0] = v & 0xFF;
    buf[1] = (v >> 8) & 0xFF;
    buf[2] = (v >> 16) & 0xFF;
    buf[3] = (v >> 24) & 0xFF;
}

void init(void) {
    unsigned char* fetch = get_fetch_buffer_ptr();
    unsigned char* diff = get_diff_buffer_ptr();

    /* Write "Quire" to fetch buffer at offset 0 */
    fetch[0] = 'Q'; fetch[1] = 'u'; fetch[2] = 'i';
    fetch[3] = 'r'; fetch[4] = 'e';

    /* Write SET_TEXT diff entry */
    /* Header: byte 0 = count */
    diff[0] = 1;

    /* Entry at offset 4 (16-byte aligned): op(4) + nodeId(4) + value1(4) + value2(4) */
    write_u32_le(diff + 4, 1);   /* op = SET_TEXT */
    write_u32_le(diff + 8, 1);   /* nodeId = 1 */
    write_u32_le(diff + 12, 0);  /* fetch offset = 0 */
    write_u32_le(diff + 16, 5);  /* length = 5 */
}

void process_event(void) {}
void on_fetch_complete(int status, int len) { (void)status; (void)len; }
void on_timer_complete(int callback_id) { (void)callback_id; }
void on_file_open_complete(int handle, int size) { (void)handle; (void)size; }
void on_decompress_complete(int handle, int size) { (void)handle; (void)size; }
void on_kv_complete(int success) { (void)success; }
void on_kv_get_complete(int len) { (void)len; }
void on_kv_get_blob_complete(int handle, int size) { (void)handle; (void)size; }
void on_clipboard_copy_complete(int success) { (void)success; }
%}
