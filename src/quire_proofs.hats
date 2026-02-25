(* quire_proofs.hats — shared proof declarations.
 * #include'd by quire.dats and static_tests.dats.
 *
 * All proofs are absprop — unforgeable. Each can ONLY be constructed
 * by calling the designated function inside its local assume block.
 * Proof names match function names — documentation serves as specification.
 *)

(* SCRUBBER_FILL_CHECKED: proves update_scrubber_fill was called.
 * absprop: unforgeable. Only update_scrubber_fill's local assume block can construct.
 * BUG CLASS PREVENTED: removing scrubber fill call from update_page_info
 * without the compiler catching it. *)
absprop SCRUBBER_FILL_CHECKED()

(* PAGE_INFO_SHOWN: proves update_page_info was called AND that it
 * called update_scrubber_fill (via local assume PAGE_INFO_SHOWN = SCRUBBER_FILL_CHECKED).
 * absprop: unforgeable. Only update_page_info's local assume block can construct.
 * BUG CLASS PREVENTED: page-changing path that skips update_page_info. *)
absprop PAGE_INFO_SHOWN()

(* CHAPTER_TITLE_DISPLAYED: proves handle_chapter_title was called.
 * absprop: unforgeable. Only handle_chapter_title's local assume block can construct.
 * BUG CLASS PREVENTED: chapter load that skips title update. *)
absprop CHAPTER_TITLE_DISPLAYED()

(* BOOKMARK_BTN_SYNCED: proves visual state matches bookmark data.
 * absprop: unforgeable. Only update_bookmark_btn's local assume block can construct.
 * BUG CLASS PREVENTED: bookmark toggle without DOM sync. *)
absprop BOOKMARK_BTN_SYNCED()

(* BOOKMARK_TOGGLED: proves toggle_bookmark was called.
 * absprop: unforgeable. Only toggle_bookmark's local assume block can construct.
 * BUG CLASS PREVENTED: bookmark event without toggle + save. *)
absprop BOOKMARK_TOGGLED()

(* POSITION_PERSISTED: proves library_update_position + library_save
 * were called. absprop: unforgeable. Only save_reading_position's block can construct.
 * BUG CLASS PREVENTED: navigation path that skips position save. *)
absprop POSITION_PERSISTED()

(* POS_STACK_PUSHED: proves push_position was called.
 * absprop: unforgeable. Only push_position's local assume block can construct.
 * BUG CLASS PREVENTED: TOC jump without pushing prior position to stack. *)
absprop POS_STACK_PUSHED()

(* PAGE_DISPLAY_UPDATED: proves page turn + page info update occurred.
 * Requires PAGE_INFO_SHOWN sub-proof (unforgeable absprop).
 * BUG CLASS PREVENTED: page turn that skips page info update. *)
dataprop PAGE_DISPLAY_UPDATED() =
  | PAGE_TURNED_AND_SHOWN() of PAGE_INFO_SHOWN()

(* HIGHLIGHTS_RENDERED: proves render_highlights was called after chapter load.
 * absprop: unforgeable. Only render_highlights's local assume block can construct.
 * BUG CLASS PREVENTED: chapter load that skips highlight rendering. *)
absprop HIGHLIGHTS_RENDERED()

(* CHAPTER_DISPLAY_READY: proves chapter load + title + page info + highlights all occurred.
 * Requires CHAPTER_TITLE_DISPLAYED, PAGE_INFO_SHOWN, and HIGHLIGHTS_RENDERED sub-proofs.
 * BUG CLASS PREVENTED: chapter load that skips title, page info, or highlight rendering. *)
dataprop CHAPTER_DISPLAY_READY() =
  | MEASURED_AND_TRANSFORMED() of (CHAPTER_TITLE_DISPLAYED(), PAGE_INFO_SHOWN(), HIGHLIGHTS_RENDERED())

(* PAGE_FORMAT_SIMPLIFIED: proves the page info format uses middot
 * separator (U+00B7) instead of slash for chapter/page separation.
 * R4: "Ch X · p. N/M" is cleaner than "Ch X/Y  N/M".
 * BUG CLASS PREVENTED: format regression to verbose Ch X/Y display. *)
dataprop PAGE_FORMAT_SIMPLIFIED(separator_cp: int) =
  | {s:int | s == 183} MIDDOT_FORMAT(s)

(* BOOKMARK_ICON_PAIR: proves the bookmark icons are a valid
 * unfilled/filled pair from the same Unicode block.
 * unfilled_cp and filled_cp must differ by exactly 1 (adjacent codepoints).
 * BUG CLASS PREVENTED: mismatched bookmark icon pair. *)
dataprop BOOKMARK_ICON_PAIR(unfilled_cp: int, filled_cp: int) =
  | {u,f:int | f == u - 1; u >= 0x2600; u <= 0x26FF}
    STAR_PAIR(u, f)
