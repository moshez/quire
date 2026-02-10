(* quire.dats — Quire application entry point (stub)
 *
 * This is a temporary stub while modules are being migrated to ward APIs.
 * The full implementation will be rebuilt in Phase 9 using ward_node_init
 * as the entry point, ward event listeners, and ward promises.
 *
 * The old 1400-line C block has been removed. All functionality will be
 * reimplemented using ward's typed DOM diff protocol.
 *)

#define ATS_DYNLOADFLAG 0

#include "share/atspre_staload.hats"
staload "./quire.sats"
staload "./app_state.sats"

(* Ward entry point — create and register app_state *)
implement ward_node_init(root_id) = let
  val st = app_state_init()
  val () = app_state_register(st)
in end

(* Legacy callback stubs — will be removed in Phase 9 *)
implement init() = ()
implement process_event() = ()
implement on_fetch_complete(status, len) = ()
implement on_timer_complete(callback_id) = ()
implement on_file_open_complete(handle, size) = ()
implement on_decompress_complete(handle, size) = ()
implement on_kv_complete(success) = ()
implement on_kv_get_complete(len) = ()
implement on_kv_get_blob_complete(handle, size) = ()
implement on_clipboard_copy_complete(success) = ()
implement on_kv_open_complete(success) = ()
