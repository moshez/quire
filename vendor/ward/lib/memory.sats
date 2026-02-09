(* memory.sats -- Ward: linear memory safety library *)
(* Typed arrays with linear ownership — no raw pointers. *)

(* ============================================================
   Types
   ============================================================ *)

absvtype ward_arr(a:t@ype, l:addr, n:int)
absvtype ward_arr_frozen(a:t@ype, l:addr, n:int, k:int)
absvtype ward_arr_borrow(a:t@ype, l:addr, n:int)

(* ============================================================
   Allocate / free
   ============================================================ *)

fun{a:t@ype}
ward_arr_alloc
  {n:pos}
  (n: int n)
  : [l:agz] ward_arr(a, l, n)

fun{a:t@ype}
ward_arr_free
  {l:agz}{n:nat}
  (arr: ward_arr(a, l, n))
  : void

(* ============================================================
   Element access (bounds-checked)
   ============================================================ *)

fun{a:t@ype}
ward_arr_get
  {l:agz}{n,i:nat | i < n}
  (arr: !ward_arr(a, l, n), i: int i)
  : a

fun{a:t@ype}
ward_arr_set
  {l:agz}{n,i:nat | i < n}
  (arr: !ward_arr(a, l, n), i: int i, v: a)
  : void

(* ============================================================
   Split / join (sub-array with size tracking)
   ============================================================ *)

fun{a:t@ype}
ward_arr_split
  {l:agz}{n,m:nat | m <= n}
  (arr: ward_arr(a, l, n), m: int m)
  : @(ward_arr(a, l, m), ward_arr(a, l+m, n-m))

fun{a:t@ype}
ward_arr_join
  {l:agz}{n,m:nat}
  (left: ward_arr(a, l, n), right: ward_arr(a, l+n, m))
  : ward_arr(a, l, n+m)

(* ============================================================
   Freeze / thaw borrow protocol
   ============================================================ *)

fun{a:t@ype}
ward_arr_freeze
  {l:agz}{n:nat}
  (arr: ward_arr(a, l, n))
  : @(ward_arr_frozen(a, l, n, 1), ward_arr_borrow(a, l, n))

fun{a:t@ype}
ward_arr_thaw
  {l:agz}{n:nat}
  (frozen: ward_arr_frozen(a, l, n, 0))
  : ward_arr(a, l, n)

fun{a:t@ype}
ward_arr_dup
  {l:agz}{n:nat}{k:pos}
  (frozen: !ward_arr_frozen(a, l, n, k) >> ward_arr_frozen(a, l, n, k+1),
   borrow: !ward_arr_borrow(a, l, n))
  : ward_arr_borrow(a, l, n)

fun{a:t@ype}
ward_arr_drop
  {l:agz}{n:nat}{k:pos}
  (frozen: !ward_arr_frozen(a, l, n, k) >> ward_arr_frozen(a, l, n, k-1),
   borrow: ward_arr_borrow(a, l, n))
  : void

(* ============================================================
   Read from borrow (bounds-checked)
   ============================================================ *)

fun{a:t@ype}
ward_arr_read
  {l:agz}{n,i:nat | i < n}
  (borrow: !ward_arr_borrow(a, l, n), i: int i)
  : a

(* ============================================================
   Borrow split / join
   ============================================================ *)

fun{a:t@ype}
ward_arr_borrow_split
  {l:agz}{n,m:nat | m <= n}{k:pos}
  (frozen: !ward_arr_frozen(a, l, n, k) >> ward_arr_frozen(a, l, n, k+1),
   borrow: ward_arr_borrow(a, l, n), m: int m)
  : @(ward_arr_borrow(a, l, m), ward_arr_borrow(a, l+m, n-m))

fun{a:t@ype}
ward_arr_borrow_join
  {l:agz}{n,m:nat}{k:int | k > 1}
  (frozen: !ward_arr_frozen(a, l, n+m, k) >> ward_arr_frozen(a, l, n+m, k-1),
   left: ward_arr_borrow(a, l, n), right: ward_arr_borrow(a, l+n, m))
  : ward_arr_borrow(a, l, n+m)

(* ============================================================
   Safe text — compile-time character verification
   ============================================================ *)

(* A character is safe if it is alphanumeric or hyphen *)
stadef SAFE_CHAR (c:int) =
  (c >= 97 && c <= 122)       (* a-z *)
  || (c >= 65 && c <= 90)     (* A-Z *)
  || (c >= 48 && c <= 57)     (* 0-9 *)
  || c == 45                  (* - *)

abstype ward_safe_text (n:int) = ptr
absvtype ward_text_builder (n:int, filled:int)

fun ward_text_build
  {n:pos}
  (n: int n)
  : ward_text_builder(n, 0)

fun ward_text_putc
  {c:int | SAFE_CHAR(c)} {n:pos} {i:nat | i < n}
  (b: ward_text_builder(n, i), i: int i, c: int c)
  : ward_text_builder(n, i+1)

fun ward_text_done
  {n:pos}
  (b: ward_text_builder(n, n))
  : ward_safe_text(n)

fun ward_safe_text_get
  {n,i:nat | i < n}
  (t: ward_safe_text(n), i: int i)
  : byte

(* ============================================================
   Utility — int to byte conversion (freestanding)
   ============================================================ *)

fun ward_int2byte(i: int): byte
