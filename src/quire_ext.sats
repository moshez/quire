(* quire_ext.sats — Bridge function declarations not in ward .sats files *)

(* Parse HTML safely — returns tree binary length, stashes ptr *)
fun ward_js_parse_html(html: ptr, html_len: int): int = "mac#"

(* Retrieve parseHTML result ptr — from listener stash *)
fun ward_parse_html_get_ptr(): ptr

(* Read f64 clientX from click payload, return as int *)
fun read_payload_click_x(arr: ptr): int
