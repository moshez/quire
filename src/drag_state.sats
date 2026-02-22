(* drag_state.sats — single source of truth for drag state proof.
 * Shared by app_state.sats, reader.sats, and static_tests.dats via staload.
 *
 * DRAG_STATE_VALID(d) proves d is 0 (idle) or 1 (active).
 * Required on the setter — no bypass path. *)
dataprop DRAG_STATE_VALID(d: int) =
  | DRAG_IDLE(0)
  | DRAG_ACTIVE(1)
