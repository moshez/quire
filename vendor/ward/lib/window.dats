(* window.dats — Window/document bridge implementation *)

#include "share/atspre_staload.hats"
staload "./memory.sats"
staload "./window.sats"
staload _ = "./memory.dats"

(* No $<M>UNSAFE needed — all parameters are non-linear ATS2 types *)

extern fun _ward_js_focus_window
  (): void = "mac#ward_js_focus_window"

extern fun _ward_js_get_visibility_state
  (): int = "mac#ward_js_get_visibility_state"

extern fun _ward_js_log
  {n:nat}
  (level: int, msg: ward_safe_text(n), msg_len: int n)
  : void = "mac#ward_js_log"

implement
ward_focus_window() = _ward_js_focus_window()

implement
ward_get_visibility_state() = _ward_js_get_visibility_state()

implement
ward_log{n}(level, msg, msg_len) =
  _ward_js_log(level, msg, msg_len)
