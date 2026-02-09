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
staload _ = "./../vendor/ward/lib/memory.dats"
staload _ = "./../vendor/ward/lib/dom.dats"

(* ========== Node ID allocator ========== *)

extern fun get_dom_next_node_id(): int = "mac#"
extern fun set_dom_next_node_id(v: int): void = "mac#"

implement dom_next_id() = let
  val id = get_dom_next_node_id()
  val () = set_dom_next_node_id(id + 1)
  extern castfn to_pos(x: int): [n:int | n > 0] int n
in
  to_pos(id)
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

(* Lookup tables for tag/attr are in quire_runtime.c (mac# functions).
 * Byte readers use buf_get_u8 from runtime.h. *)

extern fun _rd_u8(p: ptr, off: int): int = "mac#buf_get_u8"

fn _rd_u16(p: ptr, off: int): int = let
  extern fun bor(a: int, b: int): int = "mac#quire_bor"
  extern fun bsl(a: int, b: int): int = "mac#quire_bsl"
  val b0 = _rd_u8(p, off)
  val b1 = _rd_u8(p, off + 1)
in bor(b0, bsl(b1, 8)) end

(* ========== Lookup dispatch via index ========== *)

(* These dispatch functions call the correct tag/attr builder based on index.
 * The index comes from lookup_tag/lookup_attr which maps bytes to table entries.
 * Each builder returns a ward_safe_text — the only way to create one. *)

implement get_tag_by_index(idx) = let
  extern castfn to_existential
    {n:pos}(x: @(ward_safe_text(n), int n)): [m:pos | m <= 10] @(ward_safe_text(m), int m)
in
  (* Use C dispatch since ATS2 doesn't support pattern matching on
   * runtime int values into dependent types. Each branch returns a
   * concrete ward_safe_text(n) which is erased to ptr. *)
  if idx = 0 then to_existential(@(tag_div(), 3))
  else if idx = 1 then to_existential(@(tag_span(), 4))
  else if idx = 2 then to_existential(@(tag_button(), 6))
  else if idx = 3 then to_existential(@(tag_style(), 5))
  else if idx = 4 then to_existential(@(tag_h1(), 2))
  else if idx = 5 then to_existential(@(tag_h2(), 2))
  else if idx = 6 then to_existential(@(tag_h3(), 2))
  else if idx = 7 then to_existential(@(tag_p(), 1))
  else if idx = 8 then to_existential(@(tag_input(), 5))
  else if idx = 9 then to_existential(@(tag_label(), 5))
  else if idx = 10 then to_existential(@(tag_select(), 6))
  else if idx = 11 then to_existential(@(tag_option(), 6))
  else if idx = 12 then to_existential(@(tag_a(), 1))
  else if idx = 13 then to_existential(@(tag_img(), 3))
  else if idx = 14 then to_existential(@(tag_b(), 1))
  else if idx = 15 then to_existential(@(tag_i(), 1))
  else if idx = 16 then to_existential(@(tag_u(), 1))
  else if idx = 17 then to_existential(@(tag_s(), 1))
  else if idx = 18 then to_existential(@(tag_q(), 1))
  else if idx = 19 then to_existential(@(tag_em(), 2))
  else if idx = 20 then to_existential(@(tag_br(), 2))
  else if idx = 21 then to_existential(@(tag_hr(), 2))
  else if idx = 22 then to_existential(@(tag_li(), 2))
  else if idx = 23 then to_existential(@(tag_dd(), 2))
  else if idx = 24 then to_existential(@(tag_dl(), 2))
  else if idx = 25 then to_existential(@(tag_dt(), 2))
  else if idx = 26 then to_existential(@(tag_ol(), 2))
  else if idx = 27 then to_existential(@(tag_ul(), 2))
  else if idx = 28 then to_existential(@(tag_td(), 2))
  else if idx = 29 then to_existential(@(tag_th(), 2))
  else if idx = 30 then to_existential(@(tag_tr(), 2))
  else if idx = 31 then to_existential(@(tag_h4(), 2))
  else if idx = 32 then to_existential(@(tag_h5(), 2))
  else if idx = 33 then to_existential(@(tag_h6(), 2))
  else if idx = 34 then to_existential(@(tag_pre(), 3))
  else if idx = 35 then to_existential(@(tag_sub(), 3))
  else if idx = 36 then to_existential(@(tag_sup(), 3))
  else if idx = 37 then to_existential(@(tag_var(), 3))
  else if idx = 38 then to_existential(@(tag_wbr(), 3))
  else if idx = 39 then to_existential(@(tag_nav(), 3))
  else if idx = 40 then to_existential(@(tag_kbd(), 3))
  else if idx = 41 then to_existential(@(tag_code(), 4))
  else if idx = 42 then to_existential(@(tag_mark(), 4))
  else if idx = 43 then to_existential(@(tag_cite(), 4))
  else if idx = 44 then to_existential(@(tag_abbr(), 4))
  else if idx = 45 then to_existential(@(tag_dfn(), 3))
  else if idx = 46 then to_existential(@(tag_main(), 4))
  else if idx = 47 then to_existential(@(tag_time(), 4))
  else if idx = 48 then to_existential(@(tag_ruby(), 4))
  else if idx = 49 then to_existential(@(tag_aside(), 5))
  else if idx = 50 then to_existential(@(tag_small(), 5))
  else if idx = 51 then to_existential(@(tag_table(), 5))
  else if idx = 52 then to_existential(@(tag_thead(), 5))
  else if idx = 53 then to_existential(@(tag_tbody(), 5))
  else if idx = 54 then to_existential(@(tag_tfoot(), 5))
  else if idx = 55 then to_existential(@(tag_strong(), 6))
  else if idx = 56 then to_existential(@(tag_figure(), 6))
  else if idx = 57 then to_existential(@(tag_footer(), 6))
  else if idx = 58 then to_existential(@(tag_header(), 6))
  else if idx = 59 then to_existential(@(tag_section(), 7))
  else if idx = 60 then to_existential(@(tag_article(), 7))
  else if idx = 61 then to_existential(@(tag_details(), 7))
  else if idx = 62 then to_existential(@(tag_summary(), 7))
  else if idx = 63 then to_existential(@(tag_caption(), 7))
  else if idx = 64 then to_existential(@(tag_blockquote(), 10))
  else if idx = 65 then to_existential(@(tag_figcaption(), 10))
  else if idx = 66 then to_existential(@(tag_svg(), 3))
  else if idx = 67 then to_existential(@(tag_g(), 1))
  else if idx = 68 then to_existential(@(tag_path(), 4))
  else if idx = 69 then to_existential(@(tag_circle(), 6))
  else if idx = 70 then to_existential(@(tag_rect(), 4))
  else if idx = 71 then to_existential(@(tag_line(), 4))
  else if idx = 72 then to_existential(@(tag_polyline(), 8))
  else if idx = 73 then to_existential(@(tag_polygon(), 7))
  else if idx = 74 then to_existential(@(tag_text(), 4))
  else if idx = 75 then to_existential(@(tag_tspan(), 5))
  else if idx = 76 then to_existential(@(tag_use(), 3))
  else if idx = 77 then to_existential(@(tag_defs(), 4))
  else if idx = 78 then to_existential(@(tag_image(), 5))
  else if idx = 79 then to_existential(@(tag_symbol(), 6))
  else if idx = 80 then to_existential(@(tag_title(), 5))
  else if idx = 81 then to_existential(@(tag_desc(), 4))
  else if idx = 82 then to_existential(@(tag_math(), 4))
  else if idx = 83 then to_existential(@(tag_mi(), 2))
  else if idx = 84 then to_existential(@(tag_mn(), 2))
  else if idx = 85 then to_existential(@(tag_mo(), 2))
  else if idx = 86 then to_existential(@(tag_mrow(), 4))
  else if idx = 87 then to_existential(@(tag_msup(), 4))
  else if idx = 88 then to_existential(@(tag_msub(), 4))
  else if idx = 89 then to_existential(@(tag_mfrac(), 5))
  else if idx = 90 then to_existential(@(tag_msqrt(), 5))
  else if idx = 91 then to_existential(@(tag_mroot(), 5))
  else if idx = 92 then to_existential(@(tag_mover(), 5))
  else if idx = 93 then to_existential(@(tag_munder(), 6))
  else if idx = 94 then to_existential(@(tag_mtable(), 6))
  else if idx = 95 then to_existential(@(tag_mtr(), 3))
  else if idx = 96 then to_existential(@(tag_mtd(), 3))
  else if idx = 97 then to_existential(@(tag_rp(), 2))
  else to_existential(@(tag_rt(), 2))  (* idx = 98 *)
end

implement get_attr_by_index(idx) = let
  extern castfn to_existential
    {n:pos}(x: @(ward_safe_text(n), int n)): [m:pos | m <= 11] @(ward_safe_text(m), int m)
in
  if idx = 0 then to_existential(@(attr_class(), 5))
  else if idx = 1 then to_existential(@(attr_id(), 2))
  else if idx = 2 then to_existential(@(attr_type(), 4))
  else if idx = 3 then to_existential(@(attr_for(), 3))
  else if idx = 4 then to_existential(@(attr_accept(), 6))
  else if idx = 5 then to_existential(@(attr_href(), 4))
  else if idx = 6 then to_existential(@(attr_src(), 3))
  else if idx = 7 then to_existential(@(attr_alt(), 3))
  else if idx = 8 then to_existential(@(attr_title(), 5))
  else if idx = 9 then to_existential(@(attr_width(), 5))
  else if idx = 10 then to_existential(@(attr_height(), 6))
  else if idx = 11 then to_existential(@(attr_lang(), 4))
  else if idx = 12 then to_existential(@(attr_dir(), 3))
  else if idx = 13 then to_existential(@(attr_role(), 4))
  else if idx = 14 then to_existential(@(attr_tabindex(), 8))
  else if idx = 15 then to_existential(@(attr_colspan(), 7))
  else if idx = 16 then to_existential(@(attr_rowspan(), 7))
  else if idx = 17 then to_existential(@(attr_xmlns(), 5))
  else if idx = 18 then to_existential(@(attr_d(), 1))
  else if idx = 19 then to_existential(@(attr_fill(), 4))
  else if idx = 20 then to_existential(@(attr_stroke(), 6))
  else if idx = 21 then to_existential(@(attr_cx(), 2))
  else if idx = 22 then to_existential(@(attr_cy(), 2))
  else if idx = 23 then to_existential(@(attr_r(), 1))
  else if idx = 24 then to_existential(@(attr_x(), 1))
  else if idx = 25 then to_existential(@(attr_y(), 1))
  else if idx = 26 then to_existential(@(attr_transform(), 9))
  else if idx = 27 then to_existential(@(attr_viewBox(), 7))
  else if idx = 28 then to_existential(@(attr_aria_label(), 10))
  else if idx = 29 then to_existential(@(attr_aria_hidden(), 11))
  else if idx = 30 then to_existential(@(attr_name(), 4))
  else to_existential(@(attr_value(), 5)) (* idx = 31 *)
end

(* ========== Tree renderer ========== *)

(* Binary format from wardJsParseHtml:
 * ELEMENT_OPEN (0x01):  tag_len:u8  tag:bytes  attr_count:u8
 *   [attr_name_len:u8  attr_name:bytes  attr_value_len:u16LE  attr_value:bytes]...
 * TEXT (0x03):  text_len:u16LE  text:bytes
 * ELEMENT_CLOSE (0x02):  (no payload)
 *)

(* C helper: copy bytes from src+off into ward_arr dst, count bytes *)
extern fun _copy_to_arr(dst: ptr, src: ptr, off: int, count: int): void = "mac#"

(* Cast plain int to dependent int — used for ward API calls.
 * These are safe because all tag/attr names are <= 11 chars (max is "aria-hidden"),
 * so the constraint tl + 10 <= 4096 is always met. *)
extern castfn _to_pos(x: int): [n:pos] int n
extern castfn _to_nat(x: int): [n:nat] int n
(* Cast dynamic ints to satisfy ward DOM buffer constraints.
 * Safe because: text_len from HTML binary is bounded in practice,
 * and attr values are also bounded. These castfns just tell the
 * constraint solver what the runtime bounds are. *)
extern castfn _to_text_len(x: int): [n:nat | n + 7 <= 4096] int n
extern castfn _to_attr_vlen(x: int): [n:nat | n + 20 <= 4096] int n

(* Helper: emit set_text using raw ptr + length.
 * Fabricates a borrow from the ptr for ward_dom_set_text. *)
fn emit_set_text {l:agz}{tl:nat | tl + 7 <= 4096}
  (st: ward_dom_state(l), nid: int, raw_p: ptr, tl: int tl)
  : ward_dom_state(l) = let
  val borrow = $UNSAFE.castvwtp0{[lb:agz] ward_arr_borrow(byte, lb, tl)}(raw_p)
  val st = ward_dom_set_text(st, nid, borrow, tl)
  val () = $UNSAFE.castvwtp0{void}(borrow)
in st end

(* Helper: emit set_attr using raw ptr + lengths.
 * Fabricates a borrow from the ptr for ward_dom_set_attr. *)
fn emit_set_attr {l:agz}{nl:pos | nl <= 11}{vl:nat | nl + vl + 8 <= 4096}
  (st: ward_dom_state(l), nid: int,
   attr_st: ward_safe_text(nl), attr_st_len: int nl,
   raw_p: ptr, vl: int vl)
  : ward_dom_state(l) = let
  val borrow = $UNSAFE.castvwtp0{[lb:agz] ward_arr_borrow(byte, lb, vl)}(raw_p)
  val st = ward_dom_set_attr(st, nid, attr_st, attr_st_len, borrow, vl)
  val () = $UNSAFE.castvwtp0{void}(borrow)
in st end


(* _copy_to_arr implementation is in quire_runtime.c *)

(* Allocate a ward_arr and fill with bytes from tree binary.
 * Uses $UNSAFE.castvwtp0 to erase the dependent size from the
 * allocated array — the actual allocation matches `len`, but
 * the type system sees size 1 (sufficient for the cast-based
 * borrow protocol used in render_tree). *)
fn alloc_and_copy(src: ptr, off: int, len: int)
  : [l:agz] ward_arr(byte, l, 1) = let
  val alloc_len = (if len > 0 then len else 1): int
  val arr = ward_arr_alloc<byte>(_to_pos(alloc_len))
  val p = $UNSAFE.castvwtp1{ptr}(arr)
  val () = if len > 0 then _copy_to_arr(p, src, off, len)
in
  $UNSAFE.castvwtp0{[l:agz] ward_arr(byte, l, 1)}(arr)
end

implement render_tree{l}(state, parent_id, tree, tree_len) = let
  extern fun _ptr_add(p: ptr, n: int): ptr = "mac#quire_ptr_add"

  fun loop {l:agz}
    (st: ward_dom_state(l), p: ptr, pos: int, len: int, parent: int)
    : @(ward_dom_state(l), int) =
    if pos >= len then @(st, pos)
    else let
      val opc = _rd_u8(p, pos)
    in
      if opc = 1 then let (* ELEMENT_OPEN *)
        val tag_len = _rd_u8(p, pos + 1)
        val tag_idx = lookup_tag(_ptr_add(p, pos + 2), tag_len)
        val attr_off = pos + 2 + tag_len
        val attr_count = _rd_u8(p, attr_off)
        val after_attrs = skip_attrs(p, attr_off + 1, attr_count)
      in
        if tag_idx >= 0 then let
          val @(tag_st, tag_st_len) = get_tag_by_index(tag_idx)
          val nid = dom_next_id()
          val st = ward_dom_create_element(st, nid, parent, tag_st, tag_st_len)
          (* Emit attributes *)
          val st = emit_attrs(st, nid, p, attr_off + 1, attr_count)
          (* Recurse into children *)
          val @(st, child_end) = loop(st, p, after_attrs, len, nid)
        in
          (* child_end should be at ELEMENT_CLOSE — skip it *)
          if child_end < len then let
            val close_opc = _rd_u8(p, child_end)
          in
            if close_opc = 2 then @(st, child_end + 1)
            else @(st, child_end)
          end
          else @(st, child_end)
        end
        else let
          (* Unknown tag: skip children until matching ELEMENT_CLOSE *)
          val end_pos = skip_element(p, after_attrs, len)
        in
          loop(st, p, end_pos, len, parent)
        end
      end
      else if opc = 3 then let (* TEXT *)
        val text_len = _rd_u16(p, pos + 1)
        val text_start = pos + 3
      in
        if text_len > 0 then let
          val text_arr = alloc_and_copy(p, text_start, text_len)
          val raw_p = $UNSAFE.castvwtp1{ptr}(text_arr)
          val st = emit_set_text(st, parent, raw_p, _to_text_len(text_len))
          val () = ward_arr_free<byte>(text_arr)
        in
          loop(st, p, text_start + text_len, len, parent)
        end
        else loop(st, p, text_start + text_len, len, parent)
      end
      else if opc = 2 then (* ELEMENT_CLOSE — return to parent *)
        @(st, pos)
      else (* Unknown opcode — skip byte *)
        loop(st, p, pos + 1, len, parent)
    end
  and skip_attrs(p: ptr, pos: int, count: int): int =
    if count <= 0 then pos
    else let
      val name_len = _rd_u8(p, pos)
      val val_len = _rd_u16(p, pos + 1 + name_len)
    in
      skip_attrs(p, pos + 1 + name_len + 2 + val_len, count - 1)
    end
  and emit_attrs {l:agz}
    (st: ward_dom_state(l), nid: int, p: ptr, pos: int, count: int)
    : ward_dom_state(l) =
    if count <= 0 then st
    else let
      val name_len = _rd_u8(p, pos)
      val name_ptr = _ptr_add(p, pos + 1)
      val attr_idx = lookup_attr(name_ptr, name_len)
      val val_off = pos + 1 + name_len
      val val_len = _rd_u16(p, val_off)
      val val_start = val_off + 2
    in
      if attr_idx >= 0 then let
        val @(attr_st, attr_st_len) = get_attr_by_index(attr_idx)
        val val_arr = alloc_and_copy(p, val_start, val_len)
        val raw_p = $UNSAFE.castvwtp1{ptr}(val_arr)
        val st = emit_set_attr(st, nid, attr_st, attr_st_len, raw_p, _to_attr_vlen(val_len))
        val () = ward_arr_free<byte>(val_arr)
      in
        emit_attrs(st, nid, p, val_start + val_len, count - 1)
      end
      else (* Unknown attribute — skip *)
        emit_attrs(st, nid, p, val_start + val_len, count - 1)
    end
  and skip_element(p: ptr, pos: int, len: int): int =
    (* Skip past children of unknown element until ELEMENT_CLOSE *)
    if pos >= len then pos
    else let
      val opc = _rd_u8(p, pos)
    in
      if opc = 2 then pos + 1  (* ELEMENT_CLOSE *)
      else if opc = 1 then let (* nested ELEMENT_OPEN *)
        val tag_len = _rd_u8(p, pos + 1)
        val attr_off = pos + 2 + tag_len
        val attr_count = _rd_u8(p, attr_off)
        val after_attrs = skip_attrs(p, attr_off + 1, attr_count)
        val end_inner = skip_element(p, after_attrs, len)
      in
        skip_element(p, end_inner, len)
      end
      else if opc = 3 then let (* TEXT *)
        val text_len = _rd_u16(p, pos + 1)
      in
        skip_element(p, pos + 3 + text_len, len)
      end
      else skip_element(p, pos + 1, len) (* unknown — skip byte *)
    end

  val @(st, _) = loop(state, tree, 0, tree_len, parent_id)
in
  st
end
