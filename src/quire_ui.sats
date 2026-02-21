(* quire_ui.sats — Shared cross-module declarations for Quire UI.
 * Forward declarations for functions implemented in separate modules.
 * Staloaded by all UI modules to resolve cross-module calls. *)

staload "./../vendor/ward/lib/memory.sats"
staload "./../vendor/ward/lib/dom.sats"
staload "./dom.sats"
staload "./library.sats"
staload "./arith.sats"

(* ========== Context menu proof ========== *)
(* CTX_MENU_VALID(vm, ss, show_hide, show_archive) proves the correct
 * menu items are shown per shelf state.
 * vm=view_mode, ss=shelf_state, show_hide=1 if Hide/Unhide shown,
 * show_archive=1 if Archive/Unarchive shown.
 * Active shelf: Hide + Archive. Archived shelf: Unarchive (no Hide).
 * Hidden shelf: Unhide (no Archive). *)
dataprop CTX_MENU_VALID(vm: int, ss: int, show_hide: int, show_archive: int) =
  | CTX_ACTIVE(0, 0, 1, 1)
  | CTX_ARCHIVED(1, 1, 0, 1)
  | CTX_HIDDEN(2, 2, 1, 0)

(* ========== Book info view proofs ========== *)

(* INFO_BUTTONS_VALID: determines which action buttons to show per shelf.
 * vm=view_mode, ss=shelf_state, show_hide=1 if show, show_archive=1 if show.
 * Active: Hide+Archive. Archived: Unarchive only. Hidden: Unhide only. *)
dataprop INFO_BUTTONS_VALID(vm: int, ss: int, show_hide: int, show_archive: int) =
  | INFO_BTN_ACTIVE(0, 0, 1, 1)
  | INFO_BTN_ARCHIVED(1, 1, 0, 1)
  | INFO_BTN_HIDDEN(2, 2, 1, 0)

(* ========== Cross-module function declarations ========== *)

(* Render the library view — implemented in library_view.dats *)
fun render_library(root_id: int): void

(* Dismiss context menu — implemented in context_menu.dats *)
fun dismiss_context_menu(): void

(* Dismiss book info overlay — implemented in book_info.dats *)
fun dismiss_book_info(): void

(* Show context menu for a book card — implemented in context_menu.dats *)
fun show_context_menu {vm,ss,sh,sa:int}
  (pf: CTX_MENU_VALID(vm, ss, sh, sa) |
   book_idx: int, root_id: int, vm: int(vm),
   show_hide: int(sh), show_archive: int(sa)): void

(* Show book info overlay — implemented in book_info.dats *)
fun show_book_info {vm,ss,sh,sa:int}
  (pf: INFO_BUTTONS_VALID(vm, ss, sh, sa) |
   book_idx: int, root_id: int, vm: int(vm),
   show_hide: int(sh), show_archive: int(sa)): void

(* Enter reader view — implemented in quire.dats *)
fun enter_reader(root_id: int, book_index: int): void

(* Dismiss duplicate modal — implemented in modals.dats *)
fun dismiss_dup_modal(): void

(* Render duplicate modal — implemented in modals.dats *)
fun render_dup_modal(dup_idx: int, root: int): void

(* Dismiss error banner — implemented in modals.dats *)
fun dismiss_error_banner(): void

(* Render error banner — implemented in modals.dats *)
fun render_error_banner(root: int): void

(* Dismiss reset modal — implemented in modals.dats *)
fun dismiss_reset_modal(): void

(* Render factory reset modal — implemented in modals.dats *)
fun render_reset_modal(root: int): void

(* Dismiss delete modal — implemented in modals.dats *)
fun dismiss_delete_modal(): void

(* Render delete confirmation modal — implemented in modals.dats *)
fun render_delete_modal(book_idx: int, root: int): void

(* Detect MIME type from magic bytes — implemented in library_view.dats *)
fun detect_mime_from_magic {lb:agz}{n:pos}
  (data: !ward_arr(byte, lb, n), data_len: int n): int

(* Set image src on a DOM node from IDB data — implemented in library_view.dats *)
fun set_image_src_idb {lb:agz}{n:pos}
  (node_id: int, data: ward_arr(byte, lb, n), data_len: int n): void
