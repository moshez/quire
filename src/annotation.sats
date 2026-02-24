(* annotation.sats — Highlight/annotation storage
 *
 * Annotations are stored separately from book content in IDB,
 * keyed by book content hash. Each annotation records a text
 * selection range (chapter + character offsets) with optional note.
 *
 * Functional correctness proofs:
 * - ANNOTATION_VALID: range is non-empty and chapter is within bounds
 * - ANNOT_SER_FORMAT: version↔header-bytes agreement
 *)

#define MAX_ANNOTATIONS 256

(* ========== Functional Correctness Dataprops ========== *)

(* ANNOTATION_VALID: proves the annotation range is valid.
 * chapter < total_chapters (in bounds)
 * start < end (non-empty range)
 * Both start and end are non-negative (character offsets). *)
dataprop ANNOTATION_VALID(chapter: int, start: int, end_off: int, total: int) =
  | {c,s,e,t:nat | s < e; c < t}
    ANNOTATION_OK(c, s, e, t)

(* Serialization format: version↔header size agreement.
 * v1: [u16 count][u16 version] = 4 bytes header *)
dataprop ANNOT_SER_FORMAT(version: int, header_bytes: int) =
  | ANNOT_FMT_V1(1, 4)

(* ========== Module Functions ========== *)

(* Initialize annotation module *)
fun annotation_init(): void

(* Get annotation count for the current book *)
fun annotation_get_count(): [n:nat | n <= 256] int(n)

(* Add an annotation. Requires room (count < 256) and valid range.
 * Returns new count. *)
fun annotation_add
  {c,s,e,t:nat | s < e; c < t; c < 256}
  (pf: ANNOTATION_VALID(c, s, e, t) |
   chapter: int(c), start_off: int(s), end_off: int(e),
   total_chapters: int(t)): void

(* Remove annotation at index *)
fun annotation_remove(idx: int): void

(* Get annotation fields by index *)
fun annotation_get_chapter(idx: int): int
fun annotation_get_start(idx: int): int
fun annotation_get_end(idx: int): int
fun annotation_get_timestamp(idx: int): int
