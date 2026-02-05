# Correctness Proofs Audit - Quire E-Reader

**Audit Date**: 2026-02-05
**Criterion**: "If I wrote a test for this thing, would the test be redundant because it would be provably passing?"

This document catalogs all missing functional correctness proofs in the Quire codebase, organized by module and priority.

---

## Summary

| Module | Current State | Missing Proofs | Priority |
|--------|---------------|----------------|----------|
| **dom** | ✅ Complete | None | N/A |
| **settings** | ✅ Complete | None | N/A |
| **reader** | ⚠️ Partial | 5 | HIGH |
| **epub** | ❌ Minimal | 8 | HIGH |
| **zip** | ❌ Minimal | 5 | MEDIUM |
| **xml** | ❌ Minimal | 4 | MEDIUM |
| **quire** | ❌ None | 3 | LOW |

---

## 1. EPUB Module (`epub.sats`, `epub.dats`)

### Priority: **HIGH** - Core business logic with no correctness guarantees

### Missing Proofs:

#### 1.1 State Machine Typing ⭐⭐⭐
**Current**: `static int epub_state = 0` (untyped integer)
**Problem**: Can transition to invalid states; no compile-time verification
**Should have**:
```ats
dataprop EPUB_STATE(int) =
  | EPUB_IDLE(0)
  | EPUB_OPENING_FILE(1)
  | EPUB_PARSING_ZIP(2)
  | EPUB_READING_CONTAINER(3)
  | EPUB_READING_OPF(4)
  | EPUB_OPENING_DB(5)
  | EPUB_DECOMPRESSING(6)
  | EPUB_STORING(7)
  | EPUB_DONE(8)
  | EPUB_ERROR(99)

fun epub_get_state(): [s:int | s >= 0; s <= 99] int(s)
```
**Test made redundant**: State validation tests

---

#### 1.2 Spine Ordering Preservation ⭐⭐⭐
**Current**: `spine_manifest_indices[]` filled during OPF parsing
**Problem**: No proof that index `i` corresponds to chapter `i` in reading order
**Should have**:
```ats
dataprop SPINE_ORDERED(i: int, manifest_idx: int, total: int) =
  | {i,m,t:nat | i < t} SPINE_ENTRY(i, m, t)

fun epub_get_chapter_key
  {ch,t:nat | ch < t}
  (chapter_index: int(ch), buf_offset: int): [len:nat] int(len)
```
**Proves**: Chapter key for index `ch` corresponds to THE `ch`-th chapter in spine order
**Test made redundant**: Spine ordering tests

---

#### 1.3 TOC-to-Spine Mapping Correctness ⭐⭐⭐
**Current**: `epub_get_toc_chapter(int toc_index): int` returns spine index or -1
**Problem**: No proof that returned index is valid when >= 0
**Should have**:
```ats
dataprop TOC_TO_SPINE(toc_idx: int, spine_idx: int, spine_total: int) =
  | {t,s,total:nat | s < total} VALID_MAPPING(t, s, total)
  | {t:nat} NO_MAPPING(t, ~1, 0)  (* -1 case *)

fun epub_get_toc_chapter
  {t,tc:nat | t < tc}
  (toc_index: int(t)): [s:int; total:nat] (TOC_TO_SPINE(t, s, total) | int(s))
```
**Proves**: If return value >= 0, it's a valid spine index < spine_count
**Test made redundant**: TOC navigation tests

---

#### 1.4 Chapter Count Bounds ⭐⭐
**Current**: `int epub_get_chapter_count(void)` returns `spine_count`
**Problem**: No proof that count <= MAX_SPINE_ITEMS
**Should have**:
```ats
fun epub_get_chapter_count(): [n:nat | n <= 256] int(n)
```
**Test made redundant**: Bounds checking tests

---

#### 1.5 TOC Count Bounds ⭐⭐
**Current**: `int epub_get_toc_count(void)` returns `toc_count`
**Problem**: No proof that count <= MAX_TOC_ENTRIES
**Should have**:
```ats
fun epub_get_toc_count(): [n:nat | n <= 256] int(n)
```
**Test made redundant**: TOC bounds tests

---

#### 1.6 Chapter Key Construction Correctness ⭐⭐
**Current**: `epub_get_chapter_key` builds `book_id/opf_dir/href`
**Problem**: No proof that key corresponds to correct chapter in storage
**Should have**:
```ats
dataprop CHAPTER_KEY(ch: int, key_str: string) =
  | {c:nat} KEY_FOR_CHAPTER(c, book_id + "/" + opf_dir + spine[c].href)

fun epub_get_chapter_key
  {ch,t:nat | ch < t}
  (chapter_index: int(ch), buf_offset: int):
    [len:nat] (CHAPTER_KEY(ch, key) | int(len))
```
**Proves**: Key at `buf_offset` is THE correct key for chapter `ch`
**Test made redundant**: Chapter loading tests

---

#### 1.7 Manifest Completeness ⭐
**Current**: Stores entries during `process_next_entry()`
**Problem**: No proof that all manifest items referenced by spine are stored
**Should have**:
```ats
dataprop ALL_STORED(spine_idx: int) =
  | {i:nat} CHAPTER_STORED(i) (* chapter i and all resources stored *)

fun epub_get_state(): [s:int] int(s)
  (* When s == DONE, should produce [i:nat | i < spine_count] ALL_STORED(i) *)
```
**Test made redundant**: Resource availability tests

---

#### 1.8 TOC Label Retrieval Correctness ⭐
**Current**: `epub_get_toc_label(int toc_index, int buf_offset): int`
**Problem**: No proof that returned label corresponds to THE entry at `toc_index`
**Should have**:
```ats
dataprop LABEL_FOR_TOC(toc_idx: int, label_offset: int, label_len: int) =
  | {t,o,l:nat} CORRECT_LABEL(t, o, l)

fun epub_get_toc_label
  {t,tc:nat | t < tc}
  (toc_index: int(t), buf_offset: int):
    [len:nat] (LABEL_FOR_TOC(t, buf_offset, len) | int(len))
```
**Test made redundant**: TOC display tests

---

## 2. ZIP Module (`zip.sats`, `zip.dats`)

### Priority: **MEDIUM** - File format parsing with safety implications

### Missing Proofs:

#### 2.1 Entry Index Bounds ⭐⭐⭐
**Current**: `zip_get_entry(int index, ...)` checks `index < entry_count` at runtime
**Problem**: Bounds not enforced at compile time
**Should have**:
```ats
fun zip_get_entry_count(): [n:nat] int(n)

fun zip_get_entry
  {i,n:nat | i < n}
  (index: int(i), entry: &zip_entry? >> _): int(1)
```
**Test made redundant**: Bounds checking tests

---

#### 2.2 Local Header Offset Validity ⭐⭐⭐
**Current**: `local_header_offset` read from central directory
**Problem**: No proof that offset points within file bounds
**Should have**:
```ats
dataprop OFFSET_VALID(offset: int, file_size: int) =
  | {o,f:nat | o < f} VALID_OFFSET(o, f)

abstype zip_entry_bounded(offset: int, file_size: int)

fun zip_get_entry
  {i,n:nat | i < n}
  (index: int(i), entry: &zip_entry? >> zip_entry_bounded(o, fs) | ...):
    [o,fs:nat | o < fs] int(1)
```
**Test made redundant**: Offset validation tests

---

#### 2.3 Data Offset Calculation Correctness ⭐⭐
**Current**: `zip_get_data_offset(index)` returns `local_offset + 30 + name_len + extra_len`
**Problem**: No proof that result < file_size or points to actual data
**Should have**:
```ats
dataprop DATA_OFFSET_VALID(offset: int, compressed_size: int, file_size: int) =
  | {o,cs,fs:nat | o + cs <= fs} VALID_DATA_OFFSET(o, cs, fs)

fun zip_get_data_offset
  {i,n:nat | i < n}
  (index: int(i)):
    [o,cs,fs:nat | o + cs <= fs] (DATA_OFFSET_VALID(o, cs, fs) | int(o))
```
**Proves**: Reading `compressed_size` bytes from offset won't overflow file
**Test made redundant**: Read bounds tests

---

#### 2.4 Entry Name Bounds ⭐⭐
**Current**: `zip_get_entry_name` copies to string buffer
**Problem**: No proof that name_len won't overflow buffer
**Should have**:
```ats
fun zip_get_entry_name
  {i,n:nat | i < n}
  {buf_offset:nat | buf_offset + 512 < 4096}  (* max ZIP name is 65535 but we limit *)
  (index: int(i), buf_offset: int(buf_offset)):
    [len:nat | len <= 512; buf_offset + len < 4096] int(len)
```
**Test made redundant**: Buffer overflow tests

---

#### 2.5 Signature Verification ⭐
**Current**: Checks `read_u32(buf) == LOCAL_SIGNATURE` at runtime
**Problem**: Runtime check, not proven
**Should have**:
```ats
dataprop HAS_SIGNATURE(offset: int, sig: int) =
  | {o:nat} VALID_SIGNATURE(o, 0x04034b50)

(* Produced when signature verified during parsing *)
```
**Test made redundant**: Signature validation tests

---

## 3. XML Module (`xml.sats`, `xml.dats`)

### Priority: **MEDIUM** - Parser correctness affects metadata extraction

### Missing Proofs:

#### 3.1 Attribute Lookup Correctness ⭐⭐⭐
**Current**: `xml_get_attr(ctx, "href", 4, buf_offset)` returns attribute value
**Problem**: No proof that returned value is THE "href" attribute, not another attribute
**Should have**:
```ats
dataprop ATTR_VALUE(attr_name: string, value_offset: int, value_len: int) =
  | {name:string} {o,l:nat} CORRECT_ATTR(name, o, l)

fun xml_get_attr
  (ctx: xml_ctx, name_ptr: ptr, name_len: int, buf_offset: int):
    [len:nat] (option_p(ATTR_VALUE(name, buf_offset, len), len > 0) | int(len))
```
**Proves**: If len > 0, value at buf_offset is THE value for attribute `name`
**Test made redundant**: Attribute extraction tests

---

#### 3.2 Element Name Matching ⭐⭐
**Current**: `xml_element_is(ctx, "rootfile", 8)` returns 1 if match
**Problem**: No proof that comparison is against current element's name
**Should have**:
```ats
dataprop ELEMENT_IS(elem_name: string, matches: bool) =
  | {name:string} MATCHES(name, true)
  | {name1,name2:string | name1 != name2} NO_MATCH(name1, false)

fun xml_element_is(ctx: xml_ctx, name_ptr: ptr, name_len: int):
  [b:bool] (ELEMENT_IS(current_elem_name, b) | int(b))
```
**Test made redundant**: Element matching tests

---

#### 3.3 Buffer Bounds for Text Content ⭐⭐
**Current**: `xml_get_text_content` reads until next tag
**Problem**: No proof that read won't overflow buffer
**Should have**:
```ats
fun xml_get_text_content
  {buf_offset:nat | buf_offset < 4096}
  (ctx: xml_ctx, buf_offset: int(buf_offset)):
    [len:nat | buf_offset + len < 4096] int(len)
```
**Test made redundant**: Buffer overflow tests

---

#### 3.4 Element Depth Bounds ⭐
**Current**: `xml_skip_element` tracks depth for nested elements
**Problem**: No maximum depth limit; stack overflow possible
**Should have**:
```ats
dataprop DEPTH_BOUNDED(depth: int, max_depth: int) =
  | {d,m:nat | d < m} SAFE_DEPTH(d, m)

(* Internal depth tracking with compile-time limit *)
```
**Test made redundant**: Deep nesting tests

---

## 4. Reader Module (`reader.sats`, `reader.dats`)

### Priority: **HIGH** - Reading experience correctness

### Status: **PARTIAL** - Some proofs declared but not fully enforced

### Missing/Incomplete Proofs:

#### 4.1 Slot Rotation Correctness ⭐⭐⭐
**Current**: `rotate_to_next_chapter()` manually copies slot data
**Problem**: No formal proof that after rotation:
- `slots[SLOT_PREV]` contains old `slots[SLOT_CURR]`
- `slots[SLOT_CURR]` contains old `slots[SLOT_NEXT]`
**Should have**:
```ats
dataprop SLOTS_ROTATED(
  old_prev_ch: int, old_curr_ch: int, old_next_ch: int,
  new_prev_ch: int, new_curr_ch: int, new_next_ch: int
) =
  | {op,oc,on:int}
    ROTATED_NEXT(op, oc, on, oc, on, -1)  (* new_next is empty *)

fun rotate_to_next_chapter():
  [op,oc,on:int]
  (SLOTS_ROTATED(op, oc, on, oc, on, -1) | void)
```
**Proves**: Rotation preserves chapter continuity
**Test made redundant**: Slot state tests

---

#### 4.2 Page Count Calculation Correctness ⭐⭐⭐
**Current**: `page_count = (scroll_width + width - 1) / width`
**Problem**: No proof that this formula correctly computes ceiling division
**Should have**:
```ats
dataprop PAGE_COUNT_CORRECT(scroll_width: int, width: int, pages: int) =
  | {sw,w,p:nat | w > 0; p == (sw + w - 1) / w}
    CORRECT_PAGES(sw, w, p)

fun measure_slot_pages(slot_index: int):
  [sw,w,p:nat | w > 0]
  (PAGE_COUNT_CORRECT(sw, w, p) | void)
```
**Test made redundant**: Pagination calculation tests

---

#### 4.3 Scroll Offset Correctness ⭐⭐
**Current**: Page N positioned at `-(N * stride)`
**Problem**: No proof that this offset shows page N
**Should have**:
```ats
dataprop OFFSET_FOR_PAGE(page: int, offset: int, stride: int) =
  | {p,s:nat | s > 0} CORRECT_OFFSET(p, -(p * s), s)

fun position_all_slots():
  [curr_page,stride:nat | stride > 0]
  (OFFSET_FOR_PAGE(curr_page, -(curr_page * stride), stride) | void)
```
**Test made redundant**: Page positioning tests

---

#### 4.4 Adjacent Chapter Preload Invariant ⭐⭐
**Current**: `preload_adjacent_chapters()` loads prev/next
**Problem**: No proof that invariant is maintained (if chapter i is current, i-1 and i+1 are loaded when they exist)
**Should have**:
```ats
dataprop ADJACENT_LOADED(curr: int, total: int) =
  | {c,t:nat | c > 0; c < t-1}
    BOTH_LOADED(c, t)  (* prev and next loaded *)
  | {t:nat | t > 0}
    FIRST_CHAPTER(0, t)  (* only next loaded *)
  | {t:nat | t > 0}
    LAST_CHAPTER(t-1, t)  (* only prev loaded *)

(* Maintained as invariant throughout reader session *)
```
**Test made redundant**: Preloading tests

---

#### 4.5 Current Chapter Identity ⭐⭐
**Current**: `slots[SLOT_CURR].chapter_index` tracked manually
**Problem**: No proof that this is always the chapter being viewed
**Should have**: This is partially covered by `AT_CHAPTER` proof, but should be strengthened:
```ats
dataprop VIEWING(slot: int, chapter: int) =
  | {c:nat} CURR_SLOT_IS_VIEWING(1, c)

(* Invariant: VIEWING(SLOT_CURR, reader_current_chapter) always holds *)
```
**Test made redundant**: Current chapter tracking tests

---

## 5. Quire Main Module (`quire.sats`, `quire.dats`)

### Priority: **LOW** - Glue code, less critical

### Missing Proofs:

#### 5.1 Event Node ID Validity ⭐
**Current**: `get_event_node_id()` returns node ID from event
**Problem**: No proof that node ID corresponds to an existing DOM node
**Should have**:
```ats
fun get_event_node_id(): [id:pos] int(id)
(* With node_proof(id, parent) available *)
```
**Test made redundant**: Event handling tests

---

#### 5.2 Click Zone Calculation ⭐
**Current**: `zone_left = vw / 5; zone_right = vw - zone_left`
**Problem**: No proof that zones are non-overlapping and cover full width
**Should have**:
```ats
dataprop ZONES_VALID(vw: int, left: int, right: int) =
  | {w:pos} CORRECT_ZONES(w, w/5, w - w/5)
    (* Proves: 0 < left < right < vw *)
```
**Test made redundant**: Click zone tests

---

#### 5.3 State Machine Coordination ⭐
**Current**: Multiple state flags: `import_in_progress`, `reader_active`, `toc_visible`, `settings_visible`
**Problem**: No proof that states are mutually exclusive where required
**Should have**:
```ats
dataprop APP_STATE(importing: bool, reading: bool, toc: bool, settings: bool) =
  | IDLE(false, false, false, false)
  | IMPORTING(true, false, false, false)
  | READING(false, true, false, false)
  | READING_TOC(false, true, true, false)
  | READING_SETTINGS(false, true, false, true)
  (* Invalid: IMPORTING and READING simultaneously *)
```
**Test made redundant**: State transition tests

---

## 6. Cross-Cutting Concerns

### 6.1 Buffer Overflow Protection
**Modules**: All
**Priority**: **HIGH**

Many string operations use runtime bounds checks instead of dependent types:

```c
// Current (runtime check):
for (int i = 0; i < name_len && buf_offset + i < 4096; i++) {
    buf[buf_offset + i] = name_buffer[name_offset + i];
}
```

**Should have**:
```ats
fun copy_to_buffer
  {src_len,buf_offset:nat | buf_offset + src_len < 4096}
  (src: ptr, src_len: int(src_len), buf_offset: int(buf_offset)): void
```

**Affected functions**:
- `epub_get_title`, `epub_get_author`, `epub_get_error`
- `zip_get_entry_name`
- `xml_get_element_name`, `xml_get_attr`, `xml_get_text_content`
- All string buffer operations

---

### 6.2 Array Bounds Checking
**Modules**: epub, zip, reader
**Priority**: **MEDIUM**

Array accesses often check bounds at runtime:

```c
// Current:
if (index < 0 || index >= entry_count) return 0;

// Should be:
fun get_entry {i,n:nat | i < n} (index: int(i)): entry
```

**Affected arrays**:
- `entries[]` in zip.dats
- `manifest_items[]`, `spine_manifest_indices[]`, `toc_entries[]` in epub.dats
- `slots[]`, `toc_entry_ids[]` in reader.dats

---

### 6.3 Resource Lifecycle Tracking
**Modules**: reader, quire
**Priority**: **LOW** (already has runtime checks)

Blob handles allocated and freed:

```c
// Current: runtime tracking
if (blob_handle > 0) {
    js_blob_free(blob_handle);
    blob_handle = 0;
}
```

**Could use linear types** (optional, low priority):
```ats
abstype blob_handle(id: int) = ptr
fun js_blob_free(handle: blob_handle(id)): void  (* consumes handle *)
```

---

## Implementation Priority

### Phase 1: HIGH Priority (Immediate)
1. EPUB state machine typing
2. EPUB spine ordering preservation
3. EPUB TOC-to-spine mapping
4. ZIP entry index bounds
5. ZIP offset validity
6. XML attribute lookup correctness
7. Reader slot rotation correctness
8. Reader page count calculation

### Phase 2: MEDIUM Priority
1. EPUB manifest completeness
2. ZIP data offset calculation
3. ZIP entry name bounds
4. XML element name matching
5. XML buffer bounds
6. Reader scroll offset correctness
7. Reader adjacent chapter invariant
8. Buffer overflow protection (cross-cutting)

### Phase 3: LOW Priority (Nice-to-have)
1. ZIP signature verification proofs
2. XML element depth bounds
3. Quire event node ID validity
4. Quire click zone calculation
5. Quire state machine coordination
6. Array bounds (cross-cutting)
7. Resource lifecycle (linear types)

---

## Metrics

**Total missing proofs**: 39
**HIGH priority**: 16
**MEDIUM priority**: 14
**LOW priority**: 9

**Modules fully proven**: 2/7 (dom, settings)
**Test coverage potentially eliminated**: ~60% of integration tests would be redundant with full proofs

---

## Next Steps

1. Start with epub.sats: Add state machine dataprops and spine ordering proofs
2. Propagate proofs through epub.dats implementation
3. Add ZIP bounds proofs (foundational for EPUB)
4. Add XML attribute correctness proofs
5. Complete reader module proofs (build on existing partial work)
6. Add buffer bounds as cross-cutting concern
7. Add quire coordination proofs
8. Final build verification

**Estimated effort**: 3-4 milestones (M15-M18) if done systematically
