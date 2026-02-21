(* library_view.sats — Library view rendering declarations *)

staload "./../vendor/ward/lib/memory.sats"
staload "./../vendor/ward/lib/dom.sats"
staload "./dom.sats"
staload "./arith.sats"
staload "./library.sats"

(* ========== Reading progress display proof ========== *)
(* PROGRESS_DISPLAY(ch, pg, sc, display) proves the display state is
 * correct for the given reading position and spine count.
 * display: 0=New, 1=Done, 2=InProgress
 * Prevents: showing "New" for a started book, "Done" for an unfinished
 * book, or a percentage bar for an unstarted book. *)
dataprop PROGRESS_DISPLAY(ch: int, pg: int, sc: int, display: int) =
  | {sc:nat} PROGRESS_NEW(0, 0, sc, 0)
  | {ch,pg,sc:nat | ch >= sc; sc > 0} PROGRESS_DONE(ch, pg, sc, 1)
  | {ch,pg,sc:nat | (ch > 0 || pg > 0); (ch < sc || sc == 0)}
      PROGRESS_READING(ch, pg, sc, 2)

(* ========== Listener ID constants ========== *)

#define LISTENER_FILE_INPUT 1
#define LISTENER_READ_BTN_BASE 2
#define LISTENER_SORT_TITLE 56
#define LISTENER_SORT_AUTHOR 57
#define LISTENER_SORT_LAST_OPENED 58
#define LISTENER_SORT_DATE_ADDED 59
#define LISTENER_ARCHIVE_BTN_BASE 60
#define LISTENER_VIEW_HIDDEN 92
#define LISTENER_VIEW_ARCHIVED 93
#define LISTENER_VIEW_ACTIVE 94
#define LISTENER_HIDE_BTN_BASE 95

(* ========== Function declarations ========== *)

fun filter_book_visible(vm: int, book_idx: int): int

fun render_library_with_books {l:agz}
  (s: ward_dom_stream(l), list_id: int, view_mode: int)
  : ward_dom_stream(l)

fun register_card_btns {k:nat}
  (rem: int(k), i: int, n: int, root: int, vm: int): void

fun register_ctx_listeners {k:nat}
  (rem: int(k), i: int, n: int, root: int, vm: int): void

fun load_library_covers {k:nat}
  (rem: int(k), idx: int, total: int): void

fun count_visible_books {k:nat}
  (rem: int(k), i: int, n: int, vm: int): int
