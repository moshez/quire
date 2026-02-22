(* context_menu.sats — Context menu declarations *)

staload "./../vendor/ward/lib/memory.sats"
staload "./../vendor/ward/lib/dom.sats"

(* ========== Context menu listener IDs ========== *)

#define LISTENER_CTX_DISMISS 19
#define LISTENER_CTX_INFO 20
#define LISTENER_CTX_HIDE 21
#define LISTENER_CTX_ARCHIVE 22
#define LISTENER_CTX_DELETE 23

(* ========== CSS class builders ========== *)

fun cls_ctx_overlay(): ward_safe_text(11)
fun cls_ctx_menu(): ward_safe_text(8)
fun cls_ctx_item(): ward_safe_text(8)
fun cls_ctx_danger(): ward_safe_text(10)
