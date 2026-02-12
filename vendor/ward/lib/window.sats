(* window.sats — Window/document bridge primitives *)

staload "./memory.sats"

fun ward_focus_window(): void

fun ward_get_visibility_state(): int  (* 0=visible, 1=hidden *)

fun ward_log
  {n:nat}
  (level: int, msg: ward_safe_text(n), msg_len: int n): void
