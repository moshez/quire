(* sha256.dats — Pure ATS2 SHA-256 implementation
 *
 * Uses synthesized XOR/USHR/ROTR from available bitwise ops
 * (band, bor, bsl, bsr in arith.sats).
 *
 * No C code, no $UNSAFE, no %{ blocks.
 *)

#define ATS_DYNLOADFLAG 0

#include "share/atspre_staload.hats"
staload "./../vendor/ward/lib/memory.sats"
staload _ = "./../vendor/ward/lib/memory.dats"
staload "./sha256.sats"
staload "./arith.sats"

(* file.sats for ward_file_read *)
staload "./../vendor/ward/lib/file.sats"

(* ========== Bitwise helpers ========== *)

(* XOR synthesized: (a|b) - (a&b). See ward#20 for native support.
 * Proof: for each bit, OR-AND difference is exactly the bits that differ. *)
fn bxor(a: int, b: int): int =
  sub_int_int(bor_int_int(a, b), band_int_int(a, b))

(* 0xFFFFFFFF — all 32 bits set, used as mask.
 * Computed as -1 in two's complement (avoids 1<<32 which overflows i32). *)
fn _mask32_val(): int = sub_int_int(0, 1)

(* Unsigned right shift: mask away sign-extension bits from arithmetic shift.
 * Valid for n in {2,3,6,7,10,11,13,17,18,19,22,25} — all SHA-256 shift amounts,
 * where 1 << (32-n) fits in positive signed i32. *)
fn ushr(x: int, n: int): int =
  band_int_int(bsr_int_int(x, n),
    sub_int_int(bsl_int_int(1, sub_int_int(32, n)), 1))

(* Right rotate 32-bit *)
fn rotr(x: int, n: int): int =
  bor_int_int(ushr(x, n),
    band_int_int(bsl_int_int(x, sub_int_int(32, n)), _mask32_val()))

(* Mask to 32 bits — keeps values in i32 range *)
fn mask32(x: int): int = band_int_int(x, _mask32_val())

(* ========== SHA-256 round constants K[0..63] ========== *)

fn sha256_k(i: int): int =
  if eq_int_int(i, 0) then 1116352408
  else if eq_int_int(i, 1) then 1899447441
  else if eq_int_int(i, 2) then sub_int_int(0, 1245643825)  (* 3049323471 *)
  else if eq_int_int(i, 3) then sub_int_int(0, 373957723)   (* 3921009573 *)
  else if eq_int_int(i, 4) then 961987163
  else if eq_int_int(i, 5) then 1508970993
  else if eq_int_int(i, 6) then sub_int_int(0, 1841331548)  (* 2453635748 *)
  else if eq_int_int(i, 7) then sub_int_int(0, 1424204075)  (* 2870763221 *)
  else if eq_int_int(i, 8) then sub_int_int(0, 670586216)   (* 3624381080 *)
  else if eq_int_int(i, 9) then 310598401
  else if eq_int_int(i, 10) then 607225278
  else if eq_int_int(i, 11) then 1426881987
  else if eq_int_int(i, 12) then 1925078388
  else if eq_int_int(i, 13) then sub_int_int(0, 2132889090) (* 2162078206 *)
  else if eq_int_int(i, 14) then sub_int_int(0, 1680079193) (* 2614888103 *)
  else if eq_int_int(i, 15) then sub_int_int(0, 1046744716) (* 3248222580 *)
  else if eq_int_int(i, 16) then sub_int_int(0, 459576895)  (* 3835390401 *)
  else if eq_int_int(i, 17) then sub_int_int(0, 272742522)  (* 4022224774 *)
  else if eq_int_int(i, 18) then 264347078
  else if eq_int_int(i, 19) then 604807628
  else if eq_int_int(i, 20) then 770255983
  else if eq_int_int(i, 21) then 1249150122
  else if eq_int_int(i, 22) then 1555081692
  else if eq_int_int(i, 23) then 1996064986
  else if eq_int_int(i, 24) then sub_int_int(0, 1740746414) (* 2554220882 *)
  else if eq_int_int(i, 25) then sub_int_int(0, 1473132947) (* 2821834349 *)
  else if eq_int_int(i, 26) then sub_int_int(0, 1341970488) (* 2952996808 *)
  else if eq_int_int(i, 27) then sub_int_int(0, 1084653625) (* 3210313671 *)
  else if eq_int_int(i, 28) then sub_int_int(0, 958395405)  (* 3336571891 *)
  else if eq_int_int(i, 29) then sub_int_int(0, 710438585)  (* 3584528711 *)
  else if eq_int_int(i, 30) then 113926993
  else if eq_int_int(i, 31) then 338241895
  else if eq_int_int(i, 32) then 666307205
  else if eq_int_int(i, 33) then 773529912
  else if eq_int_int(i, 34) then 1294757372
  else if eq_int_int(i, 35) then 1396182291
  else if eq_int_int(i, 36) then 1695183700
  else if eq_int_int(i, 37) then 1986661051
  else if eq_int_int(i, 38) then sub_int_int(0, 2117940946) (* 2177026350 *)
  else if eq_int_int(i, 39) then sub_int_int(0, 1838011235) (* 2456956037 *)
  else if eq_int_int(i, 40) then sub_int_int(0, 1564481375) (* 2730485921 *)
  else if eq_int_int(i, 41) then sub_int_int(0, 1474664885) (* 2820302411 *)
  else if eq_int_int(i, 42) then sub_int_int(0, 1035236496) (* 3259730800 *)
  else if eq_int_int(i, 43) then sub_int_int(0, 949202525)  (* 3345764771 *)
  else if eq_int_int(i, 44) then sub_int_int(0, 778901479)  (* 3516065817 *)
  else if eq_int_int(i, 45) then sub_int_int(0, 694614492)  (* 3600352804 *)
  else if eq_int_int(i, 46) then sub_int_int(0, 200395387)  (* 4094571909 *)
  else if eq_int_int(i, 47) then 275423344
  else if eq_int_int(i, 48) then 430227734
  else if eq_int_int(i, 49) then 506948616
  else if eq_int_int(i, 50) then 659060556
  else if eq_int_int(i, 51) then 883997877
  else if eq_int_int(i, 52) then 958139571
  else if eq_int_int(i, 53) then 1322822218
  else if eq_int_int(i, 54) then 1537002063
  else if eq_int_int(i, 55) then 1747873779
  else if eq_int_int(i, 56) then 1955562222
  else if eq_int_int(i, 57) then 2024104815
  else if eq_int_int(i, 58) then sub_int_int(0, 2067236844) (* 2227730452 *)
  else if eq_int_int(i, 59) then sub_int_int(0, 1933114872) (* 2361852424 *)
  else if eq_int_int(i, 60) then sub_int_int(0, 1866530822) (* 2428436474 *)
  else if eq_int_int(i, 61) then sub_int_int(0, 1538233109) (* 2756734187 *)
  else if eq_int_int(i, 62) then sub_int_int(0, 1090935817) (* 3204031479 *)
  else (* i = 63 *) sub_int_int(0, 965641998)               (* 3329325298 *)

(* ========== SHA-256 functions ========== *)

(* Ch(x,y,z) = (x AND y) XOR ((NOT x) AND z) *)
fn sha256_ch(x: int, y: int, z: int): int =
  bxor(band_int_int(x, y),
       band_int_int(bxor(x, _mask32_val()), z))

(* Maj(x,y,z) = (x AND y) XOR (x AND z) XOR (y AND z) *)
fn sha256_maj(x: int, y: int, z: int): int =
  bxor(bxor(band_int_int(x, y), band_int_int(x, z)),
       band_int_int(y, z))

(* Sigma0(x) = ROTR2(x) XOR ROTR13(x) XOR ROTR22(x) *)
fn sha256_sigma0(x: int): int =
  bxor(bxor(rotr(x, 2), rotr(x, 13)), rotr(x, 22))

(* Sigma1(x) = ROTR6(x) XOR ROTR11(x) XOR ROTR25(x) *)
fn sha256_sigma1(x: int): int =
  bxor(bxor(rotr(x, 6), rotr(x, 11)), rotr(x, 25))

(* sigma0(x) = ROTR7(x) XOR ROTR18(x) XOR SHR3(x) *)
fn sha256_lsigma0(x: int): int =
  bxor(bxor(rotr(x, 7), rotr(x, 18)), ushr(x, 3))

(* sigma1(x) = ROTR17(x) XOR ROTR19(x) XOR SHR10(x) *)
fn sha256_lsigma1(x: int): int =
  bxor(bxor(rotr(x, 17), rotr(x, 19)), ushr(x, 10))

(* ========== Ward arr int helpers ========== *)

fn _ai {l:agz}{n:pos}
  (a: !ward_arr(int, l, n), off: int, cap: int n): int =
  ward_arr_get<int>(a, _ward_idx(off, cap))

fn _wi {l:agz}{n:pos}
  (a: !ward_arr(int, l, n), off: int, v: int, cap: int n): void =
  ward_arr_set<int>(a, _ward_idx(off, cap), v)

(* ========== Block compression ========== *)

(* Process one 64-byte block. Reads 64 bytes starting at block_off in data_arr,
 * expands to 64 message schedule words in W, runs 64 compression rounds,
 * and updates H[0..7]. *)
fn sha256_compress {ld:agz}{nd:pos}{lw:agz}{lh:agz}
  (data: !ward_arr(byte, ld, nd), data_cap: int nd, block_off: int,
   w: !ward_arr(int, lw, 64), h: !ward_arr(int, lh, 8)): void = let

  (* Read 16 big-endian 32-bit words from the block *)
  fun read_words {ld:agz}{nd:pos}{lw:agz}
    (data: !ward_arr(byte, ld, nd), w: !ward_arr(int, lw, 64),
     i: int, boff: int, dcap: int nd): void =
    if gte_int_int(i, 16) then ()
    else let
      val off = boff + i * 4
      val b0 = byte2int0(ward_arr_get<byte>(data, _ward_idx(off, dcap)))
      val b1 = byte2int0(ward_arr_get<byte>(data, _ward_idx(off + 1, dcap)))
      val b2 = byte2int0(ward_arr_get<byte>(data, _ward_idx(off + 2, dcap)))
      val b3 = byte2int0(ward_arr_get<byte>(data, _ward_idx(off + 3, dcap)))
      val word = bor_int_int(bor_int_int(bsl_int_int(b0, 24), bsl_int_int(b1, 16)),
                             bor_int_int(bsl_int_int(b2, 8), b3))
      val () = _wi(w, i, word, 64)
    in read_words(data, w, i + 1, boff, dcap) end

  val () = read_words(data, w, 0, block_off, data_cap)

  (* Expand to 64 message schedule words *)
  fun expand {lw:agz}
    (w: !ward_arr(int, lw, 64), i: int): void =
    if gte_int_int(i, 64) then ()
    else let
      val s0 = sha256_lsigma0(_ai(w, i - 15, 64))
      val s1 = sha256_lsigma1(_ai(w, i - 2, 64))
      val v = mask32(mask32(_ai(w, i - 16, 64) + s0) + mask32(_ai(w, i - 7, 64) + s1))
      val () = _wi(w, i, v, 64)
    in expand(w, i + 1) end

  val () = expand(w, 16)

  (* Run 64 compression rounds *)
  fun rounds {lw:agz}{lh:agz}
    (w: !ward_arr(int, lw, 64), h: !ward_arr(int, lh, 8),
     i: int, a: int, b: int, c: int, d: int,
     e: int, f: int, g: int, hh: int): void =
    if gte_int_int(i, 64) then let
      (* Add compressed values back to H *)
      val () = _wi(h, 0, mask32(_ai(h, 0, 8) + a), 8)
      val () = _wi(h, 1, mask32(_ai(h, 1, 8) + b), 8)
      val () = _wi(h, 2, mask32(_ai(h, 2, 8) + c), 8)
      val () = _wi(h, 3, mask32(_ai(h, 3, 8) + d), 8)
      val () = _wi(h, 4, mask32(_ai(h, 4, 8) + e), 8)
      val () = _wi(h, 5, mask32(_ai(h, 5, 8) + f), 8)
      val () = _wi(h, 6, mask32(_ai(h, 6, 8) + g), 8)
      val () = _wi(h, 7, mask32(_ai(h, 7, 8) + hh), 8)
    in end
    else let
      val s1 = sha256_sigma1(e)
      val ch = sha256_ch(e, f, g)
      val temp1 = mask32(mask32(hh + s1) + mask32(ch + mask32(sha256_k(i) + _ai(w, i, 64))))
      val s0 = sha256_sigma0(a)
      val mj = sha256_maj(a, b, c)
      val temp2 = mask32(s0 + mj)
    in rounds(w, h, i + 1,
        mask32(temp1 + temp2), a, b, c,
        mask32(d + temp1), e, f, g) end

  val a0 = _ai(h, 0, 8) val b0 = _ai(h, 1, 8)
  val c0 = _ai(h, 2, 8) val d0 = _ai(h, 3, 8)
  val e0 = _ai(h, 4, 8) val f0 = _ai(h, 5, 8)
  val g0 = _ai(h, 6, 8) val h0 = _ai(h, 7, 8)

in rounds(w, h, 0, a0, b0, c0, d0, e0, f0, g0, h0) end

(* ========== Hex output ========== *)

fn hex_digit(v: int): int =
  if lt_int_int(v, 10) then v + 48 (* '0' = 48 *)
  else v + 87 (* 'a' = 97, 97 - 10 = 87 *)

(* Write 8 hex chars for one 32-bit word to output at position pos *)
fn write_hex_word {lo:agz}
  (out: !ward_arr(byte, lo, 64), pos: int, word: int): void = let
  fun loop {lo:agz}
    (out: !ward_arr(byte, lo, 64), p: int, w: int, i: int): void =
    if gte_int_int(i, 8) then ()
    else let
      val shift = mul_int_int(sub_int_int(7, i), 4)
      val nibble = band_int_int(ushr(w, shift), 15)
      val () = ward_arr_set<byte>(out, _ward_idx(p + i, 64),
        ward_int2byte(_checked_byte(hex_digit(nibble))))
    in loop(out, p, w, i + 1) end
in loop(out, pos, word, 0) end

(* ========== Main hash function ========== *)

implement sha256_file_hash {l}{sz} (handle, file_size, out) = let
  (* Initialize hash state H0..H7 *)
  val h = ward_arr_alloc<int>(8)
  val () = _wi(h, 0, 1779033703, 8)
  val () = _wi(h, 1, sub_int_int(0, 1150833019), 8)  (* 3144134277 *)
  val () = _wi(h, 2, 1013904242, 8)
  val () = _wi(h, 3, sub_int_int(0, 1521486534), 8)  (* 2773480762 *)
  val () = _wi(h, 4, 1359893119, 8)
  val () = _wi(h, 5, sub_int_int(0, 1694144372), 8)  (* 2600822924 *)
  val () = _wi(h, 6, 528734635, 8)
  val () = _wi(h, 7, 1541459225, 8)

  (* Message schedule W[0..63] *)
  val w = ward_arr_alloc<int>(64)

  (* Read buffer — 4096 bytes for chunked file reading *)
  val rbuf = ward_arr_alloc<byte>(4096)

  (* Process all complete 64-byte blocks from the file.
   * We read 4096 bytes at a time, then process 64-byte blocks within.
   *
   * Termination proof: process_file uses remaining:int(rem) with
   * termination metric .<rem>. proc_blocks returns HASH_PROGRESS:
   * - HASH_ADVANCED(c): consumed c > 0 bytes → rem decreases
   * - HASH_DONE(0): no blocks fit → return immediately
   * The ATS2 type checker verifies rem' < rem on every recursive call. *)

  (* proc_blocks: process complete 64-byte blocks in a chunk.
   * Returns (HASH_PROGRESS(c) | int(c)) where c is bytes consumed.
   * If no complete block fits (chunk < 64), returns (HASH_DONE | 0).
   * If >= 1 block processed, returns (HASH_ADVANCED | c) with c > 0. *)
  fun proc_blocks {lr:agz}{lw:agz}{lh:agz}
    (rbuf: !ward_arr(byte, lr, 4096),
     w: !ward_arr(int, lw, 64), h: !ward_arr(int, lh, 8),
     boff: int, chunk_sz: int): [c:nat] (HASH_PROGRESS(c) | int(c)) =
    if gt_int_int(boff + 64, chunk_sz) then let
      val boff_n = _checked_nat(boff)
    in
      if gt_g1(boff_n, 0) then (HASH_ADVANCED() | boff_n)
      else (HASH_DONE() | 0)
    end
    else let
      val () = sha256_compress(rbuf, 4096, boff, w, h)
    in proc_blocks(rbuf, w, h, boff + 64, chunk_sz) end

  fun process_file {lr:agz}{lw:agz}{lh:agz}{rem:nat} .<rem>.
    (handle: int, rbuf: !ward_arr(byte, lr, 4096),
     w: !ward_arr(int, lw, 64), h: !ward_arr(int, lh, 8),
     file_off: int, file_size: int, remaining: int(rem),
     total_processed: int): int =
    if lte_g1(remaining, 0) then total_processed
    else let
      val chunk = if gt_int_int(remaining, 4096) then 4096 else remaining
      val _rd = ward_file_read(handle, file_off, rbuf, 4096)
      val (pf_progress | consumed) = proc_blocks(rbuf, w, h, 0, chunk)
    in
      if eq_g1(consumed, 0) then let
        (* No complete blocks fit → terminate. *)
        prval HASH_DONE() = pf_progress
      in total_processed end
      else let
        (* consumed > 0 proven by HASH_ADVANCED → rem - c < rem (termination metric).
         * consumed <= remaining because consumed <= chunk <= remaining.
         * lte_g1 provides the c <= rem constraint to the solver. *)
        prval HASH_ADVANCED() = pf_progress
      in
        if lte_g1(consumed, remaining) then
          process_file(handle, rbuf, w, h, file_off + consumed, file_size,
                       sub_g1(remaining, consumed), total_processed + consumed)
        else total_processed (* unreachable: consumed <= chunk <= remaining *)
      end
    end

  val file_sz = _checked_nat(file_size)
  val total_blocks_bytes = process_file(handle, rbuf, w, h, 0, file_size, file_sz, 0)

  (* Now handle the final partial block + padding.
   * We need to read whatever remains after the last complete block. *)
  val tail_len = file_size - total_blocks_bytes

  (* Read the tail into a padding buffer (max 128 bytes: 64 tail + 64 padding) *)
  val pbuf = ward_arr_alloc<byte>(128)

  (* Zero the padding buffer *)
  fun zero_pbuf {lp:agz}
    (pbuf: !ward_arr(byte, lp, 128), i: int): void =
    if gte_int_int(i, 128) then ()
    else let
      val () = ward_arr_set<byte>(pbuf, _ward_idx(i, 128),
        ward_int2byte(_checked_byte(0)))
    in zero_pbuf(pbuf, i + 1) end
  val () = zero_pbuf(pbuf, 0)

  (* Copy tail bytes from file to pbuf, then append 0x80 *)
  fun copy_tail {lr:agz}{lp:agz}
    (rbuf: !ward_arr(byte, lr, 4096), pbuf: !ward_arr(byte, lp, 128),
     i: int, n: int): void =
    if gte_int_int(i, n) then ()
    else let
      val b = byte2int0(ward_arr_get<byte>(rbuf, _ward_idx(i, 4096)))
      val () = ward_arr_set<byte>(pbuf, _ward_idx(i, 128),
        ward_int2byte(_checked_byte(band_int_int(b, 255))))
    in copy_tail(rbuf, pbuf, i + 1, n) end

  (* Always read — harmless if tail_len is 0 since copy_tail stops at 0 *)
  val _rd = ward_file_read(handle, total_blocks_bytes, rbuf, 4096)
  val tl: int = if gt_int_int(tail_len, 64) then 64 else tail_len
  val () = copy_tail(rbuf, pbuf, 0, tl)

  (* Append 0x80 byte *)
  val () = ward_arr_set<byte>(pbuf, _ward_idx(tail_len, 128),
    ward_int2byte(_checked_byte(128)))

  (* Determine if we need one or two final blocks.
   * If tail_len + 1 + 8 > 64, we need two blocks. *)
  val need_two = gt_int_int(tail_len + 9, 64)

  (* Write 64-bit big-endian bit length at end of last block.
   * bit_length = file_size * 8 *)
  val bit_len_pos: int = if need_two then 120 else 56
  (* file_size * 8 as big-endian 64-bit at bit_len_pos.
   * We split into high and low 32-bit words.
   * high_bits = file_size >> 29 (top 3 bits of file_size become bits 32-34)
   * low_bits = (file_size << 3) & 0xFFFFFFFF *)
  val high_bits = ushr(file_size, 29)
  val low_bits = mask32(bsl_int_int(file_size, 3))

  (* Write big-endian 64-bit bit-length at position p in pbuf *)
  fn _wb_len {lp:agz}
    (pb: !ward_arr(byte, lp, 128), p: int, hi: int, lo: int): void = let
    val () = ward_arr_set<byte>(pb, _ward_idx(p, 128),
      ward_int2byte(_checked_byte(band_int_int(ushr(hi, 24), 255))))
    val () = ward_arr_set<byte>(pb, _ward_idx(add_int_int(p, 1), 128),
      ward_int2byte(_checked_byte(band_int_int(ushr(hi, 16), 255))))
    val () = ward_arr_set<byte>(pb, _ward_idx(add_int_int(p, 2), 128),
      ward_int2byte(_checked_byte(band_int_int(ushr(hi, 8), 255))))
    val () = ward_arr_set<byte>(pb, _ward_idx(add_int_int(p, 3), 128),
      ward_int2byte(_checked_byte(band_int_int(hi, 255))))
    val () = ward_arr_set<byte>(pb, _ward_idx(add_int_int(p, 4), 128),
      ward_int2byte(_checked_byte(band_int_int(ushr(lo, 24), 255))))
    val () = ward_arr_set<byte>(pb, _ward_idx(add_int_int(p, 5), 128),
      ward_int2byte(_checked_byte(band_int_int(ushr(lo, 16), 255))))
    val () = ward_arr_set<byte>(pb, _ward_idx(add_int_int(p, 6), 128),
      ward_int2byte(_checked_byte(band_int_int(ushr(lo, 8), 255))))
    val () = ward_arr_set<byte>(pb, _ward_idx(add_int_int(p, 7), 128),
      ward_int2byte(_checked_byte(band_int_int(lo, 255))))
  in end

  val () = _wb_len(pbuf, bit_len_pos, high_bits, low_bits)

  (* Process padding blocks: 1 or 2 blocks depending on tail length *)
  val nblocks: int = if need_two then 2 else 1
  fun proc_pad {lp:agz}{lw:agz}{lh:agz}
    (pb: !ward_arr(byte, lp, 128), ww: !ward_arr(int, lw, 64),
     hh: !ward_arr(int, lh, 8), i: int, n: int): void =
    if gte_int_int(i, n) then ()
    else let
      val () = sha256_compress(pb, 128, mul_int_int(i, 64), ww, hh)
    in proc_pad(pb, ww, hh, add_int_int(i, 1), n) end
  val () = proc_pad(pbuf, w, h, 0, nblocks)

  (* Write hex output: 8 words * 8 hex chars = 64 chars *)
  fun write_hex {lo:agz}{lh:agz}
    (out: !ward_arr(byte, lo, 64), h: !ward_arr(int, lh, 8), i: int): void =
    if gte_int_int(i, 8) then ()
    else let
      val () = write_hex_word(out, i * 8, _ai(h, i, 8))
    in write_hex(out, h, i + 1) end

  val () = write_hex(out, h, 0)

  (* Free working arrays *)
  val () = ward_arr_free<byte>(pbuf)
  val () = ward_arr_free<byte>(rbuf)
  val () = ward_arr_free<int>(w)
  val () = ward_arr_free<int>(h)

in end
