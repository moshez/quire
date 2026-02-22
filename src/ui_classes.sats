(* ui_classes.sats — CSS class, event type, and log message safe text builders *)

staload "./../vendor/ward/lib/memory.sats"
staload "./../vendor/ward/lib/dom.sats"

(* ========== CSS class builders ========== *)

fun cls_import_btn(): ward_safe_text(10)
fun cls_library_list(): ward_safe_text(12)
fun cls_importing(): ward_safe_text(9)
fun cls_import_status(): ward_safe_text(13)
fun cls_empty_lib(): ward_safe_text(9)
fun cls_book_card(): ward_safe_text(9)
fun cls_book_cover(): ward_safe_text(10)
fun cls_book_title(): ward_safe_text(10)
fun cls_book_author(): ward_safe_text(11)
fun cls_book_position(): ward_safe_text(13)
fun cls_pbar(): ward_safe_text(4)
fun cls_pfill(): ward_safe_text(5)
fun cls_read_btn(): ward_safe_text(8)
fun cls_lib_toolbar(): ward_safe_text(11)
fun cls_hide_btn(): ward_safe_text(8)
fun cls_sort_btn(): ward_safe_text(8)
fun cls_sort_active(): ward_safe_text(11)
fun cls_archive_btn(): ward_safe_text(11)
fun cls_card_actions(): ward_safe_text(12)
fun cls_reader_viewport(): ward_safe_text(15)
fun cls_chapter_container(): ward_safe_text(17)
fun cls_chapter_error(): ward_safe_text(13)
fun cls_reader_nav(): ward_safe_text(10)
fun cls_back_btn(): ward_safe_text(8)
fun cls_page_info(): ward_safe_text(9)
fun cls_nav_controls(): ward_safe_text(12)
fun cls_prev_btn(): ward_safe_text(8)
fun cls_next_btn(): ward_safe_text(8)
fun cls_ch_title(): ward_safe_text(8)

(* ========== Event/type builders ========== *)

fun st_file(): ward_safe_text(4)
fun evt_change(): ward_safe_text(6)
fun evt_click(): ward_safe_text(5)
fun evt_keydown(): ward_safe_text(7)
fun evt_contextmenu(): ward_safe_text(11)

(* ========== Other builders ========== *)

fun val_zero(): ward_safe_text(1)

(* ========== Log message builders ========== *)

fun log_import_start(): ward_safe_text(12)
fun log_import_done(): ward_safe_text(11)
fun log_err_container(): ward_safe_text(13)
fun log_err_opf(): ward_safe_text(7)
fun log_err_zip_parse(): ward_safe_text(7)
fun log_err_lib_full(): ward_safe_text(12)
fun log_err_manifest(): ward_safe_text(12)
