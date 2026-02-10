(* clipboard.sats — Clipboard bridge primitives *)

staload "./memory.sats"
staload "./promise.sats"

(* Write text to clipboard. Resolves with 1=success, 0=failure. *)
fun ward_clipboard_write_text
  {n:nat}
  (text: ward_safe_text(n), text_len: int n)
  : ward_promise_pending(int)

(* WASM export — called by JS when clipboard op completes *)
fun ward_on_clipboard_complete
  (resolver_id: int, success: int): void = "ext#ward_on_clipboard_complete"
