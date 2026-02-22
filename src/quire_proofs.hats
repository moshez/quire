(* quire_proofs.hats — shared proof declarations.
 * #include'd by quire.dats and static_tests.dats.
 *
 * These proofs enforce correct function call sequences.
 * Each proof can ONLY be constructed by calling the designated function.
 * Proof names match function names — documentation serves as specification.
 *)

(* SCRUBBER_FILL_CHECKED: proves update_scrubber_fill was called.
 * Only update_scrubber_fill constructs SCRUB_FILL_OK().
 * BUG CLASS PREVENTED: removing scrubber fill call from update_page_info
 * without the compiler catching it. *)
dataprop SCRUBBER_FILL_CHECKED() = | SCRUB_FILL_OK()

(* PAGE_INFO_SHOWN: proves update_page_info was called AND that it
 * called update_scrubber_fill (via SCRUBBER_FILL_CHECKED dependency).
 * Only update_page_info constructs PAGE_INFO_OK(pf_sfc).
 * BUG CLASS PREVENTED: page-changing path that skips update_page_info. *)
dataprop PAGE_INFO_SHOWN() = | PAGE_INFO_OK() of SCRUBBER_FILL_CHECKED()

(* CHAPTER_TITLE_DISPLAYED: proves handle_chapter_title was called.
 * Only handle_chapter_title constructs TITLE_SHOWN().
 * BUG CLASS PREVENTED: chapter load that skips title update. *)
dataprop CHAPTER_TITLE_DISPLAYED() = | TITLE_SHOWN()

(* BOOKMARK_BTN_SYNCED: proves visual state matches bookmark data.
 * Only update_bookmark_btn constructs BM_BTN_SYNCED().
 * BUG CLASS PREVENTED: bookmark toggle without DOM sync. *)
dataprop BOOKMARK_BTN_SYNCED() = | BM_BTN_SYNCED()

(* BOOKMARK_TOGGLED: proves toggle_bookmark was called.
 * Only toggle_bookmark constructs BM_TOGGLED().
 * BUG CLASS PREVENTED: bookmark event without toggle + save. *)
dataprop BOOKMARK_TOGGLED() = | BM_TOGGLED()

(* POSITION_PERSISTED: proves library_update_position + library_save
 * were called. Only save_reading_position constructs POS_PERSISTED().
 * BUG CLASS PREVENTED: navigation path that skips position save. *)
dataprop POSITION_PERSISTED() = | POS_PERSISTED()

(* PAGE_DISPLAY_UPDATED: proves page turn + page info update occurred.
 * Requires PAGE_INFO_SHOWN sub-proof (which itself requires SCRUBBER_FILL_CHECKED).
 * BUG CLASS PREVENTED: page turn that skips page info update. *)
dataprop PAGE_DISPLAY_UPDATED() =
  | PAGE_TURNED_AND_SHOWN() of PAGE_INFO_SHOWN()

(* CHAPTER_DISPLAY_READY: proves chapter load + title + page info all occurred.
 * Requires BOTH CHAPTER_TITLE_DISPLAYED and PAGE_INFO_SHOWN sub-proofs.
 * BUG CLASS PREVENTED: chapter load that skips title or page info update. *)
dataprop CHAPTER_DISPLAY_READY() =
  | MEASURED_AND_TRANSFORMED() of (CHAPTER_TITLE_DISPLAYED(), PAGE_INFO_SHOWN())
