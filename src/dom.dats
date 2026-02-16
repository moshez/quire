(* dom.dats — Quire DOM convenience layer implementation
 *
 * Builds ward_safe_text constants for tags and attributes.
 * Implements lookup tables and tree renderer.
 *)

#define ATS_DYNLOADFLAG 0

#include "share/atspre_staload.hats"
staload "./../vendor/ward/lib/memory.sats"
staload "./../vendor/ward/lib/dom.sats"
staload "./../vendor/ward/lib/file.sats"
staload "./dom.sats"
staload "./zip.sats"
staload "./app_state.sats"
staload "./arith.sats"
staload UN = "prelude/SATS/unsafe.sats"
staload _ = "./../vendor/ward/lib/memory.dats"
staload _ = "./../vendor/ward/lib/dom.dats"

(* ========== Render element count side channel ========== *)

(* C static variable avoids struct return across compilation units
 * which causes ABI mismatch with WASM LTO (different tyrec typedefs). *)
%{
static int _dom_render_ecnt = 0;
static int _dom_get_render_ecnt() { return _dom_render_ecnt; }
#define _dom_set_render_ecnt(n) (_dom_render_ecnt = (n))
%}

extern fun _dom_set_render_ecnt(n: int): void = "mac#"
extern fun _dom_get_render_ecnt_impl(): int = "mac#_dom_get_render_ecnt"

implement dom_get_render_ecnt() = _dom_get_render_ecnt_impl()

(* ========== Node ID allocator ========== *)

(* Loads app_state from callback registry, reads/increments counter,
 * stores app_state back. *)
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

(* Byte read from ward_arr — wraps ward_arr_get<byte> with castfn index *)
fn ward_arr_byte {l:agz}{n:pos}
  (arr: !ward_arr(byte, l, n), off: int, len: int n): int =
  byte2int0(ward_arr_get<byte>(arr, _ward_idx(off, len)))

fn rd_u16 {lb:agz}{n:pos}
  (tree: !ward_arr(byte, lb, n), off: int, len: int n): int = let
  val b0 = ward_arr_byte(tree, off, len)
  val b1 = ward_arr_byte(tree, off + 1, len)
in bor_int_int(b0, bsl_int_int(b1, 8)) end

(* Byte write to ward_arr — wraps ward_arr_write_byte with castfn index *)
fn ward_arr_set_byte {l:agz}{n:pos}
  (arr: !ward_arr(byte, l, n), off: int, len: int n, v: int): void =
  ward_arr_write_byte(arr, _ward_idx(off, len), _checked_byte(v))

(* Copy bytes between ward_arrs. Both erase to ptr at runtime.
 * Copies count bytes from src[src_off..] to dst[0..count-1]. *)
fn copy_arr_bytes {la:agz}{na:pos}{lb:agz}{nb:pos}
  (dst: !ward_arr(byte, la, na), dlen: int na,
   src: !ward_arr(byte, lb, nb), slen: int nb,
   src_off: int, count: int): void = let
  fun loop(dst: !ward_arr(byte, la, na), dlen: int na,
           src: !ward_arr(byte, lb, nb), slen: int nb,
           src_off: int, i: int, count: int): void =
    if i < count then let
      val b = ward_arr_byte(src, src_off + i, slen)
      val () = ward_arr_set_byte(dst, i, dlen, b)
    in loop(dst, dlen, src, slen, src_off, i + 1, count) end
in loop(dst, dlen, src, slen, src_off, 0, count) end

(* ========== Tag/Attribute lookup — static table + ATS2 loop ========== *)

(* Justification for C data tables (CLAUDE.md Rule 7 "Minimize C code"):
 * (a) ATS2 if-else dispatch generated 5314 lines of C with 300 local variables,
 *     crashing V8's WASM compiler. Static arrays are the standard C approach for
 *     lookup tables and cannot be expressed in ATS2 freestanding mode.
 * (b) The ATS2 decision tree was tried and works correctly but generates too-large
 *     WASM. A loop calling get_tag_by_index would allocate 99 ward_safe_text objects.
 * (c) Trade-off: ~40 lines of read-only C data vs. V8 crash on real-world pages.
 * (d) Safety: const arrays, no mutation, no aliasing. Lookup logic is in ATS2. *)

%{^
/* Tag name lookup table -- 99 HTML/SVG/MathML tags (384 bytes of name data).
 * Indices match get_tag_by_index. */
static const unsigned char _tag_names[] =
  "div" "span" "button" "style" "h1" "h2" "h3" "p"
  "input" "label" "select" "option" "a" "img" "b" "i" "u" "s" "q"
  "em" "br" "hr" "li" "dd" "dl" "dt" "ol" "ul" "td" "th" "tr"
  "h4" "h5" "h6" "pre" "sub" "sup" "var" "wbr" "nav" "kbd"
  "code" "mark" "cite" "abbr" "dfn" "main" "time" "ruby"
  "aside" "small" "table" "thead" "tbody" "tfoot"
  "strong" "figure" "footer" "header"
  "section" "article" "details" "summary" "caption"
  "blockquote" "figcaption"
  "svg" "g" "path" "circle" "rect" "line" "polyline" "polygon"
  "text" "tspan" "use" "defs" "image" "symbol" "title" "desc"
  "math" "mi" "mn" "mo" "mrow" "msup" "msub"
  "mfrac" "msqrt" "mroot" "mover" "munder" "mtable"
  "mtr" "mtd" "rp" "rt";
static const unsigned short _tag_offsets[99] = {
  0,3,7,13,18,20,22,24,25,30,35,41,47,48,51,52,53,54,55,
  56,58,60,62,64,66,68,70,72,74,76,78,80,82,84,86,89,92,
  95,98,101,104,107,111,115,119,123,126,130,134,138,143,148,
  153,158,163,168,174,180,186,192,199,206,213,220,227,237,247,
  250,251,255,261,265,269,277,284,288,293,296,300,305,311,316,
  320,324,326,328,330,334,338,342,347,352,357,362,368,374,377,
  380,382};
static const unsigned char _tag_lens[99] = {
  3,4,6,5,2,2,2,1,5,5,6,6,1,3,1,1,1,1,1,
  2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,3,3,3,
  3,3,3,3,4,4,4,4,3,4,4,4,5,5,5,
  5,5,5,6,6,6,6,7,7,7,7,7,10,10,3,
  1,4,6,4,4,8,7,4,5,3,4,5,6,5,4,
  4,2,2,2,4,4,4,5,5,5,5,6,6,3,3,
  2,2};
#define _tag_table_byte(i, j) ((int)_tag_names[_tag_offsets[i] + (j)])
#define _tag_table_len(i) ((int)_tag_lens[i])

/* Attribute name lookup table -- 32 HTML/SVG attributes (148 bytes). */
static const unsigned char _attr_names[] =
  "class" "id" "type" "for" "accept" "href" "src" "alt" "title" "width"
  "height" "lang" "dir" "role" "tabindex" "colspan" "rowspan" "xmlns"
  "d" "fill" "stroke" "cx" "cy" "r" "x" "y"
  "transform" "viewBox" "aria-label" "aria-hidden" "name" "value";
static const unsigned short _attr_offsets[32] = {
  0,5,7,11,14,20,24,27,30,35,40,46,50,53,57,65,
  72,79,84,85,89,95,97,99,100,101,102,111,118,128,139,143};
static const unsigned char _attr_lens[32] = {
  5,2,4,3,6,4,3,3,5,5,6,4,3,4,8,7,
  7,5,1,4,6,2,2,1,1,1,9,7,10,11,4,5};
#define _attr_table_byte(i, j) ((int)_attr_names[_attr_offsets[i] + (j)])
#define _attr_table_len(i) ((int)_attr_lens[i])

/* Cached safe text builders — allocate once, reuse on subsequent calls.
 * ward_safe_text is ptr to malloc'd buffer of character bytes.
 * ward_text_build = malloc, ward_text_putc = buf[i] = c, ward_text_done = nop.
 * This C loop replaces 1000+ lines of ATS2 existential-unpacking C code. */
static void* _tag_text_cache[99];
static void* _attr_text_cache[32];
static void* _build_tag_text(int idx) {
  void* p = _tag_text_cache[idx];
  if (p) return p;
  int len = _tag_lens[idx], off = _tag_offsets[idx];
  unsigned char* buf = (unsigned char*)malloc(len);
  for (int i = 0; i < len; i++) buf[i] = _tag_names[off + i];
  _tag_text_cache[idx] = buf;
  return buf;
}
static void* _build_attr_text(int idx) {
  void* p = _attr_text_cache[idx];
  if (p) return p;
  int len = _attr_lens[idx], off = _attr_offsets[idx];
  unsigned char* buf = (unsigned char*)malloc(len);
  for (int i = 0; i < len; i++) buf[i] = _attr_names[off + i];
  _attr_text_cache[idx] = buf;
  return buf;
}
%}

extern fun _tag_table_byte(idx: int, pos: int): int = "mac#"
extern fun _tag_table_len(idx: int): int = "mac#"
extern fun _attr_table_byte(idx: int, pos: int): int = "mac#"
extern fun _attr_table_len(idx: int): int = "mac#"
extern fun _build_tag_text(idx: int): ptr = "mac#"
extern fun _build_attr_text(idx: int): ptr = "mac#"

(* Safe cast: C helpers build valid ward_safe_text buffers (malloc + byte copy).
 * All table bytes satisfy SAFE_CHAR (a-z, A-Z, 0-9, -). *)
extern castfn _ptr_as_safe_text {n:pos} (p: ptr): ward_safe_text(n)

implement lookup_tag{lb}{n}(tree, tlen, offset, name_len) = let
  fun cmp(tree: !ward_arr(byte, lb, n), tlen: int n,
          off: int, idx: int, nlen: int, j: int): bool =
    if j >= nlen then true
    else if ward_arr_byte(tree, off + j, tlen) = _tag_table_byte(idx, j)
    then cmp(tree, tlen, off, idx, nlen, j + 1)
    else false
  fun loop(tree: !ward_arr(byte, lb, n), tlen: int n,
           off: int, nlen: int, i: int): int =
    if i >= 99 then 0 - 1
    else if _tag_table_len(i) = nlen then
      if cmp(tree, tlen, off, i, nlen, 0) then i
      else loop(tree, tlen, off, nlen, i + 1)
    else loop(tree, tlen, off, nlen, i + 1)
in loop(tree, tlen, offset, name_len, 0) end

implement lookup_attr{lb}{n}(tree, tlen, offset, name_len) = let
  fun cmp(tree: !ward_arr(byte, lb, n), tlen: int n,
          off: int, idx: int, nlen: int, j: int): bool =
    if j >= nlen then true
    else if ward_arr_byte(tree, off + j, tlen) = _attr_table_byte(idx, j)
    then cmp(tree, tlen, off, idx, nlen, j + 1)
    else false
  fun loop(tree: !ward_arr(byte, lb, n), tlen: int n,
           off: int, nlen: int, i: int): int =
    if i >= 32 then 0 - 1
    else if _attr_table_len(i) = nlen then
      if cmp(tree, tlen, off, i, nlen, 0) then i
      else loop(tree, tlen, off, nlen, i + 1)
    else loop(tree, tlen, off, nlen, i + 1)
in loop(tree, tlen, offset, name_len, 0) end


(* ========== Lookup dispatch via index ========== *)

(* C helpers _build_tag_text/_build_attr_text (in %{^ above) allocate+fill the
 * safe text buffer from static data tables with caching. The ATS2 side only
 * dispatches on length to satisfy the existential [n:pos | n <= 10/11].
 * Justification for castfn: C builds identical buffers to ward_text_build/putc/done
 * (malloc + byte copy), all bytes satisfy SAFE_CHAR. *)

implement get_tag_by_index(idx) = let
  val p = _build_tag_text(idx)
  val len = _tag_table_len(idx)
in
  if len = 1 then @(_ptr_as_safe_text{1}(p), 1)
  else if len = 2 then @(_ptr_as_safe_text{2}(p), 2)
  else if len = 3 then @(_ptr_as_safe_text{3}(p), 3)
  else if len = 4 then @(_ptr_as_safe_text{4}(p), 4)
  else if len = 5 then @(_ptr_as_safe_text{5}(p), 5)
  else if len = 6 then @(_ptr_as_safe_text{6}(p), 6)
  else if len = 7 then @(_ptr_as_safe_text{7}(p), 7)
  else if len = 8 then @(_ptr_as_safe_text{8}(p), 8)
  else (* 10 *) @(_ptr_as_safe_text{10}(p), 10)
end

implement get_attr_by_index(idx) = let
  val p = _build_attr_text(idx)
  val len = _attr_table_len(idx)
in
  if len = 1 then @(_ptr_as_safe_text{1}(p), 1)
  else if len = 2 then @(_ptr_as_safe_text{2}(p), 2)
  else if len = 3 then @(_ptr_as_safe_text{3}(p), 3)
  else if len = 4 then @(_ptr_as_safe_text{4}(p), 4)
  else if len = 5 then @(_ptr_as_safe_text{5}(p), 5)
  else if len = 6 then @(_ptr_as_safe_text{6}(p), 6)
  else if len = 7 then @(_ptr_as_safe_text{7}(p), 7)
  else if len = 8 then @(_ptr_as_safe_text{8}(p), 8)
  else if len = 9 then @(_ptr_as_safe_text{9}(p), 9)
  else if len = 10 then @(_ptr_as_safe_text{10}(p), 10)
  else (* 11 *) @(_ptr_as_safe_text{11}(p), 11)
end


(* ========== Tree renderer ========== *)

(* Binary format from wardJsParseHtml:
 * ELEMENT_OPEN (0x01):  tag_len:u8  tag:bytes  attr_count:u8
 *   [attr_name_len:u8  attr_name:bytes  attr_value_len:u16LE  attr_value:bytes]...
 * TEXT (0x03):  text_len:u16LE  text:bytes
 * ELEMENT_CLOSE (0x02):  (no payload)
 *)

(* Ward DOM buffer cap — text needs tl + 7 <= 262144, attr needs nl + vl + 8 <= 262144.
 * Max attr name is 11 chars, so vl + 19 <= 262144. Auto-flush handles large payloads. *)

(* Check if text content in SAX buffer is whitespace-only.
 * Whitespace: space(32), newline(10), tab(9), carriage-return(13).
 * TEXT_RENDER_SAFE: whitespace-only TEXT nodes are always skipped as an
 * optimization — they represent source indentation, not content.
 * Non-whitespace TEXT on a parent with existing children (has_child > 0)
 * is wrapped in <span> rather than calling set_text on parent. *)
fn is_whitespace_only {lb:agz}{n:pos}
  (tree: !ward_arr(byte, lb, n), start: int, text_len: int, tlen: int n): bool = let
  fun check(tree: !ward_arr(byte, lb, n), pos: int, endp: int, tlen: int n): bool =
    if pos >= endp then true
    else let
      val b = ward_arr_byte(tree, pos, tlen)
    in
      if b = 32 then check(tree, pos + 1, endp, tlen)        (* space *)
      else if b = 10 then check(tree, pos + 1, endp, tlen)   (* newline *)
      else if b = 9 then check(tree, pos + 1, endp, tlen)    (* tab *)
      else if b = 13 then check(tree, pos + 1, endp, tlen)   (* CR *)
      else false
    end
in check(tree, start, start + text_len, tlen) end

implement render_tree{l}{lb}{n}(stream, parent_id, tree, tree_len) = let

  fun loop {l:agz}{lb:agz}{n:pos}
    (st: ward_dom_stream(l), tree: !ward_arr(byte, lb, n),
     pos: int, len: int, parent: int, tlen: int n,
     has_child: int, ecnt: int)
    : @(ward_dom_stream(l), int, int) =
    if pos >= len then @(st, pos, ecnt)
    else if ecnt >= MAX_RENDER_ELEMENTS then @(st, len, ecnt)
    else let
      val opc = ward_arr_byte(tree, pos, tlen)
    in
      if opc = 1 then let (* ELEMENT_OPEN *)
        val tag_len = ward_arr_byte(tree, pos + 1, tlen)
        val tag_idx = lookup_tag(tree, tlen, pos + 2, tag_len)
        val attr_off = pos + 2 + tag_len
        val attr_count = ward_arr_byte(tree, attr_off, tlen)
        val after_attrs = skip_attrs(tree, attr_off + 1, attr_count, tlen)
      in
        if tag_idx >= 0 then
          (* Skip <img> elements: image sources are paths inside the EPUB ZIP
           * that can't be resolved, so they show as broken.
           * TAG_IDX_IMG defined in dom.sats — single source of truth. *)
          if tag_idx = TAG_IDX_IMG then let
            val end_pos = skip_element(tree, after_attrs, len, tlen)
          in
            loop(st, tree, end_pos, len, parent, tlen, has_child, ecnt)
          end
          else let
          val @(tag_st, tag_st_len) = get_tag_by_index(tag_idx)
          val nid = dom_next_id()
          val st = ward_dom_stream_create_element(st, nid, parent, tag_st, tag_st_len)
          val st = emit_attrs(st, nid, tree, attr_off + 1, attr_count, tlen)
          val @(st, child_end, ec2) = loop(st, tree, after_attrs, len, nid, tlen, 0, ecnt + 1)
        in
          (* SIBLING_CONTINUATION: after closing this element, continue
           * processing remaining siblings under the same parent.
           * has_child=1: we just created an element child under parent. *)
          if child_end < len then let
            val close_opc = ward_arr_byte(tree, child_end, tlen)
          in
            if close_opc = 2 then
              loop(st, tree, child_end + 1, len, parent, tlen, 1, ec2)
            else
              loop(st, tree, child_end, len, parent, tlen, 1, ec2)
          end
          else @(st, child_end, ec2)
        end
        else let
          val end_pos = skip_element(tree, after_attrs, len, tlen)
        in
          loop(st, tree, end_pos, len, parent, tlen, has_child, ecnt)
        end
      end
      else if opc = 3 then let (* TEXT *)
        val text_len = rd_u16(tree, pos + 1, tlen)
        val text_start = pos + 3
        val tl = g1ofg0(text_len)
      in
        if tl > 0 then
          if is_whitespace_only(tree, text_start, text_len, tlen) then
            loop(st, tree, text_start + text_len, len, parent, tlen, has_child, ecnt)
          else if tl < 65536 then
            if has_child > 0 then let
              (* TEXT_RENDER_SAFE: parent has existing children.
               * Wrap text in <span> to prevent set_text from destroying them. *)
              val span_id = dom_next_id()
              val st = ward_dom_stream_create_element(
                st, span_id, parent, tag_span(), 4)
              val text_arr = ward_arr_alloc<byte>(tl)
              val () = copy_arr_bytes(text_arr, tl, tree, tlen, text_start, text_len)
              val @(frozen, borrow) = ward_arr_freeze<byte>(text_arr)
              val st = ward_dom_stream_set_text(st, span_id, borrow, tl)
              val () = ward_arr_drop<byte>(frozen, borrow)
              val text_arr = ward_arr_thaw<byte>(frozen)
              val () = ward_arr_free<byte>(text_arr)
            in
              loop(st, tree, text_start + text_len, len, parent, tlen, 1, ecnt + 1)
            end
            else let
              (* TEXT_RENDER_SAFE: no children yet — set_text on parent is safe *)
              val text_arr = ward_arr_alloc<byte>(tl)
              val () = copy_arr_bytes(text_arr, tl, tree, tlen, text_start, text_len)
              val @(frozen, borrow) = ward_arr_freeze<byte>(text_arr)
              val st = ward_dom_stream_set_text(st, parent, borrow, tl)
              val () = ward_arr_drop<byte>(frozen, borrow)
              val text_arr = ward_arr_thaw<byte>(frozen)
              val () = ward_arr_free<byte>(text_arr)
            in
              loop(st, tree, text_start + text_len, len, parent, tlen, 1, ecnt)
            end
          else (* text too large for DOM buffer — skip *)
            loop(st, tree, text_start + text_len, len, parent, tlen, has_child, ecnt)
        else loop(st, tree, text_start + text_len, len, parent, tlen, has_child, ecnt)
      end
      else if opc = 2 then (* ELEMENT_CLOSE — return to parent *)
        @(st, pos, ecnt)
      else (* Unknown opcode — skip byte *)
        loop(st, tree, pos + 1, len, parent, tlen, has_child, ecnt)
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
      val attr_idx = lookup_attr(tree, tlen, pos + 1, name_len)
      val val_off = pos + 1 + name_len
      val val_len = rd_u16(tree, val_off, tlen)
      val val_start = val_off + 2
    in
      if attr_idx >= 0 then let
        val @(attr_st, attr_st_len) = get_attr_by_index(attr_idx)
        val vl = g1ofg0(val_len)
      in
        if vl > 0 then
          if vl < 65536 then
          if attr_st_len + vl + 8 <= 262144 then let
            val val_arr = ward_arr_alloc<byte>(vl)
            val () = copy_arr_bytes(val_arr, vl, tree, tlen, val_start, val_len)
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
          else (* attr value >= 65536 — skip *)
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

  val @(st, _, ecnt) = loop(stream, tree, 0, tree_len, parent_id, tree_len, 0, 0)
  val () = _dom_set_render_ecnt(ecnt)
in
  st
end

(* ========== Image-aware tree renderer ========== *)

(* Build a ward_safe_content_text for a MIME type string.
 * All MIME chars (a-z, /, +) are SAFE_CONTENT_CHAR.
 * Returns the content text and its length. *)
fn build_mime_jpeg()
  : [l:agz] @(ward_safe_content_text(l, 10), int 10) = let
  (* "image/jpeg" = 10 chars *)
  val b = ward_content_text_build(10)
  val b = ward_content_text_putc(b, 0, char2int1('i'))
  val b = ward_content_text_putc(b, 1, char2int1('m'))
  val b = ward_content_text_putc(b, 2, char2int1('a'))
  val b = ward_content_text_putc(b, 3, char2int1('g'))
  val b = ward_content_text_putc(b, 4, char2int1('e'))
  val b = ward_content_text_putc(b, 5, 47) (* '/' *)
  val b = ward_content_text_putc(b, 6, char2int1('j'))
  val b = ward_content_text_putc(b, 7, char2int1('p'))
  val b = ward_content_text_putc(b, 8, char2int1('e'))
  val b = ward_content_text_putc(b, 9, char2int1('g'))
in @(ward_content_text_done(b), 10) end

fn build_mime_png()
  : [l:agz] @(ward_safe_content_text(l, 9), int 9) = let
  (* "image/png" = 9 chars *)
  val b = ward_content_text_build(9)
  val b = ward_content_text_putc(b, 0, char2int1('i'))
  val b = ward_content_text_putc(b, 1, char2int1('m'))
  val b = ward_content_text_putc(b, 2, char2int1('a'))
  val b = ward_content_text_putc(b, 3, char2int1('g'))
  val b = ward_content_text_putc(b, 4, char2int1('e'))
  val b = ward_content_text_putc(b, 5, 47) (* '/' *)
  val b = ward_content_text_putc(b, 6, char2int1('p'))
  val b = ward_content_text_putc(b, 7, char2int1('n'))
  val b = ward_content_text_putc(b, 8, char2int1('g'))
in @(ward_content_text_done(b), 9) end

fn build_mime_gif()
  : [l:agz] @(ward_safe_content_text(l, 9), int 9) = let
  (* "image/gif" = 9 chars *)
  val b = ward_content_text_build(9)
  val b = ward_content_text_putc(b, 0, char2int1('i'))
  val b = ward_content_text_putc(b, 1, char2int1('m'))
  val b = ward_content_text_putc(b, 2, char2int1('a'))
  val b = ward_content_text_putc(b, 3, char2int1('g'))
  val b = ward_content_text_putc(b, 4, char2int1('e'))
  val b = ward_content_text_putc(b, 5, 47) (* '/' *)
  val b = ward_content_text_putc(b, 6, char2int1('g'))
  val b = ward_content_text_putc(b, 7, char2int1('i'))
  val b = ward_content_text_putc(b, 8, char2int1('f'))
in @(ward_content_text_done(b), 9) end

fn build_mime_svg()
  : [l:agz] @(ward_safe_content_text(l, 13), int 13) = let
  (* "image/svg+xml" = 13 chars *)
  val b = ward_content_text_build(13)
  val b = ward_content_text_putc(b, 0, char2int1('i'))
  val b = ward_content_text_putc(b, 1, char2int1('m'))
  val b = ward_content_text_putc(b, 2, char2int1('a'))
  val b = ward_content_text_putc(b, 3, char2int1('g'))
  val b = ward_content_text_putc(b, 4, char2int1('e'))
  val b = ward_content_text_putc(b, 5, 47) (* '/' *)
  val b = ward_content_text_putc(b, 6, char2int1('s'))
  val b = ward_content_text_putc(b, 7, char2int1('v'))
  val b = ward_content_text_putc(b, 8, char2int1('g'))
  val b = ward_content_text_putc(b, 9, 43) (* '+' *)
  val b = ward_content_text_putc(b, 10, char2int1('x'))
  val b = ward_content_text_putc(b, 11, char2int1('m'))
  val b = ward_content_text_putc(b, 12, char2int1('l'))
in @(ward_content_text_done(b), 13) end

(* Resolve image src path relative to chapter directory.
 * Writes resolved path to the string buffer (via _app_sbuf_set_u8).
 * Handles "../" by stripping one directory level from chapter_dir.
 * Returns the resolved path length in the sbuf. *)
fn resolve_img_src {lb:agz}{n:pos}{ld:agz}{nd:pos}
  (tree: !ward_arr(byte, lb, n), tlen: int n,
   src_off: int, src_len: int,
   chapter_dir: !ward_arr(byte, ld, nd), dir_len: int nd): int = let
  (* Check for "../" prefix *)
  val has_dotdot =
    if gte_int_int(src_len, 3) then
      if ward_arr_byte(tree, src_off, tlen) = 46 then     (* '.' *)
        if ward_arr_byte(tree, src_off + 1, tlen) = 46 then (* '.' *)
          if ward_arr_byte(tree, src_off + 2, tlen) = 47 then (* '/' *)
            1
          else 0
        else 0
      else 0
    else 0

  val dl = g0ofg1(dir_len)
in
  if gt_int_int(has_dotdot, 0) then let
    (* Strip one directory level from chapter_dir.
     * e.g., "OEBPS/Text/" + "../Images/cover.jpg" → "OEBPS/Images/cover.jpg"
     * Find second-to-last '/' in chapter_dir (which ends with '/') *)
    fun find_parent_slash {ld:agz}{nd:pos}
      (d: !ward_arr(byte, ld, nd), dlen: int nd, pos: int): int =
      if pos < 0 then 0
      else if ward_arr_byte(d, pos, dlen) = 47 (* '/' *)
      then pos + 1
      else find_parent_slash(d, dlen, pos - 1)
    val parent_len = find_parent_slash(chapter_dir, dir_len, dl - 2)
    (* Copy parent dir to sbuf *)
    fun copy_dir {ld:agz}{nd:pos}
      (d: !ward_arr(byte, ld, nd), dlen: int nd, i: int, count: int): void =
      if i < count then let
        val b = ward_arr_byte(d, i, dlen)
        val _ = _app_sbuf_set_u8(i, b)
      in copy_dir(d, dlen, i + 1, count) end
    val () = copy_dir(chapter_dir, dir_len, 0, parent_len)
    (* Copy src after "../" to sbuf[parent_len..] *)
    val skip = 3 (* skip "../" *)
    val remain = src_len - skip
    fun copy_src {lb:agz}{n:pos}
      (tree: !ward_arr(byte, lb, n), tlen: int n,
       src_start: int, i: int, count: int, dst: int): void =
      if i < count then let
        val b = ward_arr_byte(tree, src_start + i, tlen)
        val _ = _app_sbuf_set_u8(dst + i, b)
      in copy_src(tree, tlen, src_start, i + 1, count, dst) end
    val () = copy_src(tree, tlen, src_off + skip, 0, remain, parent_len)
  in parent_len + remain end
  else let
    (* No "../" — prepend chapter_dir *)
    fun copy_dir2 {ld:agz}{nd:pos}
      (d: !ward_arr(byte, ld, nd), dlen: int nd, i: int, count: int): void =
      if i < count then let
        val b = ward_arr_byte(d, i, dlen)
        val _ = _app_sbuf_set_u8(i, b)
      in copy_dir2(d, dlen, i + 1, count) end
    val () = copy_dir2(chapter_dir, dir_len, 0, dl)
    fun copy_src2 {lb:agz}{n:pos}
      (tree: !ward_arr(byte, lb, n), tlen: int n,
       src_start: int, i: int, count: int, dst: int): void =
      if i < count then let
        val b = ward_arr_byte(tree, src_start + i, tlen)
        val _ = _app_sbuf_set_u8(dst + i, b)
      in copy_src2(tree, tlen, src_start, i + 1, count, dst) end
    val () = copy_src2(tree, tlen, src_off, 0, src_len, dl)
  in dl + src_len end
end

(* Try to load an image from the ZIP and set it on a DOM node.
 * Resolves path, finds ZIP entry, reads stored data,
 * detects MIME, calls ward_dom_stream_set_image_src.
 * Returns the stream (possibly unchanged if image not loadable). *)
fn try_set_image {l:agz}{lb:agz}{n:pos}{ld:agz}{nd:pos}
  (st: ward_dom_stream(l), nid: int,
   tree: !ward_arr(byte, lb, n), tlen: int n,
   src_off: int, src_len: int,
   file_handle: int,
   chapter_dir: !ward_arr(byte, ld, nd), dir_len: int nd)
  : ward_dom_stream(l) = let
  (* DIAGNOSTIC 12: try_set_image is a complete no-op.
   * malloc(4097) is called in quire.dats AFTER rendering completes.
   * If crash → something about the WASM call chain triggers it.
   * If no crash → the render loop itself is the trigger. *)
in
  st
end

implement render_tree_with_images
  {l}{lb}{n}{ld}{nd}
  (stream, parent_id, tree, tree_len,
   file_handle, chapter_dir, chapter_dir_len) = let

  fun loop {l:agz}{lb:agz}{n:pos}{ld:agz}{nd:pos}
    (st: ward_dom_stream(l), tree: !ward_arr(byte, lb, n),
     pos: int, len: int, parent: int, tlen: int n,
     has_child: int, ecnt: int,
     fh: int, cdir: !ward_arr(byte, ld, nd), cdlen: int nd)
    : @(ward_dom_stream(l), int, int) =
    if pos >= len then @(st, pos, ecnt)
    else if ecnt >= MAX_RENDER_ELEMENTS then @(st, len, ecnt)
    else let
      val opc = ward_arr_byte(tree, pos, tlen)
    in
      if opc = 1 then let (* ELEMENT_OPEN *)
        val tag_len = ward_arr_byte(tree, pos + 1, tlen)
        val tag_idx = lookup_tag(tree, tlen, pos + 2, tag_len)
        val attr_off = pos + 2 + tag_len
        val attr_count = ward_arr_byte(tree, attr_off, tlen)
        val after_attrs = skip_attrs_img(tree, attr_off + 1, attr_count, tlen)
      in
        if tag_idx >= 0 then
          if tag_idx = TAG_IDX_IMG then let
            (* Create <img> element and handle src attribute *)
            val @(tag_st, tag_st_len) = get_tag_by_index(tag_idx)
            val nid = dom_next_id()
            val st = ward_dom_stream_create_element(st, nid, parent, tag_st, tag_st_len)
            (* Emit non-src attributes and collect src info *)
            val @(st, src_off, src_len) = emit_attrs_img(
              st, nid, tree, attr_off + 1, attr_count, tlen, 0, 0)
          in
            if gt_int_int(src_len, 0) then let
              val st = try_set_image(st, nid, tree, tlen,
                src_off, src_len, fh, cdir, cdlen)
              (* <img> is void — skip to ELEMENT_CLOSE *)
              val end_pos = skip_element_img(tree, after_attrs, len, tlen)
            in
              if end_pos < len then let
                val close_opc = ward_arr_byte(tree, end_pos, tlen)
              in
                if close_opc = 2 then
                  loop(st, tree, end_pos + 1, len, parent, tlen, 1, ecnt + 1, fh, cdir, cdlen)
                else
                  loop(st, tree, end_pos, len, parent, tlen, 1, ecnt + 1, fh, cdir, cdlen)
              end
              else @(st, end_pos, ecnt + 1)
            end
            else let
              (* No src found — element exists without image *)
              val end_pos = skip_element_img(tree, after_attrs, len, tlen)
            in
              if end_pos < len then let
                val close_opc = ward_arr_byte(tree, end_pos, tlen)
              in
                if close_opc = 2 then
                  loop(st, tree, end_pos + 1, len, parent, tlen, 1, ecnt + 1, fh, cdir, cdlen)
                else
                  loop(st, tree, end_pos, len, parent, tlen, 1, ecnt + 1, fh, cdir, cdlen)
              end
              else @(st, end_pos, ecnt + 1)
            end
          end
          else let
          val @(tag_st, tag_st_len) = get_tag_by_index(tag_idx)
          val nid = dom_next_id()
          val st = ward_dom_stream_create_element(st, nid, parent, tag_st, tag_st_len)
          val st = emit_attrs_noimg(st, nid, tree, attr_off + 1, attr_count, tlen)
          val @(st, child_end, ec2) = loop(st, tree, after_attrs, len, nid, tlen, 0, ecnt + 1, fh, cdir, cdlen)
        in
          (* SIBLING_CONTINUATION *)
          if child_end < len then let
            val close_opc = ward_arr_byte(tree, child_end, tlen)
          in
            if close_opc = 2 then
              loop(st, tree, child_end + 1, len, parent, tlen, 1, ec2, fh, cdir, cdlen)
            else
              loop(st, tree, child_end, len, parent, tlen, 1, ec2, fh, cdir, cdlen)
          end
          else @(st, child_end, ec2)
        end
        else let
          val end_pos = skip_element_img(tree, after_attrs, len, tlen)
        in
          loop(st, tree, end_pos, len, parent, tlen, has_child, ecnt, fh, cdir, cdlen)
        end
      end
      else if opc = 3 then let (* TEXT *)
        val text_len = rd_u16(tree, pos + 1, tlen)
        val text_start = pos + 3
        val tl = g1ofg0(text_len)
      in
        if tl > 0 then
          if is_whitespace_only(tree, text_start, text_len, tlen) then
            loop(st, tree, text_start + text_len, len, parent, tlen, has_child, ecnt, fh, cdir, cdlen)
          else if tl < 65536 then
            if has_child > 0 then let
              val span_id = dom_next_id()
              val st = ward_dom_stream_create_element(
                st, span_id, parent, tag_span(), 4)
              val text_arr = ward_arr_alloc<byte>(tl)
              val () = copy_arr_bytes(text_arr, tl, tree, tlen, text_start, text_len)
              val @(frozen, borrow) = ward_arr_freeze<byte>(text_arr)
              val st = ward_dom_stream_set_text(st, span_id, borrow, tl)
              val () = ward_arr_drop<byte>(frozen, borrow)
              val text_arr = ward_arr_thaw<byte>(frozen)
              val () = ward_arr_free<byte>(text_arr)
            in
              loop(st, tree, text_start + text_len, len, parent, tlen, 1, ecnt + 1, fh, cdir, cdlen)
            end
            else let
              val text_arr = ward_arr_alloc<byte>(tl)
              val () = copy_arr_bytes(text_arr, tl, tree, tlen, text_start, text_len)
              val @(frozen, borrow) = ward_arr_freeze<byte>(text_arr)
              val st = ward_dom_stream_set_text(st, parent, borrow, tl)
              val () = ward_arr_drop<byte>(frozen, borrow)
              val text_arr = ward_arr_thaw<byte>(frozen)
              val () = ward_arr_free<byte>(text_arr)
            in
              loop(st, tree, text_start + text_len, len, parent, tlen, 1, ecnt, fh, cdir, cdlen)
            end
          else
            loop(st, tree, text_start + text_len, len, parent, tlen, has_child, ecnt, fh, cdir, cdlen)
        else loop(st, tree, text_start + text_len, len, parent, tlen, has_child, ecnt, fh, cdir, cdlen)
      end
      else if opc = 2 then (* ELEMENT_CLOSE *)
        @(st, pos, ecnt)
      else
        loop(st, tree, pos + 1, len, parent, tlen, has_child, ecnt, fh, cdir, cdlen)
    end
  and skip_attrs_img {lb:agz}{n:pos}
    (tree: !ward_arr(byte, lb, n), pos: int, count: int, tlen: int n): int =
    if count <= 0 then pos
    else let
      val name_len = ward_arr_byte(tree, pos, tlen)
      val val_len = rd_u16(tree, pos + 1 + name_len, tlen)
    in
      skip_attrs_img(tree, pos + 1 + name_len + 2 + val_len, count - 1, tlen)
    end
  and emit_attrs_noimg {l:agz}{lb:agz}{n:pos}
    (st: ward_dom_stream(l), nid: int, tree: !ward_arr(byte, lb, n),
     pos: int, count: int, tlen: int n)
    : ward_dom_stream(l) =
    if count <= 0 then st
    else let
      val name_len = ward_arr_byte(tree, pos, tlen)
      val attr_idx = lookup_attr(tree, tlen, pos + 1, name_len)
      val val_off = pos + 1 + name_len
      val val_len = rd_u16(tree, val_off, tlen)
      val val_start = val_off + 2
    in
      if attr_idx >= 0 then let
        val @(attr_st, attr_st_len) = get_attr_by_index(attr_idx)
        val vl = g1ofg0(val_len)
      in
        if vl > 0 then
          if vl < 65536 then
          if attr_st_len + vl + 8 <= 262144 then let
            val val_arr = ward_arr_alloc<byte>(vl)
            val () = copy_arr_bytes(val_arr, vl, tree, tlen, val_start, val_len)
            val @(frozen, borrow) = ward_arr_freeze<byte>(val_arr)
            val st = ward_dom_stream_set_attr(st, nid, attr_st, attr_st_len, borrow, vl)
            val () = ward_arr_drop<byte>(frozen, borrow)
            val val_arr = ward_arr_thaw<byte>(frozen)
            val () = ward_arr_free<byte>(val_arr)
          in
            emit_attrs_noimg(st, nid, tree, val_start + val_len, count - 1, tlen)
          end
          else emit_attrs_noimg(st, nid, tree, val_start + val_len, count - 1, tlen)
          else emit_attrs_noimg(st, nid, tree, val_start + val_len, count - 1, tlen)
        else emit_attrs_noimg(st, nid, tree, val_start, count - 1, tlen)
      end
      else emit_attrs_noimg(st, nid, tree, val_start + val_len, count - 1, tlen)
    end
  and emit_attrs_img {l:agz}{lb:agz}{n:pos}
    (st: ward_dom_stream(l), nid: int, tree: !ward_arr(byte, lb, n),
     pos: int, count: int, tlen: int n,
     found_src_off: int, found_src_len: int)
    : @(ward_dom_stream(l), int, int) =
    if count <= 0 then @(st, found_src_off, found_src_len)
    else let
      val name_len = ward_arr_byte(tree, pos, tlen)
      val attr_idx = lookup_attr(tree, tlen, pos + 1, name_len)
      val val_off = pos + 1 + name_len
      val val_len = rd_u16(tree, val_off, tlen)
      val val_start = val_off + 2
    in
      if attr_idx = ATTR_IDX_SRC then
        (* Save src offset/len but don't emit as normal attribute *)
        emit_attrs_img(st, nid, tree, val_start + val_len, count - 1, tlen,
          val_start, val_len)
      else if attr_idx >= 0 then let
        val @(attr_st, attr_st_len) = get_attr_by_index(attr_idx)
        val vl = g1ofg0(val_len)
      in
        if vl > 0 then
          if vl < 65536 then
          if attr_st_len + vl + 8 <= 262144 then let
            val val_arr = ward_arr_alloc<byte>(vl)
            val () = copy_arr_bytes(val_arr, vl, tree, tlen, val_start, val_len)
            val @(frozen, borrow) = ward_arr_freeze<byte>(val_arr)
            val st = ward_dom_stream_set_attr(st, nid, attr_st, attr_st_len, borrow, vl)
            val () = ward_arr_drop<byte>(frozen, borrow)
            val val_arr = ward_arr_thaw<byte>(frozen)
            val () = ward_arr_free<byte>(val_arr)
          in
            emit_attrs_img(st, nid, tree, val_start + val_len, count - 1, tlen,
              found_src_off, found_src_len)
          end
          else emit_attrs_img(st, nid, tree, val_start + val_len, count - 1, tlen,
            found_src_off, found_src_len)
          else emit_attrs_img(st, nid, tree, val_start + val_len, count - 1, tlen,
            found_src_off, found_src_len)
        else emit_attrs_img(st, nid, tree, val_start, count - 1, tlen,
          found_src_off, found_src_len)
      end
      else emit_attrs_img(st, nid, tree, val_start + val_len, count - 1, tlen,
        found_src_off, found_src_len)
    end
  and skip_element_img {lb:agz}{n:pos}
    (tree: !ward_arr(byte, lb, n), pos: int, len: int, tlen: int n): int =
    if pos >= len then pos
    else let
      val opc = ward_arr_byte(tree, pos, tlen)
    in
      if opc = 2 then pos + 1
      else if opc = 1 then let
        val tag_len = ward_arr_byte(tree, pos + 1, tlen)
        val attr_off = pos + 2 + tag_len
        val attr_count = ward_arr_byte(tree, attr_off, tlen)
        val after_attrs = skip_attrs_img(tree, attr_off + 1, attr_count, tlen)
        val end_inner = skip_element_img(tree, after_attrs, len, tlen)
      in
        skip_element_img(tree, end_inner, len, tlen)
      end
      else if opc = 3 then let
        val text_len = rd_u16(tree, pos + 1, tlen)
      in
        skip_element_img(tree, pos + 3 + text_len, len, tlen)
      end
      else skip_element_img(tree, pos + 1, len, tlen)
    end

  val @(st, _, ecnt) = loop(stream, tree, 0, tree_len, parent_id, tree_len, 0, 0,
    file_handle, chapter_dir, chapter_dir_len)
  val () = _dom_set_render_ecnt(ecnt)
in
  st
end
