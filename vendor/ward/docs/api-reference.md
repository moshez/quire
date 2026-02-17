# API Reference

All functions are prefixed `ward_` for easy auditing. Types are abstract (`absvtype` / `abstype`) -- no raw pointer extraction is possible.

## memory -- Typed arrays and safe text

**Source:** `lib/memory.sats`

### Types

| Type | Kind | Description |
|------|------|-------------|
| `ward_arr(a, l, n)` | linear | Typed array of `n` elements of type `a` at address `l` |
| `ward_arr_frozen(a, l, n, k)` | linear | Frozen typed array, `k` outstanding borrows |
| `ward_arr_borrow(a, l, n)` | linear | Read-only borrow of typed array |
| `ward_safe_text(n)` | non-linear | Read-only text, `n` bytes, compile-time character verified |
| `ward_text_builder(n, filled)` | linear | Builder for safe text construction |

### Functions

#### Allocate / free

```ats
fun{a:t@ype} ward_arr_alloc {n:pos | n <= 1048576} (n: int n): [l:agz] ward_arr(a, l, n)
fun{a:t@ype} ward_arr_free {l:agz}{n:nat} (arr: ward_arr(a, l, n)): void
```

For allocations larger than 1MB, use arenas (see Arena section below).

#### Element access (bounds-checked)

```ats
fun{a:t@ype} ward_arr_get {l:agz}{n,i:nat | i < n} (arr: !ward_arr(a, l, n), i: int i): a
fun{a:t@ype} ward_arr_set {l:agz}{n,i:nat | i < n} (arr: !ward_arr(a, l, n), i: int i, v: a): void
```

#### Split / join

```ats
fun{a:t@ype} ward_arr_split {l:agz}{n,m:nat | m <= n}
  (arr: ward_arr(a, l, n), m: int m): @(ward_arr(a, l, m), ward_arr(a, l+m, n-m))

fun{a:t@ype} ward_arr_join {l:agz}{n,m:nat}
  (left: ward_arr(a, l, n), right: ward_arr(a, l+n, m)): ward_arr(a, l, n+m)
```

#### Freeze / thaw borrow protocol

```ats
fun{a:t@ype} ward_arr_freeze {l:agz}{n:nat}
  (arr: ward_arr(a, l, n)): @(ward_arr_frozen(a, l, n, 1), ward_arr_borrow(a, l, n))

fun{a:t@ype} ward_arr_thaw {l:agz}{n:nat}
  (frozen: ward_arr_frozen(a, l, n, 0)): ward_arr(a, l, n)

fun{a:t@ype} ward_arr_dup {l:agz}{n:nat}{k:pos}
  (frozen: !ward_arr_frozen(a, l, n, k) >> ward_arr_frozen(a, l, n, k+1),
   borrow: !ward_arr_borrow(a, l, n)): ward_arr_borrow(a, l, n)

fun{a:t@ype} ward_arr_drop {l:agz}{n:nat}{k:pos}
  (frozen: !ward_arr_frozen(a, l, n, k) >> ward_arr_frozen(a, l, n, k-1),
   borrow: ward_arr_borrow(a, l, n)): void
```

#### Read from borrow

```ats
fun{a:t@ype} ward_arr_read {l:agz}{n,i:nat | i < n}
  (borrow: !ward_arr_borrow(a, l, n), i: int i): a
```

#### Borrow split / join

```ats
fun{a:t@ype} ward_arr_borrow_split {l:agz}{n,m:nat | m <= n}{k:pos}
  (frozen: !ward_arr_frozen(a, l, n, k) >> ward_arr_frozen(a, l, n, k+1),
   borrow: ward_arr_borrow(a, l, n), m: int m)
  : @(ward_arr_borrow(a, l, m), ward_arr_borrow(a, l+m, n-m))

fun{a:t@ype} ward_arr_borrow_join {l:agz}{n,m:nat}{k:int | k > 1}
  (frozen: !ward_arr_frozen(a, l, n+m, k) >> ward_arr_frozen(a, l, n+m, k-1),
   left: ward_arr_borrow(a, l, n), right: ward_arr_borrow(a, l+n, m))
  : ward_arr_borrow(a, l, n+m)
```

#### Safe text

```ats
stadef SAFE_CHAR(c:int) =
  (c >= 97 && c <= 122) || (c >= 65 && c <= 90) || (c >= 48 && c <= 57) || c == 45

fun ward_text_build {n:pos} (n: int n): ward_text_builder(n, 0)
fun ward_text_putc {c:int | SAFE_CHAR(c)} {n:pos} {i:nat | i < n}
  (b: ward_text_builder(n, i), i: int i, c: int c): ward_text_builder(n, i+1)
fun ward_text_done {n:pos} (b: ward_text_builder(n, n)): ward_safe_text(n)
fun ward_safe_text_get {n,i:nat | i < n} (t: ward_safe_text(n), i: int i): byte
```

#### Utility

```ats
fun ward_int2byte(i: int): byte
```

#### Arena -- bulk allocation with token-tracked lifecycle

Arena arrays ARE `ward_arr` values -- all existing operations (get, set, freeze, thaw, split, join, borrow, read) work on arena-allocated arrays with zero duplication.

##### Types

| Type | Kind | Description |
|------|------|-------------|
| `ward_arena(l, max, k)` | linear | Arena for bulk allocation, `k` outstanding tokens |
| `ward_arena_token(la, l, n)` | linear | Witness linking each allocation to its arena |

##### Functions

```ats
fun ward_arena_create {max:pos | max <= 268435456}
  (max_size: int max): [l:agz] ward_arena(l, max, 0)

fun{a:t@ype} ward_arena_alloc {la:agz}{max:pos}{k:nat}{n:pos}
  (arena: !ward_arena(la, max, k) >> ward_arena(la, max, k+1), n: int n)
  : [l:agz] @(ward_arena_token(la, l, n), ward_arr(a, l, n))

fun{a:t@ype} ward_arena_return {la:agz}{max:pos}{k:pos}{l:agz}{n:pos}
  (arena: !ward_arena(la, max, k) >> ward_arena(la, max, k-1),
   token: ward_arena_token(la, l, n), arr: ward_arr(a, l, n)): void

fun ward_arena_destroy {l:agz}{max:nat}
  (arena: ward_arena(l, max, 0)): void
```

**Safety invariants:**
- Can't `ward_arr_free` arena arrays -- the token would be left unconsumed (linearity violation)
- Can't return the wrong array -- token and arr share the same existential `l` and `n`
- Can't split-and-cheat -- after `ward_arr_split`, pieces have different `n` than the token requires
- Can't destroy early -- `ward_arena_destroy` requires `k = 0`; outstanding tokens keep `k > 0`

---

## dom -- Type-safe DOM streaming

**Source:** `lib/dom.sats`

### Types

| Type | Kind | Description |
|------|------|-------------|
| `ward_dom_state(l)` | linear | DOM diff buffer at address `l` (256KB) |
| `ward_dom_stream(l)` | linear | Accumulates ops, auto-flushes when full |

### Functions

#### Lifecycle (2)

```ats
fun ward_dom_init (): [l:agz] ward_dom_state(l)
fun ward_dom_fini {l:agz} (state: ward_dom_state(l)): void
```

#### Stream lifecycle (2)

```ats
fun ward_dom_stream_begin {l:agz} (state: ward_dom_state(l)): [l2:agz] ward_dom_stream(l2)
fun ward_dom_stream_end {l:agz} (stream: ward_dom_stream(l)): [l2:agz] ward_dom_state(l2)
```

`stream_begin` consumes the state and resets the cursor. `stream_end` flushes remaining ops and returns the state.

#### Stream ops (5 core + 2 safe text variants)

```ats
fun ward_dom_stream_create_element {l:agz}{tl:pos | tl + 10 <= 262144}
  (stream: ward_dom_stream(l), node_id: int, parent_id: int,
   tag: ward_safe_text(tl), tag_len: int tl): ward_dom_stream(l)

fun ward_dom_stream_set_text {l:agz}{lb:agz}{tl:nat | tl + 7 <= 262144}
  (stream: ward_dom_stream(l), node_id: int,
   text: !ward_arr_borrow(byte, lb, tl), text_len: int tl): ward_dom_stream(l)

fun ward_dom_stream_set_attr {l:agz}{lb:agz}{nl:pos}{vl:nat | nl + vl + 8 <= 262144}
  (stream: ward_dom_stream(l), node_id: int,
   attr_name: ward_safe_text(nl), name_len: int nl,
   value: !ward_arr_borrow(byte, lb, vl), value_len: int vl): ward_dom_stream(l)

fun ward_dom_stream_set_style {l:agz}{lb:agz}{vl:nat | vl + 13 <= 262144}
  (stream: ward_dom_stream(l), node_id: int,
   value: !ward_arr_borrow(byte, lb, vl), value_len: int vl): ward_dom_stream(l)

fun ward_dom_stream_remove_children {l:agz}
  (stream: ward_dom_stream(l), node_id: int): ward_dom_stream(l)

fun ward_dom_stream_set_safe_text {l:agz}{tl:nat | tl + 7 <= 262144}
  (stream: ward_dom_stream(l), node_id: int,
   text: ward_safe_text(tl), text_len: int tl): ward_dom_stream(l)

fun ward_dom_stream_set_attr_safe {l:agz}{nl:pos}{vl:nat | nl + vl + 8 <= 262144}
  (stream: ward_dom_stream(l), node_id: int,
   attr_name: ward_safe_text(nl), name_len: int nl,
   value: ward_safe_text(vl), value_len: int vl): ward_dom_stream(l)
```

Each stream op auto-flushes the buffer if the next op would exceed the 256KB capacity. The compile-time constraint ensures a single op always fits in an empty buffer.

---

## promise -- Linear promises

**Source:** `lib/promise.sats`

### Datasort

```ats
datasort PromiseState = Pending | Resolved
```

### Types

| Type | Kind | Description |
|------|------|-------------|
| `ward_promise(a, s)` | linear | Promise indexed by `PromiseState` |
| `ward_promise_resolver(a)` | linear | Write-end, consumed by `resolve` |

Convenience aliases: `ward_promise_pending(a)` = `ward_promise(a, Pending)`, `ward_promise_resolved(a)` = `ward_promise(a, Resolved)`.

### Functions

```ats
(* Creation *)
fun{a:vt@ype} ward_promise_create (): @(ward_promise_pending(a), ward_promise_resolver(a))
fun{a:vt@ype} ward_promise_resolved (v: a): ward_promise_resolved(a)
fun{a:vt@ype} ward_promise_return (v: a): ward_promise_pending(a)

(* Resolution -- consumes the resolver *)
fun{a:vt@ype} ward_promise_resolve (r: ward_promise_resolver(a), v: a): void

(* Consumption *)
fun{a:vt@ype} ward_promise_extract (p: ward_promise_resolved(a)): a
fun{a:vt@ype} {s:PromiseState} ward_promise_discard (p: ward_promise(a, s)): void

(* Monadic bind -- linear closure, freed after invocation *)
fun{a:vt@ype}{b:vt@ype} ward_promise_then
  (p: ward_promise_pending(a), f: (a) -<lin,cloptr1> ward_promise_pending(b))
  : ward_promise_pending(b)
```

---

## event -- Timers and exit

**Source:** `lib/event.sats`

### Functions

```ats
fun ward_timer_set (delay_ms: int): ward_promise_pending(int)
fun ward_timer_fire (resolver_id: int): void = "ext#ward_timer_fire"   (* WASM export *)
fun ward_exit (): void = "mac#ward_exit"
```

---

## idb -- IndexedDB key-value storage

**Source:** `lib/idb.sats`

Keys are `ward_safe_text`, values are byte arrays via the borrow protocol.

### Functions

```ats
fun ward_idb_put {kn:pos}{lv:agz}{vn:nat}
  (key: ward_safe_text(kn), key_len: int kn,
   val_data: !ward_arr_borrow(byte, lv, vn), val_len: int vn)
  : ward_promise_pending(int)

fun ward_idb_get {kn:pos}
  (key: ward_safe_text(kn), key_len: int kn)
  : ward_promise_pending(int)

fun ward_idb_get_result {n:pos} (len: int n): [l:agz] ward_arr(byte, l, n)

fun ward_idb_delete {kn:pos}
  (key: ward_safe_text(kn), key_len: int kn)
  : ward_promise_pending(int)

(* WASM exports *)
fun ward_idb_fire (resolver_id: int, status: int): void = "ext#ward_idb_fire"
fun ward_idb_fire_get (resolver_id: int, data_len: int): void = "ext#ward_idb_fire_get"
```

---

## window -- Window/document bridge

**Source:** `lib/window.sats`

### Functions

```ats
fun ward_focus_window (): void
fun ward_get_visibility_state (): int    (* 0=hidden, 1=visible *)
fun ward_log {n:nat} (level: int, msg: ward_safe_text(n), msg_len: int n): void
```

Log levels: 0=debug, 1=info, 2=warn, 3=error.

---

## nav -- Navigation bridge

**Source:** `lib/nav.sats`

### Functions

```ats
fun ward_get_url {l:agz}{n:pos}
  (out: !ward_arr(byte, l, n), max_len: int n): int

fun ward_get_url_hash {l:agz}{n:pos}
  (out: !ward_arr(byte, l, n), max_len: int n): int

fun ward_set_url_hash {n:nat}
  (hash: ward_safe_text(n), hash_len: int n): void

fun ward_replace_state {n:nat}
  (url: ward_safe_text(n), url_len: int n): void

fun ward_push_state {n:nat}
  (url: ward_safe_text(n), url_len: int n): void
```

---

## dom_read -- DOM measurement and query

**Source:** `lib/dom_read.sats`

### Functions

```ats
fun ward_measure_node (node_id: int): int     (* 1=found, 0=not found *)
fun ward_measure_get_x (): int
fun ward_measure_get_y (): int
fun ward_measure_get_w (): int
fun ward_measure_get_h (): int
fun ward_measure_get_top (): int
fun ward_measure_get_left (): int
fun ward_query_selector {n:pos}
  (selector: ward_safe_text(n), selector_len: int n): int   (* node_id or -1 *)
```

---

## listener -- DOM event listeners

**Source:** `lib/listener.sats`

### Functions

```ats
fun ward_add_event_listener {tn:pos}
  (node_id: int, event_type: ward_safe_text(tn), type_len: int tn,
   listener_id: int, callback: int -<cloref1> int): void

fun ward_remove_event_listener (listener_id: int): void

fun ward_prevent_default (): void   (* must be called synchronously within callback *)

fun ward_event_get_payload {n:pos} (len: int n): [l:agz] ward_arr(byte, l, n)

(* WASM export *)
fun ward_on_event (listener_id: int, payload_len: int): void = "ext#ward_on_event"
```

---

## fetch -- Network fetch

**Source:** `lib/fetch.sats`

### Functions

```ats
fun ward_fetch {un:pos}
  (url: ward_safe_text(un), url_len: int un)
  : ward_promise_pending(int)     (* resolves with HTTP status *)

fun ward_fetch_get_body_len (): int
fun ward_fetch_get_body {n:pos} (len: int n): [l:agz] ward_arr(byte, l, n)

(* WASM export *)
fun ward_on_fetch_complete
  (resolver_id: int, status: int, body_len: int): void = "ext#ward_on_fetch_complete"
```

---

## clipboard -- Clipboard access

**Source:** `lib/clipboard.sats`

### Functions

```ats
fun ward_clipboard_write_text {n:nat}
  (text: ward_safe_text(n), text_len: int n)
  : ward_promise_pending(int)     (* 1=success, 0=failure *)

(* WASM export *)
fun ward_on_clipboard_complete
  (resolver_id: int, success: int): void = "ext#ward_on_clipboard_complete"
```

---

## file -- File I/O (user-selected files)

**Source:** `lib/file.sats`

### Functions

```ats
fun ward_file_open (input_node_id: int): ward_promise_pending(int)
fun ward_file_get_size (): int
fun ward_file_read {l:agz}{n:pos}
  (handle: int, file_offset: int, out: !ward_arr(byte, l, n), len: int n): int
fun ward_file_close (handle: int): void

(* WASM export *)
fun ward_on_file_open
  (resolver_id: int, handle: int, size: int): void = "ext#ward_on_file_open"
```

---

## decompress -- Decompression

**Source:** `lib/decompress.sats`

### Functions

```ats
fun ward_decompress {lb:agz}{n:pos}
  (data: !ward_arr_borrow(byte, lb, n), data_len: int n, method: int)
  : ward_promise_pending(int)     (* method: 0=gzip, 1=deflate, 2=deflate-raw *)

fun ward_decompress_get_len (): int
fun ward_blob_read {l:agz}{n:pos}
  (handle: int, blob_offset: int, out: !ward_arr(byte, l, n), len: int n): int
fun ward_blob_free (handle: int): void

(* WASM export *)
fun ward_on_decompress_complete
  (resolver_id: int, handle: int, decompressed_len: int): void = "ext#ward_on_decompress_complete"
```

---

## notify -- Notifications and push

**Source:** `lib/notify.sats`

### Functions

```ats
fun ward_notification_request_permission ()
  : ward_promise_pending(int)     (* 1=granted, 0=denied *)

fun ward_notification_show {tn:pos}
  (title: ward_safe_text(tn), title_len: int tn): void

fun ward_push_subscribe {vn:pos}
  (vapid: ward_safe_text(vn), vapid_len: int vn)
  : ward_promise_pending(int)     (* resolves with JSON length *)

fun ward_push_get_result {n:pos} (len: int n): [l:agz] ward_arr(byte, l, n)

fun ward_push_get_subscription ()
  : ward_promise_pending(int)     (* resolves with JSON length *)

(* WASM exports *)
fun ward_on_permission_result
  (resolver_id: int, granted: int): void = "ext#ward_on_permission_result"
fun ward_on_push_subscribe
  (resolver_id: int, json_len: int): void = "ext#ward_on_push_subscribe"
```
