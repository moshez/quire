(* book_info.dats — Book info overlay implementation *)

#define ATS_DYNLOADFLAG 0

#include "share/atspre_staload.hats"
staload "./quire.sats"
staload "./quire_ui.sats"
staload "./book_info.sats"
staload "./quire_text.sats"
staload "./ui_classes.sats"
staload "./app_state.sats"
staload "./dom.sats"
staload "./arith.sats"
staload "./library.sats"
staload "./epub.sats"
staload "./reader.sats"
staload "./sha256.sats"
staload "./quire_ext.sats"
staload "./buf.sats"
staload "./../vendor/ward/lib/memory.sats"
staload "./../vendor/ward/lib/dom.sats"
staload "./../vendor/ward/lib/listener.sats"
staload "./../vendor/ward/lib/event.sats"
staload "./../vendor/ward/lib/idb.sats"
staload _ = "./../vendor/ward/lib/memory.dats"
staload _ = "./../vendor/ward/lib/dom.dats"
staload _ = "./../vendor/ward/lib/listener.dats"
staload _ = "./../vendor/ward/lib/event.dats"
staload _ = "./../vendor/ward/lib/idb.dats"

(* Proof construction after runtime validation via check_book_index.
 * The caller MUST verify check_book_index(idx, count) == 1 before calling.
 * Dataprop erased at runtime -- cast is identity on int. *)
extern castfn _mk_book_access(x: int): [i:nat | i < 32] (BOOK_ACCESS_SAFE(i) | int(i))

(* Clamp spine count to [0, 256] for epub_delete_book_data.
 * Caller MUST verify value <= 256 before calling. *)
extern castfn _checked_spine_count(x: int): [n:nat | n <= 256] int n

(* ========== Book info CSS class builders ========== *)

implement cls_info_overlay(): ward_safe_text(12) = let
  val b = ward_text_build(12)
  val b = ward_text_putc(b, 0, char2int1('i'))
  val b = ward_text_putc(b, 1, char2int1('n'))
  val b = ward_text_putc(b, 2, char2int1('f'))
  val b = ward_text_putc(b, 3, char2int1('o'))
  val b = ward_text_putc(b, 4, 45) (* '-' *)
  val b = ward_text_putc(b, 5, char2int1('o'))
  val b = ward_text_putc(b, 6, char2int1('v'))
  val b = ward_text_putc(b, 7, char2int1('e'))
  val b = ward_text_putc(b, 8, char2int1('r'))
  val b = ward_text_putc(b, 9, char2int1('l'))
  val b = ward_text_putc(b, 10, char2int1('a'))
  val b = ward_text_putc(b, 11, char2int1('y'))
in ward_text_done(b) end

implement cls_info_header(): ward_safe_text(11) = let
  val b = ward_text_build(11)
  val b = ward_text_putc(b, 0, char2int1('i'))
  val b = ward_text_putc(b, 1, char2int1('n'))
  val b = ward_text_putc(b, 2, char2int1('f'))
  val b = ward_text_putc(b, 3, char2int1('o'))
  val b = ward_text_putc(b, 4, 45) (* '-' *)
  val b = ward_text_putc(b, 5, char2int1('h'))
  val b = ward_text_putc(b, 6, char2int1('e'))
  val b = ward_text_putc(b, 7, char2int1('a'))
  val b = ward_text_putc(b, 8, char2int1('d'))
  val b = ward_text_putc(b, 9, char2int1('e'))
  val b = ward_text_putc(b, 10, char2int1('r'))
in ward_text_done(b) end

implement cls_info_back(): ward_safe_text(9) = let
  val b = ward_text_build(9)
  val b = ward_text_putc(b, 0, char2int1('i'))
  val b = ward_text_putc(b, 1, char2int1('n'))
  val b = ward_text_putc(b, 2, char2int1('f'))
  val b = ward_text_putc(b, 3, char2int1('o'))
  val b = ward_text_putc(b, 4, 45) (* '-' *)
  val b = ward_text_putc(b, 5, char2int1('b'))
  val b = ward_text_putc(b, 6, char2int1('a'))
  val b = ward_text_putc(b, 7, char2int1('c'))
  val b = ward_text_putc(b, 8, char2int1('k'))
in ward_text_done(b) end

implement cls_info_cover(): ward_safe_text(10) = let
  val b = ward_text_build(10)
  val b = ward_text_putc(b, 0, char2int1('i'))
  val b = ward_text_putc(b, 1, char2int1('n'))
  val b = ward_text_putc(b, 2, char2int1('f'))
  val b = ward_text_putc(b, 3, char2int1('o'))
  val b = ward_text_putc(b, 4, 45) (* '-' *)
  val b = ward_text_putc(b, 5, char2int1('c'))
  val b = ward_text_putc(b, 6, char2int1('o'))
  val b = ward_text_putc(b, 7, char2int1('v'))
  val b = ward_text_putc(b, 8, char2int1('e'))
  val b = ward_text_putc(b, 9, char2int1('r'))
in ward_text_done(b) end

implement cls_info_title(): ward_safe_text(10) = let
  val b = ward_text_build(10)
  val b = ward_text_putc(b, 0, char2int1('i'))
  val b = ward_text_putc(b, 1, char2int1('n'))
  val b = ward_text_putc(b, 2, char2int1('f'))
  val b = ward_text_putc(b, 3, char2int1('o'))
  val b = ward_text_putc(b, 4, 45) (* '-' *)
  val b = ward_text_putc(b, 5, char2int1('t'))
  val b = ward_text_putc(b, 6, char2int1('i'))
  val b = ward_text_putc(b, 7, char2int1('t'))
  val b = ward_text_putc(b, 8, char2int1('l'))
  val b = ward_text_putc(b, 9, char2int1('e'))
in ward_text_done(b) end

implement cls_info_author(): ward_safe_text(11) = let
  val b = ward_text_build(11)
  val b = ward_text_putc(b, 0, char2int1('i'))
  val b = ward_text_putc(b, 1, char2int1('n'))
  val b = ward_text_putc(b, 2, char2int1('f'))
  val b = ward_text_putc(b, 3, char2int1('o'))
  val b = ward_text_putc(b, 4, 45) (* '-' *)
  val b = ward_text_putc(b, 5, char2int1('a'))
  val b = ward_text_putc(b, 6, char2int1('u'))
  val b = ward_text_putc(b, 7, char2int1('t'))
  val b = ward_text_putc(b, 8, char2int1('h'))
  val b = ward_text_putc(b, 9, char2int1('o'))
  val b = ward_text_putc(b, 10, char2int1('r'))
in ward_text_done(b) end

implement cls_info_meta(): ward_safe_text(9) = let
  val b = ward_text_build(9)
  val b = ward_text_putc(b, 0, char2int1('i'))
  val b = ward_text_putc(b, 1, char2int1('n'))
  val b = ward_text_putc(b, 2, char2int1('f'))
  val b = ward_text_putc(b, 3, char2int1('o'))
  val b = ward_text_putc(b, 4, 45) (* '-' *)
  val b = ward_text_putc(b, 5, char2int1('m'))
  val b = ward_text_putc(b, 6, char2int1('e'))
  val b = ward_text_putc(b, 7, char2int1('t'))
  val b = ward_text_putc(b, 8, char2int1('a'))
in ward_text_done(b) end

implement cls_info_row(): ward_safe_text(8) = let
  val b = ward_text_build(8)
  val b = ward_text_putc(b, 0, char2int1('i'))
  val b = ward_text_putc(b, 1, char2int1('n'))
  val b = ward_text_putc(b, 2, char2int1('f'))
  val b = ward_text_putc(b, 3, char2int1('o'))
  val b = ward_text_putc(b, 4, 45) (* '-' *)
  val b = ward_text_putc(b, 5, char2int1('r'))
  val b = ward_text_putc(b, 6, char2int1('o'))
  val b = ward_text_putc(b, 7, char2int1('w'))
in ward_text_done(b) end

implement cls_info_row_label(): ward_safe_text(14) = let
  val b = ward_text_build(14)
  val b = ward_text_putc(b, 0, char2int1('i'))
  val b = ward_text_putc(b, 1, char2int1('n'))
  val b = ward_text_putc(b, 2, char2int1('f'))
  val b = ward_text_putc(b, 3, char2int1('o'))
  val b = ward_text_putc(b, 4, 45) (* '-' *)
  val b = ward_text_putc(b, 5, char2int1('r'))
  val b = ward_text_putc(b, 6, char2int1('o'))
  val b = ward_text_putc(b, 7, char2int1('w'))
  val b = ward_text_putc(b, 8, 45) (* '-' *)
  val b = ward_text_putc(b, 9, char2int1('l'))
  val b = ward_text_putc(b, 10, char2int1('a'))
  val b = ward_text_putc(b, 11, char2int1('b'))
  val b = ward_text_putc(b, 12, char2int1('e'))
  val b = ward_text_putc(b, 13, char2int1('l'))
in ward_text_done(b) end

implement cls_info_row_value(): ward_safe_text(14) = let
  val b = ward_text_build(14)
  val b = ward_text_putc(b, 0, char2int1('i'))
  val b = ward_text_putc(b, 1, char2int1('n'))
  val b = ward_text_putc(b, 2, char2int1('f'))
  val b = ward_text_putc(b, 3, char2int1('o'))
  val b = ward_text_putc(b, 4, 45) (* '-' *)
  val b = ward_text_putc(b, 5, char2int1('r'))
  val b = ward_text_putc(b, 6, char2int1('o'))
  val b = ward_text_putc(b, 7, char2int1('w'))
  val b = ward_text_putc(b, 8, 45) (* '-' *)
  val b = ward_text_putc(b, 9, char2int1('v'))
  val b = ward_text_putc(b, 10, char2int1('a'))
  val b = ward_text_putc(b, 11, char2int1('l'))
  val b = ward_text_putc(b, 12, char2int1('u'))
  val b = ward_text_putc(b, 13, char2int1('e'))
in ward_text_done(b) end

implement cls_info_actions(): ward_safe_text(12) = let
  val b = ward_text_build(12)
  val b = ward_text_putc(b, 0, char2int1('i'))
  val b = ward_text_putc(b, 1, char2int1('n'))
  val b = ward_text_putc(b, 2, char2int1('f'))
  val b = ward_text_putc(b, 3, char2int1('o'))
  val b = ward_text_putc(b, 4, 45) (* '-' *)
  val b = ward_text_putc(b, 5, char2int1('a'))
  val b = ward_text_putc(b, 6, char2int1('c'))
  val b = ward_text_putc(b, 7, char2int1('t'))
  val b = ward_text_putc(b, 8, char2int1('i'))
  val b = ward_text_putc(b, 9, char2int1('o'))
  val b = ward_text_putc(b, 10, char2int1('n'))
  val b = ward_text_putc(b, 11, char2int1('s'))
in ward_text_done(b) end

implement cls_info_btn(): ward_safe_text(8) = let
  val b = ward_text_build(8)
  val b = ward_text_putc(b, 0, char2int1('i'))
  val b = ward_text_putc(b, 1, char2int1('n'))
  val b = ward_text_putc(b, 2, char2int1('f'))
  val b = ward_text_putc(b, 3, char2int1('o'))
  val b = ward_text_putc(b, 4, 45) (* '-' *)
  val b = ward_text_putc(b, 5, char2int1('b'))
  val b = ward_text_putc(b, 6, char2int1('t'))
  val b = ward_text_putc(b, 7, char2int1('n'))
in ward_text_done(b) end

implement cls_info_btn_danger(): ward_safe_text(15) = let
  val b = ward_text_build(15)
  val b = ward_text_putc(b, 0, char2int1('i'))
  val b = ward_text_putc(b, 1, char2int1('n'))
  val b = ward_text_putc(b, 2, char2int1('f'))
  val b = ward_text_putc(b, 3, char2int1('o'))
  val b = ward_text_putc(b, 4, 45) (* '-' *)
  val b = ward_text_putc(b, 5, char2int1('b'))
  val b = ward_text_putc(b, 6, char2int1('t'))
  val b = ward_text_putc(b, 7, char2int1('n'))
  val b = ward_text_putc(b, 8, 45) (* '-' *)
  val b = ward_text_putc(b, 9, char2int1('d'))
  val b = ward_text_putc(b, 10, char2int1('a'))
  val b = ward_text_putc(b, 11, char2int1('n'))
  val b = ward_text_putc(b, 12, char2int1('g'))
  val b = ward_text_putc(b, 13, char2int1('e'))
  val b = ward_text_putc(b, 14, char2int1('r'))
in ward_text_done(b) end

(* ========== Book info CSS ========== *)

#define INFO_CSS_LEN 1100

fn fill_css_info {l:agz}{n:pos}
  (arr: !ward_arr(byte, l, n), alen: int n): void = let
  val () = _w4(arr, alen, 0, 1718511918)       (* .inf *)
  val () = _w4(arr, alen, 4, 1986997615)       (* o-ov *)
  val () = _w4(arr, alen, 8, 1634497125)       (* erla *)
  val () = _w4(arr, alen, 12, 1869642617)       (* y{po *)
  val () = _w4(arr, alen, 16, 1769236851)       (* siti *)
  val () = _w4(arr, alen, 20, 1715105391)       (* on:f *)
  val () = _w4(arr, alen, 24, 1684371561)       (* ixed *)
  val () = _w4(arr, alen, 28, 1936615739)       (* ;ins *)
  val () = _w4(arr, alen, 32, 809137253)       (* et:0 *)
  val () = _w4(arr, alen, 36, 1764588091)       (* ;z-i *)
  val () = _w4(arr, alen, 40, 2019910766)       (* ndex *)
  val () = _w4(arr, alen, 44, 960051514)       (* :999 *)
  val () = _w4(arr, alen, 48, 1667326523)       (* ;bac *)
  val () = _w4(arr, alen, 52, 1869768555)       (* kgro *)
  val () = _w4(arr, alen, 56, 979660405)       (* und: *)
  val () = _w4(arr, alen, 60, 1717986851)       (* #fff *)
  val () = _w4(arr, alen, 64, 1702260539)       (* ;ove *)
  val () = _w4(arr, alen, 68, 1869375090)       (* rflo *)
  val () = _w4(arr, alen, 72, 981020023)       (* w-y: *)
  val () = _w4(arr, alen, 76, 1869903201)       (* auto *)
  val () = _w4(arr, alen, 80, 1936286779)       (* ;dis *)
  val () = _w4(arr, alen, 84, 2036427888)       (* play *)
  val () = _w4(arr, alen, 88, 1701602874)       (* :fle *)
  val () = _w4(arr, alen, 92, 1818639224)       (* x;fl *)
  val () = _w4(arr, alen, 96, 1680701541)       (* ex-d *)
  val () = _w4(arr, alen, 100, 1667592809)       (* irec *)
  val () = _w4(arr, alen, 104, 1852795252)       (* tion *)
  val () = _w4(arr, alen, 108, 1819239226)       (* :col *)
  val () = _w4(arr, alen, 112, 2104388981)       (* umn} *)
  val () = _w4(arr, alen, 116, 1718511918)       (* .inf *)
  val () = _w4(arr, alen, 120, 1701326191)       (* o-he *)
  val () = _w4(arr, alen, 124, 1919247457)       (* ader *)
  val () = _w4(arr, alen, 128, 1936286843)       (* {dis *)
  val () = _w4(arr, alen, 132, 2036427888)       (* play *)
  val () = _w4(arr, alen, 136, 1701602874)       (* :fle *)
  val () = _w4(arr, alen, 140, 1818311544)       (* x;al *)
  val () = _w4(arr, alen, 144, 762210153)       (* ign- *)
  val () = _w4(arr, alen, 148, 1835365481)       (* item *)
  val () = _w4(arr, alen, 152, 1701001843)       (* s:ce *)
  val () = _w4(arr, alen, 156, 1919251566)       (* nter *)
  val () = _w4(arr, alen, 160, 1684107323)       (* ;pad *)
  val () = _w4(arr, alen, 164, 1735289188)       (* ding *)
  val () = _w4(arr, alen, 168, 1882337594)       (* :12p *)
  val () = _w4(arr, alen, 172, 909189240)       (* x 16 *)
  val () = _w4(arr, alen, 176, 1648064624)       (* px;b *)
  val () = _w4(arr, alen, 180, 1701081711)       (* orde *)
  val () = _w4(arr, alen, 184, 1868705138)       (* r-bo *)
  val () = _w4(arr, alen, 188, 1836020852)       (* ttom *)
  val () = _w4(arr, alen, 192, 2020618554)       (* :1px *)
  val () = _w4(arr, alen, 196, 1819243296)       (*  sol *)
  val () = _w4(arr, alen, 200, 589325417)       (* id # *)
  val () = _w4(arr, alen, 204, 811937893)       (* e0e0 *)
  val () = _w4(arr, alen, 208, 779956325)       (* e0}. *)
  val () = _w4(arr, alen, 212, 1868983913)       (* info *)
  val () = _w4(arr, alen, 216, 1667326509)       (* -bac *)
  val () = _w4(arr, alen, 220, 1868725099)       (* k{bo *)
  val () = _w4(arr, alen, 224, 1919247474)       (* rder *)
  val () = _w4(arr, alen, 228, 1852796474)       (* :non *)
  val () = _w4(arr, alen, 232, 1633827685)       (* e;ba *)
  val () = _w4(arr, alen, 236, 1919380323)       (* ckgr *)
  val () = _w4(arr, alen, 240, 1684960623)       (* ound *)
  val () = _w4(arr, alen, 244, 1852796474)       (* :non *)
  val () = _w4(arr, alen, 248, 1868970853)       (* e;fo *)
  val () = _w4(arr, alen, 252, 1932358766)       (* nt-s *)
  val () = _w4(arr, alen, 256, 979729001)       (* ize: *)
  val () = _w4(arr, alen, 260, 2020619825)       (* 16px *)
  val () = _w4(arr, alen, 264, 1920295739)       (* ;cur *)
  val () = _w4(arr, alen, 268, 980578163)       (* sor: *)
  val () = _w4(arr, alen, 272, 1852403568)       (* poin *)
  val () = _w4(arr, alen, 276, 997352820)       (* ter; *)
  val () = _w4(arr, alen, 280, 1684300144)       (* padd *)
  val () = _w4(arr, alen, 284, 979857001)       (* ing: *)
  val () = _w4(arr, alen, 288, 2105045048)       (* 8px} *)
  val () = _w4(arr, alen, 292, 1718511918)       (* .inf *)
  val () = _w4(arr, alen, 296, 1868770671)       (* o-co *)
  val () = _w4(arr, alen, 300, 2071094646)       (* ver{ *)
  val () = _w4(arr, alen, 304, 1886611812)       (* disp *)
  val () = _w4(arr, alen, 308, 981033324)       (* lay: *)
  val () = _w4(arr, alen, 312, 2019912806)       (* flex *)
  val () = _w4(arr, alen, 316, 1937074747)       (* ;jus *)
  val () = _w4(arr, alen, 320, 2036754804)       (* tify *)
  val () = _w4(arr, alen, 324, 1852793645)       (* -con *)
  val () = _w4(arr, alen, 328, 1953391988)       (* tent *)
  val () = _w4(arr, alen, 332, 1852138298)       (* :cen *)
  val () = _w4(arr, alen, 336, 997352820)       (* ter; *)
  val () = _w4(arr, alen, 340, 1684300144)       (* padd *)
  val () = _w4(arr, alen, 344, 979857001)       (* ing: *)
  val () = _w4(arr, alen, 348, 2020619314)       (* 24px *)
  val () = _w4(arr, alen, 352, 779956256)       (*  0}. *)
  val () = _w4(arr, alen, 356, 1868983913)       (* info *)
  val () = _w4(arr, alen, 360, 1987011373)       (* -cov *)
  val () = _w4(arr, alen, 364, 1763734117)       (* er i *)
  val () = _w4(arr, alen, 368, 1836803949)       (* mg{m *)
  val () = _w4(arr, alen, 372, 1999468641)       (* ax-w *)
  val () = _w4(arr, alen, 376, 1752458345)       (* idth *)
  val () = _w4(arr, alen, 380, 808988986)       (* :180 *)
  val () = _w4(arr, alen, 384, 1832614000)       (* px;m *)
  val () = _w4(arr, alen, 388, 1747810401)       (* ax-h *)
  val () = _w4(arr, alen, 392, 1751607653)       (* eigh *)
  val () = _w4(arr, alen, 396, 875706996)       (* t:24 *)
  val () = _w4(arr, alen, 400, 997748784)       (* 0px; *)
  val () = _w4(arr, alen, 404, 1685221218)       (* bord *)
  val () = _w4(arr, alen, 408, 1915581029)       (* er-r *)
  val () = _w4(arr, alen, 412, 1969841249)       (* adiu *)
  val () = _w4(arr, alen, 416, 1882471027)       (* s:4p *)
  val () = _w4(arr, alen, 420, 1764654456)       (* x}.i *)
  val () = _w4(arr, alen, 424, 762275438)       (* nfo- *)
  val () = _w4(arr, alen, 428, 1819568500)       (* titl *)
  val () = _w4(arr, alen, 432, 1868987237)       (* e{fo *)
  val () = _w4(arr, alen, 436, 1932358766)       (* nt-s *)
  val () = _w4(arr, alen, 440, 979729001)       (* ize: *)
  val () = _w4(arr, alen, 444, 2020618290)       (* 20px *)
  val () = _w4(arr, alen, 448, 1852794427)       (* ;fon *)
  val () = _w4(arr, alen, 452, 1702309236)       (* t-we *)
  val () = _w4(arr, alen, 456, 1952999273)       (* ight *)
  val () = _w4(arr, alen, 460, 808465978)       (* :600 *)
  val () = _w4(arr, alen, 464, 1684107323)       (* ;pad *)
  val () = _w4(arr, alen, 468, 1735289188)       (* ding *)
  val () = _w4(arr, alen, 472, 824193082)       (* :0 1 *)
  val () = _w4(arr, alen, 476, 997748790)       (* 6px; *)
  val () = _w4(arr, alen, 480, 1735549293)       (* marg *)
  val () = _w4(arr, alen, 484, 1647144553)       (* in-b *)
  val () = _w4(arr, alen, 488, 1869902959)       (* otto *)
  val () = _w4(arr, alen, 492, 1882471021)       (* m:4p *)
  val () = _w4(arr, alen, 496, 1764654456)       (* x}.i *)
  val () = _w4(arr, alen, 500, 762275438)       (* nfo- *)
  val () = _w4(arr, alen, 504, 1752462689)       (* auth *)
  val () = _w4(arr, alen, 508, 1719366255)       (* or{f *)
  val () = _w4(arr, alen, 512, 762605167)       (* ont- *)
  val () = _w4(arr, alen, 516, 1702521203)       (* size *)
  val () = _w4(arr, alen, 520, 1882468666)       (* :14p *)
  val () = _w4(arr, alen, 524, 1868774264)       (* x;co *)
  val () = _w4(arr, alen, 528, 980578156)       (* lor: *)
  val () = _w4(arr, alen, 532, 909522467)       (* #666 *)
  val () = _w4(arr, alen, 536, 1684107323)       (* ;pad *)
  val () = _w4(arr, alen, 540, 1735289188)       (* ding *)
  val () = _w4(arr, alen, 544, 824193082)       (* :0 1 *)
  val () = _w4(arr, alen, 548, 997748790)       (* 6px; *)
  val () = _w4(arr, alen, 552, 1735549293)       (* marg *)
  val () = _w4(arr, alen, 556, 1647144553)       (* in-b *)
  val () = _w4(arr, alen, 560, 1869902959)       (* otto *)
  val () = _w4(arr, alen, 564, 909195885)       (* m:16 *)
  val () = _w4(arr, alen, 568, 779974768)       (* px}. *)
  val () = _w4(arr, alen, 572, 1868983913)       (* info *)
  val () = _w4(arr, alen, 576, 1952804141)       (* -met *)
  val () = _w4(arr, alen, 580, 1634761569)       (* a{pa *)
  val () = _w4(arr, alen, 584, 1852400740)       (* ddin *)
  val () = _w4(arr, alen, 588, 540031591)       (* g:0  *)
  val () = _w4(arr, alen, 592, 2020619825)       (* 16px *)
  val () = _w4(arr, alen, 596, 1918987579)       (* ;mar *)
  val () = _w4(arr, alen, 600, 762210663)       (* gin- *)
  val () = _w4(arr, alen, 604, 1953787746)       (* bott *)
  val () = _w4(arr, alen, 608, 842689903)       (* om:2 *)
  val () = _w4(arr, alen, 612, 2105045044)       (* 4px} *)
  val () = _w4(arr, alen, 616, 1718511918)       (* .inf *)
  val () = _w4(arr, alen, 620, 1869753711)       (* o-ro *)
  val () = _w4(arr, alen, 624, 1768192887)       (* w{di *)
  val () = _w4(arr, alen, 628, 1634496627)       (* spla *)
  val () = _w4(arr, alen, 632, 1818638969)       (* y:fl *)
  val () = _w4(arr, alen, 636, 1782282341)       (* ex;j *)
  val () = _w4(arr, alen, 640, 1769239413)       (* usti *)
  val () = _w4(arr, alen, 644, 1663924582)       (* fy-c *)
  val () = _w4(arr, alen, 648, 1702129263)       (* onte *)
  val () = _w4(arr, alen, 652, 1933210734)       (* nt:s *)
  val () = _w4(arr, alen, 656, 1701011824)       (* pace *)
  val () = _w4(arr, alen, 660, 1952801325)       (* -bet *)
  val () = _w4(arr, alen, 664, 1852138871)       (* ween *)
  val () = _w4(arr, alen, 668, 1684107323)       (* ;pad *)
  val () = _w4(arr, alen, 672, 1735289188)       (* ding *)
  val () = _w4(arr, alen, 676, 2020620346)       (* :8px *)
  val () = _w4(arr, alen, 680, 1648046112)       (*  0;b *)
  val () = _w4(arr, alen, 684, 1701081711)       (* orde *)
  val () = _w4(arr, alen, 688, 1868705138)       (* r-bo *)
  val () = _w4(arr, alen, 692, 1836020852)       (* ttom *)
  val () = _w4(arr, alen, 696, 2020618554)       (* :1px *)
  val () = _w4(arr, alen, 700, 1819243296)       (*  sol *)
  val () = _w4(arr, alen, 704, 589325417)       (* id # *)
  val () = _w4(arr, alen, 708, 996500837)       (* eee; *)
  val () = _w4(arr, alen, 712, 1953394534)       (* font *)
  val () = _w4(arr, alen, 716, 2053731117)       (* -siz *)
  val () = _w4(arr, alen, 720, 875641445)       (* e:14 *)
  val () = _w4(arr, alen, 724, 779974768)       (* px}. *)
  val () = _w4(arr, alen, 728, 1868983913)       (* info *)
  val () = _w4(arr, alen, 732, 2003792429)       (* -row *)
  val () = _w4(arr, alen, 736, 1650551853)       (* -lab *)
  val () = _w4(arr, alen, 740, 1669033061)       (* el{c *)
  val () = _w4(arr, alen, 744, 1919904879)       (* olor *)
  val () = _w4(arr, alen, 748, 909517626)       (* :#66 *)
  val () = _w4(arr, alen, 752, 1764654390)       (* 6}.i *)
  val () = _w4(arr, alen, 756, 762275438)       (* nfo- *)
  val () = _w4(arr, alen, 760, 762802034)       (* row- *)
  val () = _w4(arr, alen, 764, 1970037110)       (* valu *)
  val () = _w4(arr, alen, 768, 1868987237)       (* e{fo *)
  val () = _w4(arr, alen, 772, 1999467630)       (* nt-w *)
  val () = _w4(arr, alen, 776, 1751607653)       (* eigh *)
  val () = _w4(arr, alen, 780, 808794740)       (* t:50 *)
  val () = _w4(arr, alen, 784, 1764654384)       (* 0}.i *)
  val () = _w4(arr, alen, 788, 762275438)       (* nfo- *)
  val () = _w4(arr, alen, 792, 1769235297)       (* acti *)
  val () = _w4(arr, alen, 796, 2071162479)       (* ons{ *)
  val () = _w4(arr, alen, 800, 1886611812)       (* disp *)
  val () = _w4(arr, alen, 804, 981033324)       (* lay: *)
  val () = _w4(arr, alen, 808, 2019912806)       (* flex *)
  val () = _w4(arr, alen, 812, 1885431611)       (* ;gap *)
  val () = _w4(arr, alen, 816, 2020620346)       (* :8px *)
  val () = _w4(arr, alen, 820, 1684107323)       (* ;pad *)
  val () = _w4(arr, alen, 824, 1735289188)       (* ding *)
  val () = _w4(arr, alen, 828, 1882599738)       (* :16p *)
  val () = _w4(arr, alen, 832, 1634548600)       (* x;ma *)
  val () = _w4(arr, alen, 836, 1852401522)       (* rgin *)
  val () = _w4(arr, alen, 840, 1886352429)       (* -top *)
  val () = _w4(arr, alen, 844, 1953849658)       (* :aut *)
  val () = _w4(arr, alen, 848, 1764654447)       (* o}.i *)
  val () = _w4(arr, alen, 852, 762275438)       (* nfo- *)
  val () = _w4(arr, alen, 856, 2070836322)       (* btn{ *)
  val () = _w4(arr, alen, 860, 2019912806)       (* flex *)
  val () = _w4(arr, alen, 864, 1882927418)       (* :1;p *)
  val () = _w4(arr, alen, 868, 1768186977)       (* addi *)
  val () = _w4(arr, alen, 872, 825911150)       (* ng:1 *)
  val () = _w4(arr, alen, 876, 997748784)       (* 0px; *)
  val () = _w4(arr, alen, 880, 1685221218)       (* bord *)
  val () = _w4(arr, alen, 884, 825913957)       (* er:1 *)
  val () = _w4(arr, alen, 888, 1931507824)       (* px s *)
  val () = _w4(arr, alen, 892, 1684630639)       (* olid *)
  val () = _w4(arr, alen, 896, 1684284192)       (*  #dd *)
  val () = _w4(arr, alen, 900, 1868708708)       (* d;bo *)
  val () = _w4(arr, alen, 904, 1919247474)       (* rder *)
  val () = _w4(arr, alen, 908, 1684107821)       (* -rad *)
  val () = _w4(arr, alen, 912, 980645225)       (* ius: *)
  val () = _w4(arr, alen, 916, 997748790)       (* 6px; *)
  val () = _w4(arr, alen, 920, 1801675106)       (* back *)
  val () = _w4(arr, alen, 924, 1970238055)       (* grou *)
  val () = _w4(arr, alen, 928, 591029358)       (* nd:# *)
  val () = _w4(arr, alen, 932, 996566630)       (* fff; *)
  val () = _w4(arr, alen, 936, 1953394534)       (* font *)
  val () = _w4(arr, alen, 940, 2053731117)       (* -siz *)
  val () = _w4(arr, alen, 944, 875641445)       (* e:14 *)
  val () = _w4(arr, alen, 948, 1664841840)       (* px;c *)
  val () = _w4(arr, alen, 952, 1869836917)       (* urso *)
  val () = _w4(arr, alen, 956, 1869625970)       (* r:po *)
  val () = _w4(arr, alen, 960, 1702129257)       (* inte *)
  val () = _w4(arr, alen, 964, 1764654450)       (* r}.i *)
  val () = _w4(arr, alen, 968, 762275438)       (* nfo- *)
  val () = _w4(arr, alen, 972, 762213474)       (* btn- *)
  val () = _w4(arr, alen, 976, 1735287140)       (* dang *)
  val () = _w4(arr, alen, 980, 1719366245)       (* er{f *)
  val () = _w4(arr, alen, 984, 980968812)       (* lex: *)
  val () = _w4(arr, alen, 988, 1634745137)       (* 1;pa *)
  val () = _w4(arr, alen, 992, 1852400740)       (* ddin *)
  val () = _w4(arr, alen, 996, 808532583)       (* g:10 *)
  val () = _w4(arr, alen, 1000, 1648064624)       (* px;b *)
  val () = _w4(arr, alen, 1004, 1701081711)       (* orde *)
  val () = _w4(arr, alen, 1008, 1882274418)       (* r:1p *)
  val () = _w4(arr, alen, 1012, 1869815928)       (* x so *)
  val () = _w4(arr, alen, 1016, 543451500)       (* lid  *)
  val () = _w4(arr, alen, 1020, 842162979)       (* #c22 *)
  val () = _w4(arr, alen, 1024, 1919902267)       (* ;bor *)
  val () = _w4(arr, alen, 1028, 762471780)       (* der- *)
  val () = _w4(arr, alen, 1032, 1768186226)       (* radi *)
  val () = _w4(arr, alen, 1036, 909800309)       (* us:6 *)
  val () = _w4(arr, alen, 1040, 1648064624)       (* px;b *)
  val () = _w4(arr, alen, 1044, 1735091041)       (* ackg *)
  val () = _w4(arr, alen, 1048, 1853190002)       (* roun *)
  val () = _w4(arr, alen, 1052, 1713584740)       (* d:#f *)
  val () = _w4(arr, alen, 1056, 1664837222)       (* ff;c *)
  val () = _w4(arr, alen, 1060, 1919904879)       (* olor *)
  val () = _w4(arr, alen, 1064, 845357882)       (* :#c2 *)
  val () = _w4(arr, alen, 1068, 1868970802)       (* 2;fo *)
  val () = _w4(arr, alen, 1072, 1932358766)       (* nt-s *)
  val () = _w4(arr, alen, 1076, 979729001)       (* ize: *)
  val () = _w4(arr, alen, 1080, 2020619313)       (* 14px *)
  val () = _w4(arr, alen, 1084, 1920295739)       (* ;cur *)
  val () = _w4(arr, alen, 1088, 980578163)       (* sor: *)
  val () = _w4(arr, alen, 1092, 1852403568)       (* poin *)
  val () = _w4(arr, alen, 1096, 2104649076)       (* ter} *)
in end

fn inject_info_css(parent: int): void = let
  val info_arr = ward_arr_alloc<byte>(INFO_CSS_LEN)
  val () = fill_css_info(info_arr, INFO_CSS_LEN)
  val style_id = dom_next_id()
  val dom = ward_dom_init()
  val s = ward_dom_stream_begin(dom)
  val s = ward_dom_stream_create_element(s, style_id, parent, tag_style(), 5)
  val @(frozen, borrow) = ward_arr_freeze<byte>(info_arr)
  val s = ward_dom_stream_set_text(s, style_id, borrow, INFO_CSS_LEN)
  val () = ward_arr_drop<byte>(frozen, borrow)
  val info_arr = ward_arr_thaw<byte>(frozen)
  val () = ward_arr_free<byte>(info_arr)
  val dom = ward_dom_stream_end(s)
  val () = ward_dom_fini(dom)
in end

(* Dismiss book info: remove overlay from DOM, reset app_state *)
implement dismiss_book_info(): void = let
  val overlay_id = _app_info_overlay_id()
in
  if gt_int_int(overlay_id, 0) then let
    val dom = ward_dom_init()
    val s = ward_dom_stream_begin(dom)
    val s = ward_dom_stream_remove_child(s, overlay_id)
    val dom = ward_dom_stream_end(s)
    val () = ward_dom_fini(dom)
    val () = _app_set_info_overlay_id(0)
  in end
  else ()
end

(* ========== Date conversion: civil_from_days ========== *)

(* Leap year check: year divisible by 4, except centuries unless div by 400.
 * Returns 1 if leap, 0 otherwise. *)
fn _is_leap_year(y: int): int =
  if eq_int_int(mod_int_int(y, 4), 0) then
    if eq_int_int(mod_int_int(y, 100), 0) then
      if eq_int_int(mod_int_int(y, 400), 0) then 1
      else 0
    else 1
  else 0

(* Get days in month for given year and month.
 * Returns (MONTH_DAYS(m, dim) | int(dim)).
 * Feb checks leap year. *)
fn _get_month_days(y: int, m: int): int =
  if eq_int_int(m, 1) then 31
  else if eq_int_int(m, 2) then
    if eq_int_int(_is_leap_year(y), 1) then 29 else 28
  else if eq_int_int(m, 3) then 31
  else if eq_int_int(m, 4) then 30
  else if eq_int_int(m, 5) then 31
  else if eq_int_int(m, 6) then 30
  else if eq_int_int(m, 7) then 31
  else if eq_int_int(m, 8) then 31
  else if eq_int_int(m, 9) then 30
  else if eq_int_int(m, 10) then 31
  else if eq_int_int(m, 11) then 30
  else 31 (* December *)

(* civil_from_days: convert days since Unix epoch (1970-01-01) to (y, m, d).
 * Recursive -- applies next_day n times starting from (1970, 1, 1).
 * Results written to sbuf i32 slots: [0]=year, [1]=month, [2]=day.
 * O(N) where N ~ 20000 for current timestamps -- fine in WASM. *)
fun _civil_from_days_loop {k:nat} .<k>.
  (rem: int(k), y: int, m: int, d: int): void =
  if lte_g1(rem, 0) then let
    (* Write results to sbuf as i32 at byte offsets 0, 4, 8 *)
    val () = _app_sbuf_set_u8(0, band_int_int(y, 255))
    val () = _app_sbuf_set_u8(1, band_int_int(bsr_int_int(y, 8), 255))
    val () = _app_sbuf_set_u8(2, band_int_int(bsr_int_int(y, 16), 255))
    val () = _app_sbuf_set_u8(3, bsr_int_int(y, 24))
    val () = _app_sbuf_set_u8(4, band_int_int(m, 255))
    val () = _app_sbuf_set_u8(5, band_int_int(bsr_int_int(m, 8), 255))
    val () = _app_sbuf_set_u8(8, band_int_int(d, 255))
    val () = _app_sbuf_set_u8(9, band_int_int(bsr_int_int(d, 8), 255))
  in end
  else let
    val dim = _get_month_days(y, m)
  in
    if lt_int_int(d, dim) then
      _civil_from_days_loop(sub_g1(rem, 1), y, m, d + 1)
    else if lt_int_int(m, 12) then
      _civil_from_days_loop(sub_g1(rem, 1), y, m + 1, 1)
    else
      _civil_from_days_loop(sub_g1(rem, 1), y + 1, 1, 1)
  end

fn civil_from_days(days: int): void = let
  val d = g1ofg0(days)
in
  if gte_g1(d, 0) then
    _civil_from_days_loop(d, 1970, 1, 1)
  else let
    (* Negative days -- write epoch *)
    val () = _app_sbuf_set_u8(0, band_int_int(1970, 255))
    val () = _app_sbuf_set_u8(1, band_int_int(bsr_int_int(1970, 8), 255))
    val () = _app_sbuf_set_u8(2, 0)
    val () = _app_sbuf_set_u8(3, 0)
    val () = _app_sbuf_set_u8(4, 1)
    val () = _app_sbuf_set_u8(5, 0)
    val () = _app_sbuf_set_u8(8, 1)
    val () = _app_sbuf_set_u8(9, 0)
  in end
end

(* Read civil_from_days results from sbuf *)
fn _read_civil_year(): int =
  bor_int_int(_app_sbuf_get_u8(0), bsl_int_int(_app_sbuf_get_u8(1), 8))

fn _read_civil_month(): int =
  bor_int_int(_app_sbuf_get_u8(4), bsl_int_int(_app_sbuf_get_u8(5), 8))

fn _read_civil_day(): int =
  bor_int_int(_app_sbuf_get_u8(8), bsl_int_int(_app_sbuf_get_u8(9), 8))

(* ========== Number-to-string formatters ========== *)

(* Write an unsigned integer into ward_arr as ASCII decimal digits.
 * Returns number of digits written. Max 10 digits for 32-bit int.
 * Writes from position `pos` forward. *)
fn _write_uint {l:agz}{n:pos}
  (arr: !ward_arr(byte, l, n), alen: int n, pos: int, v: int): int =
  if eq_int_int(v, 0) then let
    val () = ward_arr_set_byte(arr, pos, alen, 48)  (* '0' *)
  in 1 end
  else let
    (* Count digits first *)
    fun count_digits(x: int, cnt: int): int =
      if lte_int_int(x, 0) then cnt
      else count_digits(div_int_int(x, 10), cnt + 1)
    val nd = count_digits(v, 0)
    (* Write digits from right to left *)
    fun write_loop {k:nat} .<k>.
      (rem: int(k), arr: !ward_arr(byte, l, n), alen: int n,
       x: int, p: int): void =
      if lte_g1(rem, 0) then ()
      else if gt_int_int(x, 0) then let
        val digit = mod_int_int(x, 10)
        val () = ward_arr_set_byte(arr, p, alen, digit + 48)
      in write_loop(sub_g1(rem, 1), arr, alen, div_int_int(x, 10), p - 1) end
    val () = write_loop(_checked_nat(nd), arr, alen, v, pos + nd - 1)
  in nd end

(* Write 3-letter month abbreviation at position. Returns 3. *)
fn _write_month_abbr {l:agz}{n:pos}
  (arr: !ward_arr(byte, l, n), alen: int n, pos: int, m: int): int = let
  (* Month abbreviations: Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec *)
  val c0 =
    if eq_int_int(m, 1) then 74  (* J *)
    else if eq_int_int(m, 2) then 70  (* F *)
    else if eq_int_int(m, 3) then 77  (* M *)
    else if eq_int_int(m, 4) then 65  (* A *)
    else if eq_int_int(m, 5) then 77  (* M *)
    else if eq_int_int(m, 6) then 74  (* J *)
    else if eq_int_int(m, 7) then 74  (* J *)
    else if eq_int_int(m, 8) then 65  (* A *)
    else if eq_int_int(m, 9) then 83  (* S *)
    else if eq_int_int(m, 10) then 79 (* O *)
    else if eq_int_int(m, 11) then 78 (* N *)
    else 68 (* D *)
  val c1 =
    if eq_int_int(m, 1) then 97   (* a *)
    else if eq_int_int(m, 2) then 101  (* e *)
    else if eq_int_int(m, 3) then 97   (* a *)
    else if eq_int_int(m, 4) then 112  (* p *)
    else if eq_int_int(m, 5) then 97   (* a *)
    else if eq_int_int(m, 6) then 117  (* u *)
    else if eq_int_int(m, 7) then 117  (* u *)
    else if eq_int_int(m, 8) then 117  (* u *)
    else if eq_int_int(m, 9) then 101  (* e *)
    else if eq_int_int(m, 10) then 99  (* c *)
    else if eq_int_int(m, 11) then 111 (* o *)
    else 101 (* e *)
  val c2 =
    if eq_int_int(m, 1) then 110  (* n *)
    else if eq_int_int(m, 2) then 98   (* b *)
    else if eq_int_int(m, 3) then 114  (* r *)
    else if eq_int_int(m, 4) then 114  (* r *)
    else if eq_int_int(m, 5) then 121  (* y *)
    else if eq_int_int(m, 6) then 110  (* n *)
    else if eq_int_int(m, 7) then 108  (* l *)
    else if eq_int_int(m, 8) then 103  (* g *)
    else if eq_int_int(m, 9) then 112  (* p *)
    else if eq_int_int(m, 10) then 116 (* t *)
    else if eq_int_int(m, 11) then 118 (* v *)
    else 99  (* c *)
  val () = ward_arr_set_byte(arr, pos, alen, c0)
  val () = ward_arr_set_byte(arr, pos + 1, alen, c1)
  val () = ward_arr_set_byte(arr, pos + 2, alen, c2)
in 3 end

(* Format date as "MMM DD, YYYY" into ward_arr. Returns total length.
 * Takes Unix timestamp in seconds. *)
fn _format_date {l:agz}{n:pos}
  (arr: !ward_arr(byte, l, n), alen: int n, ts_seconds: int): int =
  if lte_int_int(ts_seconds, 0) then let
    (* Unknown date -- write em dash U+2014 = E2 80 94 *)
    val () = ward_arr_set_byte(arr, 0, alen, 226)   (* 0xE2 *)
    val () = ward_arr_set_byte(arr, 1, alen, 128)   (* 0x80 *)
    val () = ward_arr_set_byte(arr, 2, alen, 148)   (* 0x94 *)
  in 3 end
  else let
    (* Convert seconds to days since epoch *)
    val days = div_int_int(ts_seconds, 86400)
    val () = civil_from_days(days)
    val year = _read_civil_year()
    val month = _read_civil_month()
    val day = _read_civil_day()
    (* Write "MMM DD, YYYY" *)
    var pos: int = 0
    val d1 = _write_month_abbr(arr, alen, 0, month)
    val pos = d1
    val () = ward_arr_set_byte(arr, pos, alen, 32)  (* ' ' *)
    val pos = pos + 1
    val d2 = _write_uint(arr, alen, pos, day)
    val pos = pos + d2
    val () = ward_arr_set_byte(arr, pos, alen, 44)  (* ',' *)
    val () = ward_arr_set_byte(arr, pos + 1, alen, 32)  (* ' ' *)
    val pos = pos + 2
    val d3 = _write_uint(arr, alen, pos, year)
    val pos = pos + d3
  in pos end

(* Format file size into ward_arr. Returns total length.
 * >= 1 MB: "X.Y MB", < 1 MB: "X KB" *)
fn _format_size {l:agz}{n:pos}
  (arr: !ward_arr(byte, l, n), alen: int n, file_size: int): int =
  if lte_int_int(file_size, 0) then let
    val () = ward_arr_set_byte(arr, 0, alen, 48)    (* '0' *)
    val () = ward_arr_set_byte(arr, 1, alen, 32)    (* ' ' *)
    val () = ward_arr_set_byte(arr, 2, alen, 75)    (* 'K' *)
    val () = ward_arr_set_byte(arr, 3, alen, 66)    (* 'B' *)
  in 4 end
  else let
    val fs = g1ofg0(file_size)
  in
    if gte_g1(fs, 1048576) then let
      (* MB: whole.tenths *)
      val whole = div_int_int(fs, 1048576)
      val frac = div_int_int(mod_int_int(fs, 1048576) * 10, 1048576)
      val d1 = _write_uint(arr, alen, 0, whole)
      var pos: int = d1
      val () = ward_arr_set_byte(arr, pos, alen, 46)    (* '.' *)
      val pos = pos + 1
      val d2 = _write_uint(arr, alen, pos, frac)
      val pos = pos + d2
      val () = ward_arr_set_byte(arr, pos, alen, 32)    (* ' ' *)
      val () = ward_arr_set_byte(arr, pos + 1, alen, 77)  (* 'M' *)
      val () = ward_arr_set_byte(arr, pos + 2, alen, 66)  (* 'B' *)
    in pos + 3 end
    else let
      (* KB *)
      val kb = div_int_int(fs, 1024)
      val kb2 = if lte_int_int(kb, 0) then 1 else kb
      val d1 = _write_uint(arr, alen, 0, kb2)
      var pos: int = d1
      val () = ward_arr_set_byte(arr, pos, alen, 32)    (* ' ' *)
      val () = ward_arr_set_byte(arr, pos + 1, alen, 75)  (* 'K' *)
      val () = ward_arr_set_byte(arr, pos + 2, alen, 66)  (* 'B' *)
    in pos + 3 end
  end

(* Format progress string into ward_arr. Returns total length.
 * "Ch X of Y" format for in-progress reading.
 * For new books (ch=0, pg=0): no output (handled by caller with text constant).
 * For done books: no output (handled by caller with text constant). *)
fn _format_progress {l:agz}{n:pos}
  (arr: !ward_arr(byte, l, n), alen: int n, ch: int, pg: int, sc: int): int =
  if lte_int_int(sc, 0) then 0  (* no spine count *)
  else let
    (* "Ch X of Y" *)
    val () = ward_arr_set_byte(arr, 0, alen, 67)   (* 'C' *)
    val () = ward_arr_set_byte(arr, 1, alen, 104)  (* 'h' *)
    val () = ward_arr_set_byte(arr, 2, alen, 32)   (* ' ' *)
    val d1 = _write_uint(arr, alen, 3, ch + 1)
    var pos: int = 3 + d1
    val () = ward_arr_set_byte(arr, pos, alen, 32)     (* ' ' *)
    val () = ward_arr_set_byte(arr, pos + 1, alen, 111) (* 'o' *)
    val () = ward_arr_set_byte(arr, pos + 2, alen, 102) (* 'f' *)
    val () = ward_arr_set_byte(arr, pos + 3, alen, 32)  (* ' ' *)
    val pos = pos + 4
    val d2 = _write_uint(arr, alen, pos, sc)
    val pos = pos + d2
  in pos end

(* ========== Render step helpers ========== *)

(* Step 1: Render header with back button *)
fn _render_info_header {l:agz}
  (s: ward_dom_stream(l), overlay_id: int)
  : (INFO_HEADER_DONE() | ward_dom_stream(l)) = let
  val header_id = dom_next_id()
  val s = ward_dom_stream_create_element(s, header_id, overlay_id, tag_div(), 3)
  val s = ward_dom_stream_set_attr_safe(s, header_id, attr_class(), 5, cls_info_header(), 11)
  val back_id = dom_next_id()
  val s = ward_dom_stream_create_element(s, back_id, header_id, tag_button(), 6)
  val s = ward_dom_stream_set_attr_safe(s, back_id, attr_class(), 5, cls_info_back(), 9)
  val s = set_text_cstr(VT_46() | s, back_id, 46, 4)
in (HEADER_RENDERED() | s) end

(* Step 2: Render cover image area *)
fn _render_info_cover {l:agz}
  (s: ward_dom_stream(l), overlay_id: int, has_cover: int, book_idx: int)
  : (INFO_COVER_DONE() | ward_dom_stream(l)) = let
  val cover_div_id = dom_next_id()
  val s = ward_dom_stream_create_element(s, cover_div_id, overlay_id, tag_div(), 3)
  val s = ward_dom_stream_set_attr_safe(s, cover_div_id, attr_class(), 5, cls_info_cover(), 10)
in (COVER_RENDERED() | s) end

(* Step 3: Render title *)
fn _render_info_title {l:agz}
  (s: ward_dom_stream(l), overlay_id: int, book_idx: int)
  : (INFO_TITLE_DONE() | ward_dom_stream(l)) = let
  val title_div_id = dom_next_id()
  val s = ward_dom_stream_create_element(s, title_div_id, overlay_id, tag_div(), 3)
  val s = ward_dom_stream_set_attr_safe(s, title_div_id, attr_class(), 5, cls_info_title(), 10)
  val title_len = library_get_title(book_idx, 0)
  val s = set_text_from_sbuf(s, title_div_id, title_len)
in (TITLE_RENDERED() | s) end

(* Step 4: Render author *)
fn _render_info_author {l:agz}
  (s: ward_dom_stream(l), overlay_id: int, book_idx: int)
  : (INFO_AUTHOR_DONE() | ward_dom_stream(l)) = let
  val author_div_id = dom_next_id()
  val s = ward_dom_stream_create_element(s, author_div_id, overlay_id, tag_div(), 3)
  val s = ward_dom_stream_set_attr_safe(s, author_div_id, attr_class(), 5, cls_info_author(), 11)
  val author_len = library_get_author(book_idx, 0)
  val s = set_text_from_sbuf(s, author_div_id, author_len)
in (AUTHOR_RENDERED() | s) end

(* Helper: copy ward_arr bytes to sbuf *)
fn _copy_arr_to_sbuf {l:agz}{n:pos}
  (arr: !ward_arr(byte, l, n), alen: int n, cnt: int): void = let
  fun loop {k:nat} .<k>.
    (rem: int(k), arr: !ward_arr(byte, l, n), alen: int n, i: int, cnt: int): void =
    if lte_g1(rem, 0) then ()
    else if lt_int_int(i, cnt) then let
      val b = byte2int0(ward_arr_get<byte>(arr, _ward_idx(i, alen)))
      val () = _app_sbuf_set_u8(i, b)
    in loop(sub_g1(rem, 1), arr, alen, i + 1, cnt) end
in loop(_checked_nat(cnt), arr, alen, 0, cnt) end

(* Helper: render a metadata row label using text constant *)
fn _info_render_label {l:agz}
  (ss: ward_dom_stream(l), label_id: int, text_id: int, text_len: int)
  : ward_dom_stream(l) = let
  val tl = g1ofg0(text_len)
in
  if tl > 0 then
    if tl < 65536 then let
      val larr = ward_arr_alloc<byte>(tl)
      val () = fill_text(larr, tl, text_id)
      val @(lfroz, lborrow) = ward_arr_freeze<byte>(larr)
      val ss = ward_dom_stream_set_text(ss, label_id, lborrow, tl)
      val () = ward_arr_drop<byte>(lfroz, lborrow)
      val larr = ward_arr_thaw<byte>(lfroz)
      val () = ward_arr_free<byte>(larr)
    in ss end
    else ss
  else ss
end

(* Helper: format date data into sbuf, return length *)
fn _info_format_date_to_sbuf(ts: int): int = let
  val bsz = _checked_arr_size(48)
  val arr = ward_arr_alloc<byte>(bsz)
  val vlen = _format_date(arr, bsz, ts)
  val () = _copy_arr_to_sbuf(arr, bsz, vlen)
  val () = ward_arr_free<byte>(arr)
in vlen end

(* Helper: format size data into sbuf, return length *)
fn _info_format_size_to_sbuf(file_sz: int): int = let
  val bsz = _checked_arr_size(48)
  val arr = ward_arr_alloc<byte>(bsz)
  val vlen = _format_size(arr, bsz, file_sz)
  val () = _copy_arr_to_sbuf(arr, bsz, vlen)
  val () = ward_arr_free<byte>(arr)
in vlen end

(* Helper: format progress data into sbuf, return length *)
fn _info_format_progress_to_sbuf(ch: int, pg: int, sc: int): int = let
  val bsz = _checked_arr_size(48)
  val arr = ward_arr_alloc<byte>(bsz)
  val vlen = _format_progress(arr, bsz, ch, pg, sc)
  val () = _copy_arr_to_sbuf(arr, bsz, vlen)
  val () = ward_arr_free<byte>(arr)
in vlen end

(* Helper: render a metadata row from sbuf data.
 * Data must already be in sbuf[0..vlen-1]. *)
fn _info_render_row_from_sbuf(meta_id: int, label_text_id: int,
  label_text_len: int, vlen: int): void =
  if gt_int_int(vlen, 0) then let
    val dom = ward_dom_init()
    val ss = ward_dom_stream_begin(dom)
    val row_id = dom_next_id()
    val ss = ward_dom_stream_create_element(ss, row_id, meta_id, tag_div(), 3)
    val ss = ward_dom_stream_set_attr_safe(ss, row_id, attr_class(), 5, cls_info_row(), 8)
    val label_id = dom_next_id()
    val ss = ward_dom_stream_create_element(ss, label_id, row_id, tag_span(), 4)
    val ss = ward_dom_stream_set_attr_safe(ss, label_id, attr_class(), 5, cls_info_row_label(), 14)
    val ss = _info_render_label(ss, label_id, label_text_id, label_text_len)
    val value_id = dom_next_id()
    val ss = ward_dom_stream_create_element(ss, value_id, row_id, tag_span(), 4)
    val ss = ward_dom_stream_set_attr_safe(ss, value_id, attr_class(), 5, cls_info_row_value(), 14)
    val ss = set_text_from_sbuf(ss, value_id, vlen)
    val dom = ward_dom_stream_end(ss)
    val () = ward_dom_fini(dom)
  in end
  else ()

(* Step 5: Render metadata rows (progress, added, last read, size).
 * Each row uses _info_render_row which owns its own DOM stream
 * to avoid viewtype-in-if-then-else issues.
 *
 * FLUSH REQUIRED: _info_render_row_from_sbuf creates separate DOM streams
 * that reference meta_id as parent. meta_id must exist in the bridge's
 * nodes map before the row streams can append to it. The main stream must
 * be flushed (end+fini) before row rendering, then restarted after. *)
fn _render_info_meta {l:agz}
  (s: ward_dom_stream(l), overlay_id: int, book_idx: int)
  : (INFO_META_DONE() | [l2:agz] ward_dom_stream(l2)) = let
  val meta_id = dom_next_id()
  val s = ward_dom_stream_create_element(s, meta_id, overlay_id, tag_div(), 3)
  val s = ward_dom_stream_set_attr_safe(s, meta_id, attr_class(), 5, cls_info_meta(), 9)

  (* Flush main stream so meta_id exists in bridge nodes map *)
  val dom = ward_dom_stream_end(s)
  val () = ward_dom_fini(dom)

  (* Row 1: Progress *)
  val ch = library_get_chapter(book_idx)
  val pg = library_get_page(book_idx)
  val sc = library_get_spine_count(book_idx)
  val plen = _info_format_progress_to_sbuf(ch, pg, sc)
  val () = _info_render_row_from_sbuf(meta_id, TEXT_PROGRESS, 8, plen)
  prval pf_prog = PROGRESS_ROW_DONE()

  (* Row 2: Added date *)
  val alen = _info_format_date_to_sbuf(library_get_date_added(book_idx))
  val () = _info_render_row_from_sbuf(meta_id, TEXT_ADDED, 5, alen)
  prval pf_added = ADDED_ROW_DONE()

  (* Row 3: Last read *)
  val llen = _info_format_date_to_sbuf(library_get_last_opened(book_idx))
  val () = _info_render_row_from_sbuf(meta_id, TEXT_LAST_READ, 9, llen)
  prval pf_lr = LASTREAD_ROW_DONE()

  (* Row 4: Size *)
  val slen = _info_format_size_to_sbuf(library_get_file_size(book_idx))
  val () = _info_render_row_from_sbuf(meta_id, TEXT_SIZE, 4, slen)
  prval pf_sz = SIZE_ROW_DONE()

  (* Consume all 4 row proofs *)
  prval _ = pf_prog
  prval _ = pf_added
  prval _ = pf_lr
  prval _ = pf_sz

  (* Restart main stream for remaining steps *)
  val dom = ward_dom_init()
  val s = ward_dom_stream_begin(dom)
in (META_RENDERED() | s) end

(* Helper: add hide/unhide button in info view *)
fn _info_add_hide_btn {l:agz}
  (s: ward_dom_stream(l), actions_id: int, btn_id: int, vm: int)
  : ward_dom_stream(l) = let
  val s = ward_dom_stream_create_element(s, btn_id, actions_id, tag_button(), 6)
  val s = ward_dom_stream_set_attr_safe(s, btn_id, attr_class(), 5, cls_info_btn(), 8)
in
  if eq_int_int(vm, 0) then
    set_text_cstr(VT_27() | s, btn_id, 27, 4)    (* "Hide" *)
  else
    set_text_cstr(VT_28() | s, btn_id, 28, 6)    (* "Unhide" *)
end

(* Helper: add archive/unarchive button in info view *)
fn _info_add_arch_btn {l:agz}
  (s: ward_dom_stream(l), actions_id: int, btn_id: int, vm: int)
  : ward_dom_stream(l) = let
  val s = ward_dom_stream_create_element(s, btn_id, actions_id, tag_button(), 6)
  val s = ward_dom_stream_set_attr_safe(s, btn_id, attr_class(), 5, cls_info_btn(), 8)
in
  if eq_int_int(vm, 0) then
    set_text_cstr(VT_20() | s, btn_id, 20, 7)    (* "Archive" *)
  else
    set_text_cstr(VT_21() | s, btn_id, 21, 7)    (* "Restore" *)
end

(* Helper: conditionally add hide button *)
fn _info_maybe_hide {l:agz}
  (s: ward_dom_stream(l), show_hide: int, actions_id: int, btn_id: int, vm: int)
  : ward_dom_stream(l) =
  if eq_int_int(show_hide, 1) then _info_add_hide_btn(s, actions_id, btn_id, vm)
  else s

(* Helper: conditionally add archive button *)
fn _info_maybe_arch {l:agz}
  (s: ward_dom_stream(l), show_archive: int, actions_id: int, btn_id: int, vm: int)
  : ward_dom_stream(l) =
  if eq_int_int(show_archive, 1) then _info_add_arch_btn(s, actions_id, btn_id, vm)
  else s

(* Step 6: Render action buttons *)
fn _render_info_actions {l:agz}{vm,ss,sh,sa:int}
  (pf_btn: INFO_BUTTONS_VALID(vm, ss, sh, sa) |
   s: ward_dom_stream(l), overlay_id: int,
   vm: int(vm), show_hide: int(sh), show_archive: int(sa))
  : (INFO_ACTIONS_DONE() | ward_dom_stream(l)) = let
  prval _ = pf_btn
  val actions_id = dom_next_id()
  val s = ward_dom_stream_create_element(s, actions_id, overlay_id, tag_div(), 3)
  val s = ward_dom_stream_set_attr_safe(s, actions_id, attr_class(), 5, cls_info_actions(), 12)
  val hide_btn_id = dom_next_id()
  val s = _info_maybe_hide(s, show_hide, actions_id, hide_btn_id, vm)
  val arch_btn_id = dom_next_id()
  val s = _info_maybe_arch(s, show_archive, actions_id, arch_btn_id, vm)
  val del_btn_id = dom_next_id()
  val s = ward_dom_stream_create_element(s, del_btn_id, actions_id, tag_button(), 6)
  val s = ward_dom_stream_set_attr_safe(s, del_btn_id, attr_class(), 5, cls_info_btn_danger(), 15)
  val s = set_text_cstr(VT_41() | s, del_btn_id, 41, 6)
in (ACTIONS_RENDERED() | s) end

(* Consume all 6 render step proofs *)
fn _consume_info_proofs(
  pf_h: INFO_HEADER_DONE(), pf_c: INFO_COVER_DONE(),
  pf_t: INFO_TITLE_DONE(), pf_a: INFO_AUTHOR_DONE(),
  pf_m: INFO_META_DONE(), pf_act: INFO_ACTIONS_DONE()
): void = let
  prval HEADER_RENDERED() = pf_h
  prval COVER_RENDERED() = pf_c
  prval TITLE_RENDERED() = pf_t
  prval AUTHOR_RENDERED() = pf_a
  prval META_RENDERED() = pf_m
  prval ACTIONS_RENDERED() = pf_act
in end

(* ========== show_book_info ========== *)

implement show_book_info {vm,ss,sh,sa}
  (pf_btn | book_idx, root_id, vm, show_hide, show_archive) = let
  (* Dismiss existing overlays *)
  val () = dismiss_book_info()
  val () = dismiss_context_menu()

  (* Inject CSS — use root_id (node 0) as parent, not stale node 1 *)
  val () = inject_info_css(root_id)

  (* Build info overlay DOM *)
  val dom = ward_dom_init()
  val s = ward_dom_stream_begin(dom)

  val overlay_id = dom_next_id()
  val s = ward_dom_stream_create_element(s, overlay_id, root_id, tag_div(), 3)
  val s = ward_dom_stream_set_attr_safe(s, overlay_id, attr_class(), 5, cls_info_overlay(), 12)
  val () = _app_set_info_overlay_id(overlay_id)

  val has_cover = library_get_has_cover(book_idx)

  (* Step 1: Header *)
  val (pf_h | s) = _render_info_header(s, overlay_id)
  (* Step 2: Cover *)
  val (pf_c | s) = _render_info_cover(s, overlay_id, has_cover, book_idx)
  (* Step 3: Title *)
  val (pf_t | s) = _render_info_title(s, overlay_id, book_idx)
  (* Step 4: Author *)
  val (pf_a | s) = _render_info_author(s, overlay_id, book_idx)
  (* Step 5: Metadata *)
  val (pf_m | s) = _render_info_meta(s, overlay_id, book_idx)
  (* Step 6: Actions *)
  val (pf_act | s) = _render_info_actions(pf_btn | s, overlay_id, vm, show_hide, show_archive)

  (* Verify all steps completed *)
  val () = _consume_info_proofs(pf_h, pf_c, pf_t, pf_a, pf_m, pf_act)

  val dom = ward_dom_stream_end(s)
  val () = ward_dom_fini(dom)

  (* Register back button listener (first child button of header) *)
  val saved_bi = book_idx
  val saved_root = root_id
  val saved_vm = vm
  val saved_sh = show_hide
  val saved_sa = show_archive
  val () = ward_add_event_listener(
    overlay_id, evt_click(), 5, LISTENER_INFO_DISMISS,
    lam (_pl: int): int => let
      val () = dismiss_book_info()
    in 0 end
  )

  (* Register hide/unhide handler *)
  val () =
    if eq_int_int(saved_sh, 1) then
      ward_add_event_listener(
        overlay_id, evt_click(), 5, LISTENER_INFO_HIDE,
        lam (_pl: int): int => let
          val () = dismiss_book_info()
        in
          if eq_int_int(saved_vm, 0) then let
            val () = library_set_shelf_state(SHELF_HIDDEN() | saved_bi, 2)
            val () = library_save()
            val () = render_library(saved_root)
          in 0 end
          else let
            val () = library_set_shelf_state(SHELF_ACTIVE() | saved_bi, 0)
            val () = library_save()
            val () = render_library(saved_root)
          in 0 end
        end
      )
    else ()

  (* Register archive/unarchive handler *)
  val () =
    if eq_int_int(saved_sa, 1) then
      ward_add_event_listener(
        overlay_id, evt_click(), 5, LISTENER_INFO_ARCHIVE,
        lam (_pl: int): int => let
          val () = dismiss_book_info()
        in
          if eq_int_int(saved_vm, 0) then let
            val () = library_set_shelf_state(SHELF_ARCHIVED() | saved_bi, 1)
            val bi0 = g1ofg0(saved_bi)
            val cnt = library_get_count()
            val ok = check_book_index(bi0, cnt)
            val () = if eq_g1(ok, 1) then let
              val (pf_ba | biv) = _mk_book_access(saved_bi)
              val _ = epub_set_book_id_from_library(pf_ba | biv)
              val sc0 = library_get_spine_count(saved_bi)
              val sc = (if lte_g1(sc0, 256) then sc0 else 256): int
              val () = epub_delete_book_data(_checked_spine_count(sc))
            in end
            val () = library_save()
            val () = render_library(saved_root)
          in 0 end
          else let
            val () = library_set_shelf_state(SHELF_ACTIVE() | saved_bi, 0)
            val () = library_save()
            val () = render_library(saved_root)
          in 0 end
        end
      )
    else ()

  (* Register delete handler — opens delete confirmation modal *)
  val () = ward_add_event_listener(
    overlay_id, evt_click(), 5, LISTENER_INFO_DELETE,
    lam (_pl: int): int => let
      val () = dismiss_book_info()
      val () = render_delete_modal(saved_bi, saved_root)
    in 0 end
  )
in end
