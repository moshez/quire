(* modals.sats — Modal and banner declarations for duplicate, reset, error UI *)

staload "./../vendor/ward/lib/memory.sats"
staload "./../vendor/ward/lib/dom.sats"

(* ========== Duplicate modal CSS class builders ========== *)

fun cls_dup_overlay(): ward_safe_text(11)
fun cls_dup_modal(): ward_safe_text(9)
fun cls_dup_title(): ward_safe_text(9)
fun cls_dup_msg(): ward_safe_text(7)
fun cls_dup_actions(): ward_safe_text(11)
fun cls_dup_btn(): ward_safe_text(7)
fun cls_dup_replace(): ward_safe_text(11)

(* ========== Error banner CSS class builders ========== *)

fun cls_err_banner(): ward_safe_text(10)
fun cls_err_close(): ward_safe_text(9)

(* ========== Listener ID defines ========== *)

#define LISTENER_DUP_SKIP 34
#define LISTENER_DUP_REPLACE 35
#define LISTENER_RESET_BTN 36
#define LISTENER_RESET_CONFIRM 37
#define LISTENER_RESET_CANCEL 38
#define LISTENER_ERR_DISMISS 39

(* ========== Helper functions ========== *)

fun css_hex_digit {v:nat | v < 16} (v: int(v)): int

fun css_hex3 {l:agz}{n:pos}{r,g,b:nat | r < 16; g < 16; b < 16}
  (arr: !ward_arr(byte, l, n), off: int, cap: int n,
   r: int(r), g: int(g), b: int(b)): int

fun css_dim {l:agz}{n:pos}{v:nat | v < 100}
  (arr: !ward_arr(byte, l, n), off: int, cap: int n,
   value: int(v)): int

fun clear_node(nid: int): void

fun copy_filename_to_sbuf(max_len: int): [n:nat] int(n)
