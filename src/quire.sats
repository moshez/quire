(* quire.sats — Quire application entry point *)

(* Ward entry point — called by ward_bridge.mjs after WASM instantiation.
   The bridge calls ward_node_init(0) where 0 is the root node ID.
   The application creates ward_dom_state internally via ward_dom_init(). *)
fun ward_node_init(root_id: int): void = "ext#ward_node_init"

(* Legacy bridge callbacks — will be removed in Phase 9 when quire.dats
   is rewritten to use ward event listeners and promises. *)
fun init(): void = "mac#"
fun process_event(): void = "mac#"
fun on_fetch_complete(status: int, len: int): void = "mac#"
fun on_timer_complete(callback_id: int): void = "mac#"
fun on_file_open_complete(handle: int, size: int): void = "mac#"
fun on_decompress_complete(handle: int, size: int): void = "mac#"
fun on_kv_complete(success: int): void = "mac#"
fun on_kv_get_complete(len: int): void = "mac#"
fun on_kv_get_blob_complete(handle: int, size: int): void = "mac#"
fun on_clipboard_copy_complete(success: int): void = "mac#"
fun on_kv_open_complete(success: int): void = "mac#"
