(* event.sats — Promise-based timer and exit for ward *)

staload "./promise.sats"

(* Set a timer; returns a pending promise that resolves when it fires *)
fun ward_timer_set(delay_ms: int): ward_promise_pending(int)

(* Called by JS host to fire a timer — WASM export *)
fun ward_timer_fire(resolver_ptr: ptr): void = "ext#ward_timer_fire"

(* Exit the process — host-provided *)
fun ward_exit(): void = "mac#ward_exit"
