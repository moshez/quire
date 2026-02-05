(* quire.sats - Type declarations for Quire e-reader *)
(* Minimal freestanding version - no stdlib dependencies *)

(* Required WASM exports for bridge protocol *)
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
