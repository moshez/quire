(* context_menu.sats — Context menu declarations *)

staload "./../vendor/ward/lib/memory.sats"
staload "./../vendor/ward/lib/dom.sats"

(* ========== Context menu listener IDs ========== *)

stadef LID_CTX_BASE = 128
stadef LID_CTX_END = LID_CTX_BASE + 32
stadef LID_CTX_DISMISS = LID_CTX_END
stadef LID_CTX_INFO = LID_CTX_END + 1
stadef LID_CTX_HIDE = LID_CTX_END + 2
stadef LID_CTX_ARCHIVE = LID_CTX_END + 3
stadef LID_CTX_DELETE = LID_CTX_END + 4
#define LISTENER_CTX_BASE 128
#define LISTENER_CTX_DISMISS 160
#define LISTENER_CTX_INFO 161
#define LISTENER_CTX_HIDE 162
#define LISTENER_CTX_ARCHIVE 163
#define LISTENER_CTX_DELETE 164

(* ========== CSS class builders ========== *)

fun cls_ctx_overlay(): ward_safe_text(11)
fun cls_ctx_menu(): ward_safe_text(8)
fun cls_ctx_item(): ward_safe_text(8)
fun cls_ctx_danger(): ward_safe_text(10)
