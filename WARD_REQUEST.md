# Ward Upstream Change Requests

This document requests changes to the [ward](https://github.com/example/ward) library
so that quire (and other ward-based apps) can use ward as-is without modifying
`vendor/ward/`. Each section includes a concrete diff.

**Motivation**: Quire is a PWA e-reader built on ward. A planned messaging app
will also use ward. Both need these features.

---

## 1. Unstub ward_bridge.mjs

**Status**: Already done in quire's vendored copy. Requesting upstream incorporation.

All stub functions in `ward_bridge.mjs` have been replaced with real browser
implementations. This includes:

- `wardJsFocusWindow` -> `window.focus()`
- `wardJsGetVisibilityState` -> `document.visibilityState === 'hidden' ? 1 : 0`
- `wardJsGetUrl` / `wardJsGetUrlHash` / `wardJsSetUrlHash` -> `location` API
- `wardJsReplaceState` / `wardJsPushState` -> `history` API
- `wardJsMeasureNode` -> `getBoundingClientRect()` + scroll dimensions
- `wardJsQuerySelector` -> `document.querySelector()`
- `wardJsAddEventListener` / `wardJsRemoveEventListener` -> standard DOM events
- `wardJsPreventDefault` -> `event.preventDefault()`
- `wardJsFetch` -> `fetch()` API
- `wardJsClipboardWriteText` -> `navigator.clipboard.writeText()`
- `wardJsFileOpen` / `wardJsFileRead` / `wardJsFileClose` -> `File` API
- `wardJsDecompress` -> `DecompressionStream` API
- `wardJsBlobRead` / `wardJsBlobFree` -> cached `ArrayBuffer` management
- `wardJsNotification*` / `wardJsPush*` -> Notification + PushManager APIs

**Diff**: See quire's `vendor/ward/lib/ward_bridge.mjs` for the complete
implementation. The changes are too large for inline diff but follow a
consistent pattern: each stub is replaced with its standard Web API equivalent.

---

## 2. parseHTML Bridge Function

**Status**: Already done in quire's vendored copy. Requesting upstream incorporation.

**Use cases**:
- E-reader: Parse EPUB chapter XHTML at import time, store parsed tree binary
- Messaging: Parse link preview HTML safely

**Function**: `wardJsParseHtml(htmlPtr, htmlLen)` -> returns tree binary length

**Tree binary format** (flat SAX stream, little-endian):
```
ELEMENT_OPEN  (0x01): tag_len:u8  tag:bytes  attr_count:u8
  [attr_name_len:u8  attr_name:bytes  attr_value_len:u16LE  attr_value:bytes]...
TEXT          (0x03): text_len:u16LE  text:bytes
ELEMENT_CLOSE (0x02): (no payload)
```

**Filtering rules** (in `serializeTree`):
- Elements: skip `script`, `iframe`, `object`, `embed`, `form`, `input`, `link`, `meta`
- Attributes: keep only names matching `/^[a-zA-Z0-9-]+$/` AND not `style` AND not `/^on/`

**WASM-side support**:
- `ward_parse_html_stash(ptr)` -> C function to stash result pointer
- Exported from WASM for bridge to call after malloc + copy

---

## 3. REMOVE_CHILD Diff Opcode

**Current state**: `ward_bridge.mjs` already handles opcode 5 (REMOVE_CHILD) but
`dom.sats` does not declare it. Only `REMOVE_CHILDREN` (opcode 3, clears ALL
children) is exposed in the ATS2 API.

**Use case**: Settings modal, TOC overlay, and other UI panels need to remove a
specific child node by ID without clearing all siblings.

### Diff: dom.sats

```diff
 dataprop WARD_DOM_OPCODE(int) =
   | WARD_DOM_OP_SET_TEXT(1)
   | WARD_DOM_OP_SET_ATTR(2)
   | WARD_DOM_OP_REMOVE_CHILDREN(3)
   | WARD_DOM_OP_CREATE_ELEMENT(4)
+  | WARD_DOM_OP_REMOVE_CHILD(5)

+(* Remove a specific child node by ID *)
+fun ward_dom_remove_child
+  {l:agz}
+  (state: !ward_dom_state(l), node_id: int): void
```

### Diff: dom.dats

```diff
+(* Remove a specific child node *)
+implement ward_dom_remove_child{l}(state, node_id) = let
+  val total_len = 5  (* 1 opcode + 4 node_id *)
+  val () = ward_set_byte(state, 0, 5)  (* REMOVE_CHILD *)
+  val () = ward_set_i32(state, 1, node_id)
+  val () = _ward_dom_flush(state, total_len)
+in end
```

---

## 4. `ward_text_from_bytes` - Runtime-Validated Safe Text Constructor

**Current state**: `ward_safe_text` can only be built character-by-character via
`ward_text_build` / `ward_text_putc` / `ward_text_done`, where each character is
verified against `SAFE_CHAR` at compile time.

**Problem**: When rendering pre-parsed HTML trees (from parseHTML), tag and
attribute names are bytes in a binary buffer. The app must look up each name
in a table of pre-built `ward_safe_text` constants. With ~100 HTML/SVG/MathML
tags and ~40 attributes, this requires ~140 hand-written `ward_safe_text`
builders.

**Proposed solution**: A runtime-validated constructor that checks each byte
against `SAFE_CHAR` and returns `Option(ward_safe_text(n))`.

### Diff: memory.sats

```diff
+(* Runtime-validated safe text construction.
+ * Checks each byte in the array against SAFE_CHAR.
+ * Returns Some(safe_text) if all bytes are safe, None otherwise. *)
+fun ward_text_from_bytes
+  {lb:agz}{n:pos}
+  (src: !ward_arr_borrow(byte, lb, n), len: int n): Option(ward_safe_text(n))
```

### Diff: memory.dats

```diff
+implement ward_text_from_bytes{lb}{n}(src, len) = let
+  fun loop{i:nat | i <= n}(src: !ward_arr_borrow(byte, lb, n), i: int i): bool =
+    if i = len then true
+    else let
+      val c = ward_arr_borrow_get(src, i)
+      val cv = byte2int(c)
+      val safe = (cv >= 97 andalso cv <= 122)   (* a-z *)
+              orelse (cv >= 65 andalso cv <= 90) (* A-Z *)
+              orelse (cv >= 48 andalso cv <= 57) (* 0-9 *)
+              orelse cv = 45                     (* - *)
+    in
+      if safe then loop(src, i + 1)
+      else false
+    end
+  val all_safe = loop(src, 0)
+in
+  if all_safe then let
+    val builder = ward_text_build(len)
+    (* Copy each validated byte *)
+    val text = _ward_text_from_validated(src, len)
+  in
+    Some(text)
+  end
+  else None()
+end
```

(The exact implementation may use an internal `_ward_text_from_validated` that
constructs `ward_safe_text` from already-validated bytes without re-checking.)

---

## 5. XML Tree Data Structure

**Current state**: Ward has no XML/HTML tree representation. Quire's `xml.dats`
implements its own tree with `datavtype` and `castfn` for pointer management.

**Proposed**: A `ward_xml_node` absvtype with traversal functions, suitable for
representing parsed HTML/XML trees in WASM memory.

### New file: xml.sats

```ats
(* ward_xml_node - Linear ownership tree node *)
absvtype ward_xml_node(l:addr)

(* Tree traversal *)
fun ward_xml_first_child{l:agz}(node: !ward_xml_node(l)): [l2:addr] ward_xml_node(l2)
fun ward_xml_next_sibling{l:agz}(node: !ward_xml_node(l)): [l2:addr] ward_xml_node(l2)
fun ward_xml_is_null{l:addr}(node: !ward_xml_node(l)): bool(l == null)

(* Node inspection *)
fun ward_xml_is_element{l:agz}(node: !ward_xml_node(l)): bool
fun ward_xml_tag_name{l:agz}(node: !ward_xml_node(l), buf: ptr, max: int): int
fun ward_xml_get_attr{l:agz}(node: !ward_xml_node(l), name: ptr, name_len: int, buf: ptr, max: int): int
fun ward_xml_get_text{l:agz}(node: !ward_xml_node(l), buf: ptr, max: int): int

(* Lifecycle *)
fun ward_xml_free{l:addr}(node: ward_xml_node(l)): void
```

This is lower priority than items 1-4. The current `xml.dats` castfn approach
works but isn't ideal.

---

## 6. loadWard Extension Point

**Current state**: `loadWard(wasmBytes, root, opts)` accepts an `opts` parameter
but there's no documented way to inject app-specific WASM imports.

**Use case**: Quire needs `ward_parse_html_stash` as an additional WASM export
that the bridge calls. Other apps may need similar app-specific exports.

### Diff: ward_bridge.mjs

```diff
 export async function loadWard(wasmBytes, root, opts) {
+  const extraImports = opts?.extraImports || {};
   // ... existing import construction ...
-  const importObject = { env: { ...wardImports } };
+  const importObject = { env: { ...wardImports, ...extraImports } };
```

This allows apps to inject additional WASM imports without modifying the bridge:
```javascript
await loadWard(bytes, root, {
  extraImports: {
    ward_parse_html_stash: (ptr) => { stashedPtr = ptr; }
  }
});
```

---

## 7. Event Payload Encoding

**Current state**: `wardJsAddEventListener` in the bridge converts DOM events to
binary payloads written to WASM memory before calling `ward_on_event`. The
encoding varies by event type.

**Request**: Document the standard encoding for each event type so that
ward-based apps can reliably decode event payloads:

| Event type | Payload format |
|-----------|---------------|
| `click` | `[f64:clientX] [f64:clientY] [i32:target_node_id]` |
| `keydown`/`keyup` | `[u8:keyCode] [u8:flags(shift,ctrl,alt,meta)]` |
| `input` | `[u16:value_len] [bytes:value]` |
| `scroll` | `[f64:scrollTop] [f64:scrollLeft]` |
| `resize` | `[f64:width] [f64:height]` |
| `touchstart`/`touchend` | `[f64:clientX] [f64:clientY] [i32:identifier]` |

Currently this encoding is implicit in the bridge code. Making it a documented
part of ward's contract would let apps write type-safe decoders.

---

## Priority

1. **High**: Unstub bridge (#1) + parseHTML (#2) — already implemented, just needs upstream merge
2. **High**: REMOVE_CHILD opcode (#3) — small diff, needed by any app with dynamic UI
3. **Medium**: ward_text_from_bytes (#4) — enables efficient HTML tree rendering
4. **Medium**: loadWard extension point (#6) — small diff, high value
5. **Low**: Event payload docs (#7) — documentation only
6. **Low**: XML tree structure (#5) — nice-to-have, workaround exists
