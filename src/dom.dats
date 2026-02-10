(* dom.dats — Quire DOM convenience layer implementation
 *
 * Builds ward_safe_text constants for tags and attributes.
 * Implements lookup tables and tree renderer.
 *)

#define ATS_DYNLOADFLAG 0

#include "share/atspre_staload.hats"
staload "./../vendor/ward/lib/memory.sats"
staload "./../vendor/ward/lib/dom.sats"
staload "./dom.sats"
staload "./app_state.sats"
staload _ = "./../vendor/ward/lib/memory.dats"
staload _ = "./../vendor/ward/lib/dom.dats"

(* ========== Node ID allocator ========== *)

(* Loads app_state from callback registry, reads/increments counter,
 * stores app_state back. Zero-argument signature preserved for C callers
 * in quire_runtime.c. *)
implement dom_next_id() = let
  val st = app_state_load()
  val id = g1ofg0(app_get_dom_next_id(st))
  val () = app_set_dom_next_id(st, id + 1)
  val () = app_state_store(st)
in
  if id > 0 then id
  else 1 (* counter starts at 1, can never be <= 0 in practice *)
end

(* ========== Safe text builders: tags ========== *)

implement tag_div() = let
  val b = ward_text_build(3)
  val b = ward_text_putc(b, 0, char2int1('d'))
  val b = ward_text_putc(b, 1, char2int1('i'))
  val b = ward_text_putc(b, 2, char2int1('v'))
in ward_text_done(b) end

implement tag_span() = let
  val b = ward_text_build(4)
  val b = ward_text_putc(b, 0, char2int1('s'))
  val b = ward_text_putc(b, 1, char2int1('p'))
  val b = ward_text_putc(b, 2, char2int1('a'))
  val b = ward_text_putc(b, 3, char2int1('n'))
in ward_text_done(b) end

implement tag_button() = let
  val b = ward_text_build(6)
  val b = ward_text_putc(b, 0, char2int1('b'))
  val b = ward_text_putc(b, 1, char2int1('u'))
  val b = ward_text_putc(b, 2, char2int1('t'))
  val b = ward_text_putc(b, 3, char2int1('t'))
  val b = ward_text_putc(b, 4, char2int1('o'))
  val b = ward_text_putc(b, 5, char2int1('n'))
in ward_text_done(b) end

implement tag_style() = let
  val b = ward_text_build(5)
  val b = ward_text_putc(b, 0, char2int1('s'))
  val b = ward_text_putc(b, 1, char2int1('t'))
  val b = ward_text_putc(b, 2, char2int1('y'))
  val b = ward_text_putc(b, 3, char2int1('l'))
  val b = ward_text_putc(b, 4, char2int1('e'))
in ward_text_done(b) end

implement tag_h1() = let
  val b = ward_text_build(2)
  val b = ward_text_putc(b, 0, char2int1('h'))
  val b = ward_text_putc(b, 1, 49) (* '1' *)
in ward_text_done(b) end

implement tag_h2() = let
  val b = ward_text_build(2)
  val b = ward_text_putc(b, 0, char2int1('h'))
  val b = ward_text_putc(b, 1, 50) (* '2' *)
in ward_text_done(b) end

implement tag_h3() = let
  val b = ward_text_build(2)
  val b = ward_text_putc(b, 0, char2int1('h'))
  val b = ward_text_putc(b, 1, 51) (* '3' *)
in ward_text_done(b) end

implement tag_p() = let
  val b = ward_text_build(1)
  val b = ward_text_putc(b, 0, char2int1('p'))
in ward_text_done(b) end

implement tag_input() = let
  val b = ward_text_build(5)
  val b = ward_text_putc(b, 0, char2int1('i'))
  val b = ward_text_putc(b, 1, char2int1('n'))
  val b = ward_text_putc(b, 2, char2int1('p'))
  val b = ward_text_putc(b, 3, char2int1('u'))
  val b = ward_text_putc(b, 4, char2int1('t'))
in ward_text_done(b) end

implement tag_label() = let
  val b = ward_text_build(5)
  val b = ward_text_putc(b, 0, char2int1('l'))
  val b = ward_text_putc(b, 1, char2int1('a'))
  val b = ward_text_putc(b, 2, char2int1('b'))
  val b = ward_text_putc(b, 3, char2int1('e'))
  val b = ward_text_putc(b, 4, char2int1('l'))
in ward_text_done(b) end

implement tag_select() = let
  val b = ward_text_build(6)
  val b = ward_text_putc(b, 0, char2int1('s'))
  val b = ward_text_putc(b, 1, char2int1('e'))
  val b = ward_text_putc(b, 2, char2int1('l'))
  val b = ward_text_putc(b, 3, char2int1('e'))
  val b = ward_text_putc(b, 4, char2int1('c'))
  val b = ward_text_putc(b, 5, char2int1('t'))
in ward_text_done(b) end

implement tag_option() = let
  val b = ward_text_build(6)
  val b = ward_text_putc(b, 0, char2int1('o'))
  val b = ward_text_putc(b, 1, char2int1('p'))
  val b = ward_text_putc(b, 2, char2int1('t'))
  val b = ward_text_putc(b, 3, char2int1('i'))
  val b = ward_text_putc(b, 4, char2int1('o'))
  val b = ward_text_putc(b, 5, char2int1('n'))
in ward_text_done(b) end

implement tag_a() = let
  val b = ward_text_build(1)
  val b = ward_text_putc(b, 0, char2int1('a'))
in ward_text_done(b) end

implement tag_img() = let
  val b = ward_text_build(3)
  val b = ward_text_putc(b, 0, char2int1('i'))
  val b = ward_text_putc(b, 1, char2int1('m'))
  val b = ward_text_putc(b, 2, char2int1('g'))
in ward_text_done(b) end

(* EPUB content tags *)
implement tag_b() = let val b = ward_text_build(1)
  val b = ward_text_putc(b, 0, char2int1('b')) in ward_text_done(b) end
implement tag_i() = let val b = ward_text_build(1)
  val b = ward_text_putc(b, 0, char2int1('i')) in ward_text_done(b) end
implement tag_u() = let val b = ward_text_build(1)
  val b = ward_text_putc(b, 0, char2int1('u')) in ward_text_done(b) end
implement tag_s() = let val b = ward_text_build(1)
  val b = ward_text_putc(b, 0, char2int1('s')) in ward_text_done(b) end
implement tag_q() = let val b = ward_text_build(1)
  val b = ward_text_putc(b, 0, char2int1('q')) in ward_text_done(b) end
implement tag_g() = let val b = ward_text_build(1)
  val b = ward_text_putc(b, 0, char2int1('g')) in ward_text_done(b) end

implement tag_em() = let val b = ward_text_build(2)
  val b = ward_text_putc(b, 0, char2int1('e'))
  val b = ward_text_putc(b, 1, char2int1('m')) in ward_text_done(b) end
implement tag_br() = let val b = ward_text_build(2)
  val b = ward_text_putc(b, 0, char2int1('b'))
  val b = ward_text_putc(b, 1, char2int1('r')) in ward_text_done(b) end
implement tag_hr() = let val b = ward_text_build(2)
  val b = ward_text_putc(b, 0, char2int1('h'))
  val b = ward_text_putc(b, 1, char2int1('r')) in ward_text_done(b) end
implement tag_li() = let val b = ward_text_build(2)
  val b = ward_text_putc(b, 0, char2int1('l'))
  val b = ward_text_putc(b, 1, char2int1('i')) in ward_text_done(b) end
implement tag_dd() = let val b = ward_text_build(2)
  val b = ward_text_putc(b, 0, char2int1('d'))
  val b = ward_text_putc(b, 1, char2int1('d')) in ward_text_done(b) end
implement tag_dl() = let val b = ward_text_build(2)
  val b = ward_text_putc(b, 0, char2int1('d'))
  val b = ward_text_putc(b, 1, char2int1('l')) in ward_text_done(b) end
implement tag_dt() = let val b = ward_text_build(2)
  val b = ward_text_putc(b, 0, char2int1('d'))
  val b = ward_text_putc(b, 1, char2int1('t')) in ward_text_done(b) end
implement tag_ol() = let val b = ward_text_build(2)
  val b = ward_text_putc(b, 0, char2int1('o'))
  val b = ward_text_putc(b, 1, char2int1('l')) in ward_text_done(b) end
implement tag_ul() = let val b = ward_text_build(2)
  val b = ward_text_putc(b, 0, char2int1('u'))
  val b = ward_text_putc(b, 1, char2int1('l')) in ward_text_done(b) end
implement tag_td() = let val b = ward_text_build(2)
  val b = ward_text_putc(b, 0, char2int1('t'))
  val b = ward_text_putc(b, 1, char2int1('d')) in ward_text_done(b) end
implement tag_th() = let val b = ward_text_build(2)
  val b = ward_text_putc(b, 0, char2int1('t'))
  val b = ward_text_putc(b, 1, char2int1('h')) in ward_text_done(b) end
implement tag_tr() = let val b = ward_text_build(2)
  val b = ward_text_putc(b, 0, char2int1('t'))
  val b = ward_text_putc(b, 1, char2int1('r')) in ward_text_done(b) end
implement tag_h4() = let val b = ward_text_build(2)
  val b = ward_text_putc(b, 0, char2int1('h'))
  val b = ward_text_putc(b, 1, 52) in ward_text_done(b) end
implement tag_h5() = let val b = ward_text_build(2)
  val b = ward_text_putc(b, 0, char2int1('h'))
  val b = ward_text_putc(b, 1, 53) in ward_text_done(b) end
implement tag_h6() = let val b = ward_text_build(2)
  val b = ward_text_putc(b, 0, char2int1('h'))
  val b = ward_text_putc(b, 1, 54) in ward_text_done(b) end
implement tag_mi() = let val b = ward_text_build(2)
  val b = ward_text_putc(b, 0, char2int1('m'))
  val b = ward_text_putc(b, 1, char2int1('i')) in ward_text_done(b) end
implement tag_mn() = let val b = ward_text_build(2)
  val b = ward_text_putc(b, 0, char2int1('m'))
  val b = ward_text_putc(b, 1, char2int1('n')) in ward_text_done(b) end
implement tag_mo() = let val b = ward_text_build(2)
  val b = ward_text_putc(b, 0, char2int1('m'))
  val b = ward_text_putc(b, 1, char2int1('o')) in ward_text_done(b) end
implement tag_rp() = let val b = ward_text_build(2)
  val b = ward_text_putc(b, 0, char2int1('r'))
  val b = ward_text_putc(b, 1, char2int1('p')) in ward_text_done(b) end
implement tag_rt() = let val b = ward_text_build(2)
  val b = ward_text_putc(b, 0, char2int1('r'))
  val b = ward_text_putc(b, 1, char2int1('t')) in ward_text_done(b) end

implement tag_pre() = let val b = ward_text_build(3)
  val b = ward_text_putc(b, 0, char2int1('p'))
  val b = ward_text_putc(b, 1, char2int1('r'))
  val b = ward_text_putc(b, 2, char2int1('e')) in ward_text_done(b) end
implement tag_sub() = let val b = ward_text_build(3)
  val b = ward_text_putc(b, 0, char2int1('s'))
  val b = ward_text_putc(b, 1, char2int1('u'))
  val b = ward_text_putc(b, 2, char2int1('b')) in ward_text_done(b) end
implement tag_sup() = let val b = ward_text_build(3)
  val b = ward_text_putc(b, 0, char2int1('s'))
  val b = ward_text_putc(b, 1, char2int1('u'))
  val b = ward_text_putc(b, 2, char2int1('p')) in ward_text_done(b) end
implement tag_var() = let val b = ward_text_build(3)
  val b = ward_text_putc(b, 0, char2int1('v'))
  val b = ward_text_putc(b, 1, char2int1('a'))
  val b = ward_text_putc(b, 2, char2int1('r')) in ward_text_done(b) end
implement tag_wbr() = let val b = ward_text_build(3)
  val b = ward_text_putc(b, 0, char2int1('w'))
  val b = ward_text_putc(b, 1, char2int1('b'))
  val b = ward_text_putc(b, 2, char2int1('r')) in ward_text_done(b) end
implement tag_nav() = let val b = ward_text_build(3)
  val b = ward_text_putc(b, 0, char2int1('n'))
  val b = ward_text_putc(b, 1, char2int1('a'))
  val b = ward_text_putc(b, 2, char2int1('v')) in ward_text_done(b) end
implement tag_kbd() = let val b = ward_text_build(3)
  val b = ward_text_putc(b, 0, char2int1('k'))
  val b = ward_text_putc(b, 1, char2int1('b'))
  val b = ward_text_putc(b, 2, char2int1('d')) in ward_text_done(b) end
implement tag_svg() = let val b = ward_text_build(3)
  val b = ward_text_putc(b, 0, char2int1('s'))
  val b = ward_text_putc(b, 1, char2int1('v'))
  val b = ward_text_putc(b, 2, char2int1('g')) in ward_text_done(b) end
implement tag_dfn() = let val b = ward_text_build(3)
  val b = ward_text_putc(b, 0, char2int1('d'))
  val b = ward_text_putc(b, 1, char2int1('f'))
  val b = ward_text_putc(b, 2, char2int1('n')) in ward_text_done(b) end
implement tag_use() = let val b = ward_text_build(3)
  val b = ward_text_putc(b, 0, char2int1('u'))
  val b = ward_text_putc(b, 1, char2int1('s'))
  val b = ward_text_putc(b, 2, char2int1('e')) in ward_text_done(b) end
implement tag_mtr() = let val b = ward_text_build(3)
  val b = ward_text_putc(b, 0, char2int1('m'))
  val b = ward_text_putc(b, 1, char2int1('t'))
  val b = ward_text_putc(b, 2, char2int1('r')) in ward_text_done(b) end
implement tag_mtd() = let val b = ward_text_build(3)
  val b = ward_text_putc(b, 0, char2int1('m'))
  val b = ward_text_putc(b, 1, char2int1('t'))
  val b = ward_text_putc(b, 2, char2int1('d')) in ward_text_done(b) end

implement tag_code() = let val b = ward_text_build(4)
  val b = ward_text_putc(b, 0, char2int1('c'))
  val b = ward_text_putc(b, 1, char2int1('o'))
  val b = ward_text_putc(b, 2, char2int1('d'))
  val b = ward_text_putc(b, 3, char2int1('e')) in ward_text_done(b) end
implement tag_mark() = let val b = ward_text_build(4)
  val b = ward_text_putc(b, 0, char2int1('m'))
  val b = ward_text_putc(b, 1, char2int1('a'))
  val b = ward_text_putc(b, 2, char2int1('r'))
  val b = ward_text_putc(b, 3, char2int1('k')) in ward_text_done(b) end
implement tag_cite() = let val b = ward_text_build(4)
  val b = ward_text_putc(b, 0, char2int1('c'))
  val b = ward_text_putc(b, 1, char2int1('i'))
  val b = ward_text_putc(b, 2, char2int1('t'))
  val b = ward_text_putc(b, 3, char2int1('e')) in ward_text_done(b) end
implement tag_abbr() = let val b = ward_text_build(4)
  val b = ward_text_putc(b, 0, char2int1('a'))
  val b = ward_text_putc(b, 1, char2int1('b'))
  val b = ward_text_putc(b, 2, char2int1('b'))
  val b = ward_text_putc(b, 3, char2int1('r')) in ward_text_done(b) end
implement tag_main() = let val b = ward_text_build(4)
  val b = ward_text_putc(b, 0, char2int1('m'))
  val b = ward_text_putc(b, 1, char2int1('a'))
  val b = ward_text_putc(b, 2, char2int1('i'))
  val b = ward_text_putc(b, 3, char2int1('n')) in ward_text_done(b) end
implement tag_time() = let val b = ward_text_build(4)
  val b = ward_text_putc(b, 0, char2int1('t'))
  val b = ward_text_putc(b, 1, char2int1('i'))
  val b = ward_text_putc(b, 2, char2int1('m'))
  val b = ward_text_putc(b, 3, char2int1('e')) in ward_text_done(b) end
implement tag_ruby() = let val b = ward_text_build(4)
  val b = ward_text_putc(b, 0, char2int1('r'))
  val b = ward_text_putc(b, 1, char2int1('u'))
  val b = ward_text_putc(b, 2, char2int1('b'))
  val b = ward_text_putc(b, 3, char2int1('y')) in ward_text_done(b) end
implement tag_path() = let val b = ward_text_build(4)
  val b = ward_text_putc(b, 0, char2int1('p'))
  val b = ward_text_putc(b, 1, char2int1('a'))
  val b = ward_text_putc(b, 2, char2int1('t'))
  val b = ward_text_putc(b, 3, char2int1('h')) in ward_text_done(b) end
implement tag_rect() = let val b = ward_text_build(4)
  val b = ward_text_putc(b, 0, char2int1('r'))
  val b = ward_text_putc(b, 1, char2int1('e'))
  val b = ward_text_putc(b, 2, char2int1('c'))
  val b = ward_text_putc(b, 3, char2int1('t')) in ward_text_done(b) end
implement tag_line() = let val b = ward_text_build(4)
  val b = ward_text_putc(b, 0, char2int1('l'))
  val b = ward_text_putc(b, 1, char2int1('i'))
  val b = ward_text_putc(b, 2, char2int1('n'))
  val b = ward_text_putc(b, 3, char2int1('e')) in ward_text_done(b) end
implement tag_text() = let val b = ward_text_build(4)
  val b = ward_text_putc(b, 0, char2int1('t'))
  val b = ward_text_putc(b, 1, char2int1('e'))
  val b = ward_text_putc(b, 2, char2int1('x'))
  val b = ward_text_putc(b, 3, char2int1('t')) in ward_text_done(b) end
implement tag_defs() = let val b = ward_text_build(4)
  val b = ward_text_putc(b, 0, char2int1('d'))
  val b = ward_text_putc(b, 1, char2int1('e'))
  val b = ward_text_putc(b, 2, char2int1('f'))
  val b = ward_text_putc(b, 3, char2int1('s')) in ward_text_done(b) end
implement tag_desc() = let val b = ward_text_build(4)
  val b = ward_text_putc(b, 0, char2int1('d'))
  val b = ward_text_putc(b, 1, char2int1('e'))
  val b = ward_text_putc(b, 2, char2int1('s'))
  val b = ward_text_putc(b, 3, char2int1('c')) in ward_text_done(b) end
implement tag_math() = let val b = ward_text_build(4)
  val b = ward_text_putc(b, 0, char2int1('m'))
  val b = ward_text_putc(b, 1, char2int1('a'))
  val b = ward_text_putc(b, 2, char2int1('t'))
  val b = ward_text_putc(b, 3, char2int1('h')) in ward_text_done(b) end
implement tag_mrow() = let val b = ward_text_build(4)
  val b = ward_text_putc(b, 0, char2int1('m'))
  val b = ward_text_putc(b, 1, char2int1('r'))
  val b = ward_text_putc(b, 2, char2int1('o'))
  val b = ward_text_putc(b, 3, char2int1('w')) in ward_text_done(b) end
implement tag_msup() = let val b = ward_text_build(4)
  val b = ward_text_putc(b, 0, char2int1('m'))
  val b = ward_text_putc(b, 1, char2int1('s'))
  val b = ward_text_putc(b, 2, char2int1('u'))
  val b = ward_text_putc(b, 3, char2int1('p')) in ward_text_done(b) end
implement tag_msub() = let val b = ward_text_build(4)
  val b = ward_text_putc(b, 0, char2int1('m'))
  val b = ward_text_putc(b, 1, char2int1('s'))
  val b = ward_text_putc(b, 2, char2int1('u'))
  val b = ward_text_putc(b, 3, char2int1('b')) in ward_text_done(b) end

implement tag_aside() = let val b = ward_text_build(5)
  val b = ward_text_putc(b, 0, char2int1('a'))
  val b = ward_text_putc(b, 1, char2int1('s'))
  val b = ward_text_putc(b, 2, char2int1('i'))
  val b = ward_text_putc(b, 3, char2int1('d'))
  val b = ward_text_putc(b, 4, char2int1('e')) in ward_text_done(b) end
implement tag_small() = let val b = ward_text_build(5)
  val b = ward_text_putc(b, 0, char2int1('s'))
  val b = ward_text_putc(b, 1, char2int1('m'))
  val b = ward_text_putc(b, 2, char2int1('a'))
  val b = ward_text_putc(b, 3, char2int1('l'))
  val b = ward_text_putc(b, 4, char2int1('l')) in ward_text_done(b) end
implement tag_table() = let val b = ward_text_build(5)
  val b = ward_text_putc(b, 0, char2int1('t'))
  val b = ward_text_putc(b, 1, char2int1('a'))
  val b = ward_text_putc(b, 2, char2int1('b'))
  val b = ward_text_putc(b, 3, char2int1('l'))
  val b = ward_text_putc(b, 4, char2int1('e')) in ward_text_done(b) end
implement tag_thead() = let val b = ward_text_build(5)
  val b = ward_text_putc(b, 0, char2int1('t'))
  val b = ward_text_putc(b, 1, char2int1('h'))
  val b = ward_text_putc(b, 2, char2int1('e'))
  val b = ward_text_putc(b, 3, char2int1('a'))
  val b = ward_text_putc(b, 4, char2int1('d')) in ward_text_done(b) end
implement tag_tbody() = let val b = ward_text_build(5)
  val b = ward_text_putc(b, 0, char2int1('t'))
  val b = ward_text_putc(b, 1, char2int1('b'))
  val b = ward_text_putc(b, 2, char2int1('o'))
  val b = ward_text_putc(b, 3, char2int1('d'))
  val b = ward_text_putc(b, 4, char2int1('y')) in ward_text_done(b) end
implement tag_tfoot() = let val b = ward_text_build(5)
  val b = ward_text_putc(b, 0, char2int1('t'))
  val b = ward_text_putc(b, 1, char2int1('f'))
  val b = ward_text_putc(b, 2, char2int1('o'))
  val b = ward_text_putc(b, 3, char2int1('o'))
  val b = ward_text_putc(b, 4, char2int1('t')) in ward_text_done(b) end
implement tag_tspan() = let val b = ward_text_build(5)
  val b = ward_text_putc(b, 0, char2int1('t'))
  val b = ward_text_putc(b, 1, char2int1('s'))
  val b = ward_text_putc(b, 2, char2int1('p'))
  val b = ward_text_putc(b, 3, char2int1('a'))
  val b = ward_text_putc(b, 4, char2int1('n')) in ward_text_done(b) end
implement tag_image() = let val b = ward_text_build(5)
  val b = ward_text_putc(b, 0, char2int1('i'))
  val b = ward_text_putc(b, 1, char2int1('m'))
  val b = ward_text_putc(b, 2, char2int1('a'))
  val b = ward_text_putc(b, 3, char2int1('g'))
  val b = ward_text_putc(b, 4, char2int1('e')) in ward_text_done(b) end
implement tag_title() = let val b = ward_text_build(5)
  val b = ward_text_putc(b, 0, char2int1('t'))
  val b = ward_text_putc(b, 1, char2int1('i'))
  val b = ward_text_putc(b, 2, char2int1('t'))
  val b = ward_text_putc(b, 3, char2int1('l'))
  val b = ward_text_putc(b, 4, char2int1('e')) in ward_text_done(b) end
implement tag_mfrac() = let val b = ward_text_build(5)
  val b = ward_text_putc(b, 0, char2int1('m'))
  val b = ward_text_putc(b, 1, char2int1('f'))
  val b = ward_text_putc(b, 2, char2int1('r'))
  val b = ward_text_putc(b, 3, char2int1('a'))
  val b = ward_text_putc(b, 4, char2int1('c')) in ward_text_done(b) end
implement tag_msqrt() = let val b = ward_text_build(5)
  val b = ward_text_putc(b, 0, char2int1('m'))
  val b = ward_text_putc(b, 1, char2int1('s'))
  val b = ward_text_putc(b, 2, char2int1('q'))
  val b = ward_text_putc(b, 3, char2int1('r'))
  val b = ward_text_putc(b, 4, char2int1('t')) in ward_text_done(b) end
implement tag_mroot() = let val b = ward_text_build(5)
  val b = ward_text_putc(b, 0, char2int1('m'))
  val b = ward_text_putc(b, 1, char2int1('r'))
  val b = ward_text_putc(b, 2, char2int1('o'))
  val b = ward_text_putc(b, 3, char2int1('o'))
  val b = ward_text_putc(b, 4, char2int1('t')) in ward_text_done(b) end
implement tag_mover() = let val b = ward_text_build(5)
  val b = ward_text_putc(b, 0, char2int1('m'))
  val b = ward_text_putc(b, 1, char2int1('o'))
  val b = ward_text_putc(b, 2, char2int1('v'))
  val b = ward_text_putc(b, 3, char2int1('e'))
  val b = ward_text_putc(b, 4, char2int1('r')) in ward_text_done(b) end

implement tag_strong() = let val b = ward_text_build(6)
  val b = ward_text_putc(b, 0, char2int1('s'))
  val b = ward_text_putc(b, 1, char2int1('t'))
  val b = ward_text_putc(b, 2, char2int1('r'))
  val b = ward_text_putc(b, 3, char2int1('o'))
  val b = ward_text_putc(b, 4, char2int1('n'))
  val b = ward_text_putc(b, 5, char2int1('g')) in ward_text_done(b) end
implement tag_figure() = let val b = ward_text_build(6)
  val b = ward_text_putc(b, 0, char2int1('f'))
  val b = ward_text_putc(b, 1, char2int1('i'))
  val b = ward_text_putc(b, 2, char2int1('g'))
  val b = ward_text_putc(b, 3, char2int1('u'))
  val b = ward_text_putc(b, 4, char2int1('r'))
  val b = ward_text_putc(b, 5, char2int1('e')) in ward_text_done(b) end
implement tag_footer() = let val b = ward_text_build(6)
  val b = ward_text_putc(b, 0, char2int1('f'))
  val b = ward_text_putc(b, 1, char2int1('o'))
  val b = ward_text_putc(b, 2, char2int1('o'))
  val b = ward_text_putc(b, 3, char2int1('t'))
  val b = ward_text_putc(b, 4, char2int1('e'))
  val b = ward_text_putc(b, 5, char2int1('r')) in ward_text_done(b) end
implement tag_header() = let val b = ward_text_build(6)
  val b = ward_text_putc(b, 0, char2int1('h'))
  val b = ward_text_putc(b, 1, char2int1('e'))
  val b = ward_text_putc(b, 2, char2int1('a'))
  val b = ward_text_putc(b, 3, char2int1('d'))
  val b = ward_text_putc(b, 4, char2int1('e'))
  val b = ward_text_putc(b, 5, char2int1('r')) in ward_text_done(b) end
implement tag_circle() = let val b = ward_text_build(6)
  val b = ward_text_putc(b, 0, char2int1('c'))
  val b = ward_text_putc(b, 1, char2int1('i'))
  val b = ward_text_putc(b, 2, char2int1('r'))
  val b = ward_text_putc(b, 3, char2int1('c'))
  val b = ward_text_putc(b, 4, char2int1('l'))
  val b = ward_text_putc(b, 5, char2int1('e')) in ward_text_done(b) end
implement tag_symbol() = let val b = ward_text_build(6)
  val b = ward_text_putc(b, 0, char2int1('s'))
  val b = ward_text_putc(b, 1, char2int1('y'))
  val b = ward_text_putc(b, 2, char2int1('m'))
  val b = ward_text_putc(b, 3, char2int1('b'))
  val b = ward_text_putc(b, 4, char2int1('o'))
  val b = ward_text_putc(b, 5, char2int1('l')) in ward_text_done(b) end
implement tag_munder() = let val b = ward_text_build(6)
  val b = ward_text_putc(b, 0, char2int1('m'))
  val b = ward_text_putc(b, 1, char2int1('u'))
  val b = ward_text_putc(b, 2, char2int1('n'))
  val b = ward_text_putc(b, 3, char2int1('d'))
  val b = ward_text_putc(b, 4, char2int1('e'))
  val b = ward_text_putc(b, 5, char2int1('r')) in ward_text_done(b) end
implement tag_mtable() = let val b = ward_text_build(6)
  val b = ward_text_putc(b, 0, char2int1('m'))
  val b = ward_text_putc(b, 1, char2int1('t'))
  val b = ward_text_putc(b, 2, char2int1('a'))
  val b = ward_text_putc(b, 3, char2int1('b'))
  val b = ward_text_putc(b, 4, char2int1('l'))
  val b = ward_text_putc(b, 5, char2int1('e')) in ward_text_done(b) end

implement tag_section() = let val b = ward_text_build(7)
  val b = ward_text_putc(b, 0, char2int1('s'))
  val b = ward_text_putc(b, 1, char2int1('e'))
  val b = ward_text_putc(b, 2, char2int1('c'))
  val b = ward_text_putc(b, 3, char2int1('t'))
  val b = ward_text_putc(b, 4, char2int1('i'))
  val b = ward_text_putc(b, 5, char2int1('o'))
  val b = ward_text_putc(b, 6, char2int1('n')) in ward_text_done(b) end
implement tag_article() = let val b = ward_text_build(7)
  val b = ward_text_putc(b, 0, char2int1('a'))
  val b = ward_text_putc(b, 1, char2int1('r'))
  val b = ward_text_putc(b, 2, char2int1('t'))
  val b = ward_text_putc(b, 3, char2int1('i'))
  val b = ward_text_putc(b, 4, char2int1('c'))
  val b = ward_text_putc(b, 5, char2int1('l'))
  val b = ward_text_putc(b, 6, char2int1('e')) in ward_text_done(b) end
implement tag_details() = let val b = ward_text_build(7)
  val b = ward_text_putc(b, 0, char2int1('d'))
  val b = ward_text_putc(b, 1, char2int1('e'))
  val b = ward_text_putc(b, 2, char2int1('t'))
  val b = ward_text_putc(b, 3, char2int1('a'))
  val b = ward_text_putc(b, 4, char2int1('i'))
  val b = ward_text_putc(b, 5, char2int1('l'))
  val b = ward_text_putc(b, 6, char2int1('s')) in ward_text_done(b) end
implement tag_summary() = let val b = ward_text_build(7)
  val b = ward_text_putc(b, 0, char2int1('s'))
  val b = ward_text_putc(b, 1, char2int1('u'))
  val b = ward_text_putc(b, 2, char2int1('m'))
  val b = ward_text_putc(b, 3, char2int1('m'))
  val b = ward_text_putc(b, 4, char2int1('a'))
  val b = ward_text_putc(b, 5, char2int1('r'))
  val b = ward_text_putc(b, 6, char2int1('y')) in ward_text_done(b) end
implement tag_caption() = let val b = ward_text_build(7)
  val b = ward_text_putc(b, 0, char2int1('c'))
  val b = ward_text_putc(b, 1, char2int1('a'))
  val b = ward_text_putc(b, 2, char2int1('p'))
  val b = ward_text_putc(b, 3, char2int1('t'))
  val b = ward_text_putc(b, 4, char2int1('i'))
  val b = ward_text_putc(b, 5, char2int1('o'))
  val b = ward_text_putc(b, 6, char2int1('n')) in ward_text_done(b) end
implement tag_polygon() = let val b = ward_text_build(7)
  val b = ward_text_putc(b, 0, char2int1('p'))
  val b = ward_text_putc(b, 1, char2int1('o'))
  val b = ward_text_putc(b, 2, char2int1('l'))
  val b = ward_text_putc(b, 3, char2int1('y'))
  val b = ward_text_putc(b, 4, char2int1('g'))
  val b = ward_text_putc(b, 5, char2int1('o'))
  val b = ward_text_putc(b, 6, char2int1('n')) in ward_text_done(b) end

implement tag_polyline() = let val b = ward_text_build(8)
  val b = ward_text_putc(b, 0, char2int1('p'))
  val b = ward_text_putc(b, 1, char2int1('o'))
  val b = ward_text_putc(b, 2, char2int1('l'))
  val b = ward_text_putc(b, 3, char2int1('y'))
  val b = ward_text_putc(b, 4, char2int1('l'))
  val b = ward_text_putc(b, 5, char2int1('i'))
  val b = ward_text_putc(b, 6, char2int1('n'))
  val b = ward_text_putc(b, 7, char2int1('e')) in ward_text_done(b) end

implement tag_blockquote() = let val b = ward_text_build(10)
  val b = ward_text_putc(b, 0, char2int1('b'))
  val b = ward_text_putc(b, 1, char2int1('l'))
  val b = ward_text_putc(b, 2, char2int1('o'))
  val b = ward_text_putc(b, 3, char2int1('c'))
  val b = ward_text_putc(b, 4, char2int1('k'))
  val b = ward_text_putc(b, 5, char2int1('q'))
  val b = ward_text_putc(b, 6, char2int1('u'))
  val b = ward_text_putc(b, 7, char2int1('o'))
  val b = ward_text_putc(b, 8, char2int1('t'))
  val b = ward_text_putc(b, 9, char2int1('e')) in ward_text_done(b) end
implement tag_figcaption() = let val b = ward_text_build(10)
  val b = ward_text_putc(b, 0, char2int1('f'))
  val b = ward_text_putc(b, 1, char2int1('i'))
  val b = ward_text_putc(b, 2, char2int1('g'))
  val b = ward_text_putc(b, 3, char2int1('c'))
  val b = ward_text_putc(b, 4, char2int1('a'))
  val b = ward_text_putc(b, 5, char2int1('p'))
  val b = ward_text_putc(b, 6, char2int1('t'))
  val b = ward_text_putc(b, 7, char2int1('i'))
  val b = ward_text_putc(b, 8, char2int1('o'))
  val b = ward_text_putc(b, 9, char2int1('n')) in ward_text_done(b) end

(* ========== Safe text builders: attributes ========== *)

implement attr_class() = let val b = ward_text_build(5)
  val b = ward_text_putc(b, 0, char2int1('c'))
  val b = ward_text_putc(b, 1, char2int1('l'))
  val b = ward_text_putc(b, 2, char2int1('a'))
  val b = ward_text_putc(b, 3, char2int1('s'))
  val b = ward_text_putc(b, 4, char2int1('s')) in ward_text_done(b) end
implement attr_id() = let val b = ward_text_build(2)
  val b = ward_text_putc(b, 0, char2int1('i'))
  val b = ward_text_putc(b, 1, char2int1('d')) in ward_text_done(b) end
implement attr_type() = let val b = ward_text_build(4)
  val b = ward_text_putc(b, 0, char2int1('t'))
  val b = ward_text_putc(b, 1, char2int1('y'))
  val b = ward_text_putc(b, 2, char2int1('p'))
  val b = ward_text_putc(b, 3, char2int1('e')) in ward_text_done(b) end
implement attr_for() = let val b = ward_text_build(3)
  val b = ward_text_putc(b, 0, char2int1('f'))
  val b = ward_text_putc(b, 1, char2int1('o'))
  val b = ward_text_putc(b, 2, char2int1('r')) in ward_text_done(b) end
implement attr_accept() = let val b = ward_text_build(6)
  val b = ward_text_putc(b, 0, char2int1('a'))
  val b = ward_text_putc(b, 1, char2int1('c'))
  val b = ward_text_putc(b, 2, char2int1('c'))
  val b = ward_text_putc(b, 3, char2int1('e'))
  val b = ward_text_putc(b, 4, char2int1('p'))
  val b = ward_text_putc(b, 5, char2int1('t')) in ward_text_done(b) end
implement attr_href() = let val b = ward_text_build(4)
  val b = ward_text_putc(b, 0, char2int1('h'))
  val b = ward_text_putc(b, 1, char2int1('r'))
  val b = ward_text_putc(b, 2, char2int1('e'))
  val b = ward_text_putc(b, 3, char2int1('f')) in ward_text_done(b) end
implement attr_src() = let val b = ward_text_build(3)
  val b = ward_text_putc(b, 0, char2int1('s'))
  val b = ward_text_putc(b, 1, char2int1('r'))
  val b = ward_text_putc(b, 2, char2int1('c')) in ward_text_done(b) end
implement attr_alt() = let val b = ward_text_build(3)
  val b = ward_text_putc(b, 0, char2int1('a'))
  val b = ward_text_putc(b, 1, char2int1('l'))
  val b = ward_text_putc(b, 2, char2int1('t')) in ward_text_done(b) end
implement attr_title() = let val b = ward_text_build(5)
  val b = ward_text_putc(b, 0, char2int1('t'))
  val b = ward_text_putc(b, 1, char2int1('i'))
  val b = ward_text_putc(b, 2, char2int1('t'))
  val b = ward_text_putc(b, 3, char2int1('l'))
  val b = ward_text_putc(b, 4, char2int1('e')) in ward_text_done(b) end
implement attr_width() = let val b = ward_text_build(5)
  val b = ward_text_putc(b, 0, char2int1('w'))
  val b = ward_text_putc(b, 1, char2int1('i'))
  val b = ward_text_putc(b, 2, char2int1('d'))
  val b = ward_text_putc(b, 3, char2int1('t'))
  val b = ward_text_putc(b, 4, char2int1('h')) in ward_text_done(b) end
implement attr_height() = let val b = ward_text_build(6)
  val b = ward_text_putc(b, 0, char2int1('h'))
  val b = ward_text_putc(b, 1, char2int1('e'))
  val b = ward_text_putc(b, 2, char2int1('i'))
  val b = ward_text_putc(b, 3, char2int1('g'))
  val b = ward_text_putc(b, 4, char2int1('h'))
  val b = ward_text_putc(b, 5, char2int1('t')) in ward_text_done(b) end
implement attr_lang() = let val b = ward_text_build(4)
  val b = ward_text_putc(b, 0, char2int1('l'))
  val b = ward_text_putc(b, 1, char2int1('a'))
  val b = ward_text_putc(b, 2, char2int1('n'))
  val b = ward_text_putc(b, 3, char2int1('g')) in ward_text_done(b) end
implement attr_dir() = let val b = ward_text_build(3)
  val b = ward_text_putc(b, 0, char2int1('d'))
  val b = ward_text_putc(b, 1, char2int1('i'))
  val b = ward_text_putc(b, 2, char2int1('r')) in ward_text_done(b) end
implement attr_role() = let val b = ward_text_build(4)
  val b = ward_text_putc(b, 0, char2int1('r'))
  val b = ward_text_putc(b, 1, char2int1('o'))
  val b = ward_text_putc(b, 2, char2int1('l'))
  val b = ward_text_putc(b, 3, char2int1('e')) in ward_text_done(b) end
implement attr_tabindex() = let val b = ward_text_build(8)
  val b = ward_text_putc(b, 0, char2int1('t'))
  val b = ward_text_putc(b, 1, char2int1('a'))
  val b = ward_text_putc(b, 2, char2int1('b'))
  val b = ward_text_putc(b, 3, char2int1('i'))
  val b = ward_text_putc(b, 4, char2int1('n'))
  val b = ward_text_putc(b, 5, char2int1('d'))
  val b = ward_text_putc(b, 6, char2int1('e'))
  val b = ward_text_putc(b, 7, char2int1('x')) in ward_text_done(b) end
implement attr_colspan() = let val b = ward_text_build(7)
  val b = ward_text_putc(b, 0, char2int1('c'))
  val b = ward_text_putc(b, 1, char2int1('o'))
  val b = ward_text_putc(b, 2, char2int1('l'))
  val b = ward_text_putc(b, 3, char2int1('s'))
  val b = ward_text_putc(b, 4, char2int1('p'))
  val b = ward_text_putc(b, 5, char2int1('a'))
  val b = ward_text_putc(b, 6, char2int1('n')) in ward_text_done(b) end
implement attr_rowspan() = let val b = ward_text_build(7)
  val b = ward_text_putc(b, 0, char2int1('r'))
  val b = ward_text_putc(b, 1, char2int1('o'))
  val b = ward_text_putc(b, 2, char2int1('w'))
  val b = ward_text_putc(b, 3, char2int1('s'))
  val b = ward_text_putc(b, 4, char2int1('p'))
  val b = ward_text_putc(b, 5, char2int1('a'))
  val b = ward_text_putc(b, 6, char2int1('n')) in ward_text_done(b) end
implement attr_xmlns() = let val b = ward_text_build(5)
  val b = ward_text_putc(b, 0, char2int1('x'))
  val b = ward_text_putc(b, 1, char2int1('m'))
  val b = ward_text_putc(b, 2, char2int1('l'))
  val b = ward_text_putc(b, 3, char2int1('n'))
  val b = ward_text_putc(b, 4, char2int1('s')) in ward_text_done(b) end
implement attr_d() = let val b = ward_text_build(1)
  val b = ward_text_putc(b, 0, char2int1('d')) in ward_text_done(b) end
implement attr_fill() = let val b = ward_text_build(4)
  val b = ward_text_putc(b, 0, char2int1('f'))
  val b = ward_text_putc(b, 1, char2int1('i'))
  val b = ward_text_putc(b, 2, char2int1('l'))
  val b = ward_text_putc(b, 3, char2int1('l')) in ward_text_done(b) end
implement attr_stroke() = let val b = ward_text_build(6)
  val b = ward_text_putc(b, 0, char2int1('s'))
  val b = ward_text_putc(b, 1, char2int1('t'))
  val b = ward_text_putc(b, 2, char2int1('r'))
  val b = ward_text_putc(b, 3, char2int1('o'))
  val b = ward_text_putc(b, 4, char2int1('k'))
  val b = ward_text_putc(b, 5, char2int1('e')) in ward_text_done(b) end
implement attr_cx() = let val b = ward_text_build(2)
  val b = ward_text_putc(b, 0, char2int1('c'))
  val b = ward_text_putc(b, 1, char2int1('x')) in ward_text_done(b) end
implement attr_cy() = let val b = ward_text_build(2)
  val b = ward_text_putc(b, 0, char2int1('c'))
  val b = ward_text_putc(b, 1, char2int1('y')) in ward_text_done(b) end
implement attr_r() = let val b = ward_text_build(1)
  val b = ward_text_putc(b, 0, char2int1('r')) in ward_text_done(b) end
implement attr_x() = let val b = ward_text_build(1)
  val b = ward_text_putc(b, 0, char2int1('x')) in ward_text_done(b) end
implement attr_y() = let val b = ward_text_build(1)
  val b = ward_text_putc(b, 0, char2int1('y')) in ward_text_done(b) end
implement attr_transform() = let val b = ward_text_build(9)
  val b = ward_text_putc(b, 0, char2int1('t'))
  val b = ward_text_putc(b, 1, char2int1('r'))
  val b = ward_text_putc(b, 2, char2int1('a'))
  val b = ward_text_putc(b, 3, char2int1('n'))
  val b = ward_text_putc(b, 4, char2int1('s'))
  val b = ward_text_putc(b, 5, char2int1('f'))
  val b = ward_text_putc(b, 6, char2int1('o'))
  val b = ward_text_putc(b, 7, char2int1('r'))
  val b = ward_text_putc(b, 8, char2int1('m')) in ward_text_done(b) end
implement attr_viewBox() = let val b = ward_text_build(7)
  val b = ward_text_putc(b, 0, char2int1('v'))
  val b = ward_text_putc(b, 1, char2int1('i'))
  val b = ward_text_putc(b, 2, char2int1('e'))
  val b = ward_text_putc(b, 3, char2int1('w'))
  val b = ward_text_putc(b, 4, 66) (* 'B' *)
  val b = ward_text_putc(b, 5, char2int1('o'))
  val b = ward_text_putc(b, 6, char2int1('x')) in ward_text_done(b) end
implement attr_aria_label() = let val b = ward_text_build(10)
  val b = ward_text_putc(b, 0, char2int1('a'))
  val b = ward_text_putc(b, 1, char2int1('r'))
  val b = ward_text_putc(b, 2, char2int1('i'))
  val b = ward_text_putc(b, 3, char2int1('a'))
  val b = ward_text_putc(b, 4, 45) (* '-' *)
  val b = ward_text_putc(b, 5, char2int1('l'))
  val b = ward_text_putc(b, 6, char2int1('a'))
  val b = ward_text_putc(b, 7, char2int1('b'))
  val b = ward_text_putc(b, 8, char2int1('e'))
  val b = ward_text_putc(b, 9, char2int1('l')) in ward_text_done(b) end
implement attr_aria_hidden() = let val b = ward_text_build(11)
  val b = ward_text_putc(b, 0, char2int1('a'))
  val b = ward_text_putc(b, 1, char2int1('r'))
  val b = ward_text_putc(b, 2, char2int1('i'))
  val b = ward_text_putc(b, 3, char2int1('a'))
  val b = ward_text_putc(b, 4, 45) (* '-' *)
  val b = ward_text_putc(b, 5, char2int1('h'))
  val b = ward_text_putc(b, 6, char2int1('i'))
  val b = ward_text_putc(b, 7, char2int1('d'))
  val b = ward_text_putc(b, 8, char2int1('d'))
  val b = ward_text_putc(b, 9, char2int1('e'))
  val b = ward_text_putc(b, 10, char2int1('n')) in ward_text_done(b) end
implement attr_name() = let val b = ward_text_build(4)
  val b = ward_text_putc(b, 0, char2int1('n'))
  val b = ward_text_putc(b, 1, char2int1('a'))
  val b = ward_text_putc(b, 2, char2int1('m'))
  val b = ward_text_putc(b, 3, char2int1('e')) in ward_text_done(b) end
implement attr_value() = let val b = ward_text_build(5)
  val b = ward_text_putc(b, 0, char2int1('v'))
  val b = ward_text_putc(b, 1, char2int1('a'))
  val b = ward_text_putc(b, 2, char2int1('l'))
  val b = ward_text_putc(b, 3, char2int1('u'))
  val b = ward_text_putc(b, 4, char2int1('e')) in ward_text_done(b) end

(* ========== Tree binary byte readers ========== *)

(* ========== Ward array byte access ========== *)

(* Bounds-checked byte read from ward_arr (erased to ptr at runtime).
 * Same mac# pattern as zip.dats. *)
extern fun ward_arr_byte {l:agz}{n:pos}
  (arr: !ward_arr(byte, l, n), off: int, len: int n): int = "mac#_ward_arr_byte"

fn rd_u16 {lb:agz}{n:pos}
  (tree: !ward_arr(byte, lb, n), off: int, len: int n): int = let
  extern fun bor(a: int, b: int): int = "mac#quire_bor"
  extern fun bsl(a: int, b: int): int = "mac#quire_bsl"
  val b0 = ward_arr_byte(tree, off, len)
  val b1 = ward_arr_byte(tree, off + 1, len)
in bor(b0, bsl(b1, 8)) end

(* Copy bytes between ward_arrs. Both erase to ptr at runtime.
 * Copies count bytes from src[src_off..] to dst[0..count-1].
 * Implemented by _copy_to_arr in quire_runtime.c. *)
extern fun copy_arr_bytes {la:agz}{na:pos}{lb:agz}{nb:pos}
  (dst: !ward_arr(byte, la, na), src: !ward_arr(byte, lb, nb),
   src_off: int, count: int): int = "mac#_copy_to_arr"

(* ========== Lookup dispatch via index ========== *)

(* These dispatch functions call the correct tag/attr builder based on index.
 * The index comes from lookup_tag/lookup_attr which maps bytes to table entries.
 * Each builder returns a ward_safe_text — the only way to create one. *)

implement get_tag_by_index(idx) =
  if idx = 0 then @(tag_div(), 3)
  else if idx = 1 then @(tag_span(), 4)
  else if idx = 2 then @(tag_button(), 6)
  else if idx = 3 then @(tag_style(), 5)
  else if idx = 4 then @(tag_h1(), 2)
  else if idx = 5 then @(tag_h2(), 2)
  else if idx = 6 then @(tag_h3(), 2)
  else if idx = 7 then @(tag_p(), 1)
  else if idx = 8 then @(tag_input(), 5)
  else if idx = 9 then @(tag_label(), 5)
  else if idx = 10 then @(tag_select(), 6)
  else if idx = 11 then @(tag_option(), 6)
  else if idx = 12 then @(tag_a(), 1)
  else if idx = 13 then @(tag_img(), 3)
  else if idx = 14 then @(tag_b(), 1)
  else if idx = 15 then @(tag_i(), 1)
  else if idx = 16 then @(tag_u(), 1)
  else if idx = 17 then @(tag_s(), 1)
  else if idx = 18 then @(tag_q(), 1)
  else if idx = 19 then @(tag_em(), 2)
  else if idx = 20 then @(tag_br(), 2)
  else if idx = 21 then @(tag_hr(), 2)
  else if idx = 22 then @(tag_li(), 2)
  else if idx = 23 then @(tag_dd(), 2)
  else if idx = 24 then @(tag_dl(), 2)
  else if idx = 25 then @(tag_dt(), 2)
  else if idx = 26 then @(tag_ol(), 2)
  else if idx = 27 then @(tag_ul(), 2)
  else if idx = 28 then @(tag_td(), 2)
  else if idx = 29 then @(tag_th(), 2)
  else if idx = 30 then @(tag_tr(), 2)
  else if idx = 31 then @(tag_h4(), 2)
  else if idx = 32 then @(tag_h5(), 2)
  else if idx = 33 then @(tag_h6(), 2)
  else if idx = 34 then @(tag_pre(), 3)
  else if idx = 35 then @(tag_sub(), 3)
  else if idx = 36 then @(tag_sup(), 3)
  else if idx = 37 then @(tag_var(), 3)
  else if idx = 38 then @(tag_wbr(), 3)
  else if idx = 39 then @(tag_nav(), 3)
  else if idx = 40 then @(tag_kbd(), 3)
  else if idx = 41 then @(tag_code(), 4)
  else if idx = 42 then @(tag_mark(), 4)
  else if idx = 43 then @(tag_cite(), 4)
  else if idx = 44 then @(tag_abbr(), 4)
  else if idx = 45 then @(tag_dfn(), 3)
  else if idx = 46 then @(tag_main(), 4)
  else if idx = 47 then @(tag_time(), 4)
  else if idx = 48 then @(tag_ruby(), 4)
  else if idx = 49 then @(tag_aside(), 5)
  else if idx = 50 then @(tag_small(), 5)
  else if idx = 51 then @(tag_table(), 5)
  else if idx = 52 then @(tag_thead(), 5)
  else if idx = 53 then @(tag_tbody(), 5)
  else if idx = 54 then @(tag_tfoot(), 5)
  else if idx = 55 then @(tag_strong(), 6)
  else if idx = 56 then @(tag_figure(), 6)
  else if idx = 57 then @(tag_footer(), 6)
  else if idx = 58 then @(tag_header(), 6)
  else if idx = 59 then @(tag_section(), 7)
  else if idx = 60 then @(tag_article(), 7)
  else if idx = 61 then @(tag_details(), 7)
  else if idx = 62 then @(tag_summary(), 7)
  else if idx = 63 then @(tag_caption(), 7)
  else if idx = 64 then @(tag_blockquote(), 10)
  else if idx = 65 then @(tag_figcaption(), 10)
  else if idx = 66 then @(tag_svg(), 3)
  else if idx = 67 then @(tag_g(), 1)
  else if idx = 68 then @(tag_path(), 4)
  else if idx = 69 then @(tag_circle(), 6)
  else if idx = 70 then @(tag_rect(), 4)
  else if idx = 71 then @(tag_line(), 4)
  else if idx = 72 then @(tag_polyline(), 8)
  else if idx = 73 then @(tag_polygon(), 7)
  else if idx = 74 then @(tag_text(), 4)
  else if idx = 75 then @(tag_tspan(), 5)
  else if idx = 76 then @(tag_use(), 3)
  else if idx = 77 then @(tag_defs(), 4)
  else if idx = 78 then @(tag_image(), 5)
  else if idx = 79 then @(tag_symbol(), 6)
  else if idx = 80 then @(tag_title(), 5)
  else if idx = 81 then @(tag_desc(), 4)
  else if idx = 82 then @(tag_math(), 4)
  else if idx = 83 then @(tag_mi(), 2)
  else if idx = 84 then @(tag_mn(), 2)
  else if idx = 85 then @(tag_mo(), 2)
  else if idx = 86 then @(tag_mrow(), 4)
  else if idx = 87 then @(tag_msup(), 4)
  else if idx = 88 then @(tag_msub(), 4)
  else if idx = 89 then @(tag_mfrac(), 5)
  else if idx = 90 then @(tag_msqrt(), 5)
  else if idx = 91 then @(tag_mroot(), 5)
  else if idx = 92 then @(tag_mover(), 5)
  else if idx = 93 then @(tag_munder(), 6)
  else if idx = 94 then @(tag_mtable(), 6)
  else if idx = 95 then @(tag_mtr(), 3)
  else if idx = 96 then @(tag_mtd(), 3)
  else if idx = 97 then @(tag_rp(), 2)
  else @(tag_rt(), 2)  (* idx = 98 *)

implement get_attr_by_index(idx) =
  if idx = 0 then @(attr_class(), 5)
  else if idx = 1 then @(attr_id(), 2)
  else if idx = 2 then @(attr_type(), 4)
  else if idx = 3 then @(attr_for(), 3)
  else if idx = 4 then @(attr_accept(), 6)
  else if idx = 5 then @(attr_href(), 4)
  else if idx = 6 then @(attr_src(), 3)
  else if idx = 7 then @(attr_alt(), 3)
  else if idx = 8 then @(attr_title(), 5)
  else if idx = 9 then @(attr_width(), 5)
  else if idx = 10 then @(attr_height(), 6)
  else if idx = 11 then @(attr_lang(), 4)
  else if idx = 12 then @(attr_dir(), 3)
  else if idx = 13 then @(attr_role(), 4)
  else if idx = 14 then @(attr_tabindex(), 8)
  else if idx = 15 then @(attr_colspan(), 7)
  else if idx = 16 then @(attr_rowspan(), 7)
  else if idx = 17 then @(attr_xmlns(), 5)
  else if idx = 18 then @(attr_d(), 1)
  else if idx = 19 then @(attr_fill(), 4)
  else if idx = 20 then @(attr_stroke(), 6)
  else if idx = 21 then @(attr_cx(), 2)
  else if idx = 22 then @(attr_cy(), 2)
  else if idx = 23 then @(attr_r(), 1)
  else if idx = 24 then @(attr_x(), 1)
  else if idx = 25 then @(attr_y(), 1)
  else if idx = 26 then @(attr_transform(), 9)
  else if idx = 27 then @(attr_viewBox(), 7)
  else if idx = 28 then @(attr_aria_label(), 10)
  else if idx = 29 then @(attr_aria_hidden(), 11)
  else if idx = 30 then @(attr_name(), 4)
  else @(attr_value(), 5) (* idx = 31 *)

(* ========== Tree renderer ========== *)

(* Binary format from wardJsParseHtml:
 * ELEMENT_OPEN (0x01):  tag_len:u8  tag:bytes  attr_count:u8
 *   [attr_name_len:u8  attr_name:bytes  attr_value_len:u16LE  attr_value:bytes]...
 * TEXT (0x03):  text_len:u16LE  text:bytes
 * ELEMENT_CLOSE (0x02):  (no payload)
 *)

(* Ward DOM buffer cap — text needs tl + 7 <= 262144, attr needs nl + vl + 8 <= 262144.
 * Max attr name is 11 chars, so vl + 19 <= 262144. Auto-flush handles large payloads. *)

implement render_tree{l}{lb}{n}(stream, parent_id, tree, tree_len) = let

  fun loop {l:agz}{lb:agz}{n:pos}
    (st: ward_dom_stream(l), tree: !ward_arr(byte, lb, n),
     pos: int, len: int, parent: int, tlen: int n)
    : @(ward_dom_stream(l), int) =
    if pos >= len then @(st, pos)
    else let
      val opc = ward_arr_byte(tree, pos, tlen)
    in
      if opc = 1 then let (* ELEMENT_OPEN *)
        val tag_len = ward_arr_byte(tree, pos + 1, tlen)
        val tag_idx = lookup_tag(tree, pos + 2, tag_len)
        val attr_off = pos + 2 + tag_len
        val attr_count = ward_arr_byte(tree, attr_off, tlen)
        val after_attrs = skip_attrs(tree, attr_off + 1, attr_count, tlen)
      in
        if tag_idx >= 0 then let
          val @(tag_st, tag_st_len) = get_tag_by_index(tag_idx)
          val nid = dom_next_id()
          val st = ward_dom_stream_create_element(st, nid, parent, tag_st, tag_st_len)
          val st = emit_attrs(st, nid, tree, attr_off + 1, attr_count, tlen)
          val @(st, child_end) = loop(st, tree, after_attrs, len, nid, tlen)
        in
          if child_end < len then let
            val close_opc = ward_arr_byte(tree, child_end, tlen)
          in
            if close_opc = 2 then @(st, child_end + 1)
            else @(st, child_end)
          end
          else @(st, child_end)
        end
        else let
          val end_pos = skip_element(tree, after_attrs, len, tlen)
        in
          loop(st, tree, end_pos, len, parent, tlen)
        end
      end
      else if opc = 3 then let (* TEXT *)
        val text_len = rd_u16(tree, pos + 1, tlen)
        val text_start = pos + 3
        val tl = g1ofg0(text_len)
      in
        if tl > 0 then
          if tl + 7 <= 262144 then let
            val text_arr = ward_arr_alloc<byte>(tl)
            val _ = copy_arr_bytes(text_arr, tree, text_start, text_len)
            val @(frozen, borrow) = ward_arr_freeze<byte>(text_arr)
            val st = ward_dom_stream_set_text(st, parent, borrow, tl)
            val () = ward_arr_drop<byte>(frozen, borrow)
            val text_arr = ward_arr_thaw<byte>(frozen)
            val () = ward_arr_free<byte>(text_arr)
          in
            loop(st, tree, text_start + text_len, len, parent, tlen)
          end
          else (* text too large for DOM buffer — skip *)
            loop(st, tree, text_start + text_len, len, parent, tlen)
        else loop(st, tree, text_start + text_len, len, parent, tlen)
      end
      else if opc = 2 then (* ELEMENT_CLOSE — return to parent *)
        @(st, pos)
      else (* Unknown opcode — skip byte *)
        loop(st, tree, pos + 1, len, parent, tlen)
    end
  and skip_attrs {lb:agz}{n:pos}
    (tree: !ward_arr(byte, lb, n), pos: int, count: int, tlen: int n): int =
    if count <= 0 then pos
    else let
      val name_len = ward_arr_byte(tree, pos, tlen)
      val val_len = rd_u16(tree, pos + 1 + name_len, tlen)
    in
      skip_attrs(tree, pos + 1 + name_len + 2 + val_len, count - 1, tlen)
    end
  and emit_attrs {l:agz}{lb:agz}{n:pos}
    (st: ward_dom_stream(l), nid: int, tree: !ward_arr(byte, lb, n),
     pos: int, count: int, tlen: int n)
    : ward_dom_stream(l) =
    if count <= 0 then st
    else let
      val name_len = ward_arr_byte(tree, pos, tlen)
      val attr_idx = lookup_attr(tree, pos + 1, name_len)
      val val_off = pos + 1 + name_len
      val val_len = rd_u16(tree, val_off, tlen)
      val val_start = val_off + 2
    in
      if attr_idx >= 0 then let
        val @(attr_st, attr_st_len) = get_attr_by_index(attr_idx)
        val vl = g1ofg0(val_len)
      in
        if vl > 0 then
          if attr_st_len + vl + 8 <= 262144 then let
            val val_arr = ward_arr_alloc<byte>(vl)
            val _ = copy_arr_bytes(val_arr, tree, val_start, val_len)
            val @(frozen, borrow) = ward_arr_freeze<byte>(val_arr)
            val st = ward_dom_stream_set_attr(st, nid, attr_st, attr_st_len, borrow, vl)
            val () = ward_arr_drop<byte>(frozen, borrow)
            val val_arr = ward_arr_thaw<byte>(frozen)
            val () = ward_arr_free<byte>(val_arr)
          in
            emit_attrs(st, nid, tree, val_start + val_len, count - 1, tlen)
          end
          else (* attr value too large for DOM buffer — skip *)
            emit_attrs(st, nid, tree, val_start + val_len, count - 1, tlen)
        else (* empty attr value — skip *)
          emit_attrs(st, nid, tree, val_start, count - 1, tlen)
      end
      else (* Unknown attribute — skip *)
        emit_attrs(st, nid, tree, val_start + val_len, count - 1, tlen)
    end
  and skip_element {lb:agz}{n:pos}
    (tree: !ward_arr(byte, lb, n), pos: int, len: int, tlen: int n): int =
    if pos >= len then pos
    else let
      val opc = ward_arr_byte(tree, pos, tlen)
    in
      if opc = 2 then pos + 1  (* ELEMENT_CLOSE *)
      else if opc = 1 then let (* nested ELEMENT_OPEN *)
        val tag_len = ward_arr_byte(tree, pos + 1, tlen)
        val attr_off = pos + 2 + tag_len
        val attr_count = ward_arr_byte(tree, attr_off, tlen)
        val after_attrs = skip_attrs(tree, attr_off + 1, attr_count, tlen)
        val end_inner = skip_element(tree, after_attrs, len, tlen)
      in
        skip_element(tree, end_inner, len, tlen)
      end
      else if opc = 3 then let (* TEXT *)
        val text_len = rd_u16(tree, pos + 1, tlen)
      in
        skip_element(tree, pos + 3 + text_len, len, tlen)
      end
      else skip_element(tree, pos + 1, len, tlen) (* unknown — skip byte *)
    end

  val @(st, _) = loop(stream, tree, 0, tree_len, parent_id, tree_len)
in
  st
end
