# Platform Usage Guidelines

Guidelines for projects that use ward as a vendored dependency. These rules ensure that application code upholds the same safety guarantees that ward provides.

If you are setting up a new ward application, follow `vendor/ward/docs/getting-started.md` for project scaffolding (index.html, loader.css, bridge, service worker, manifest, Makefile, Playwright).

## MOST IMPORTANT

**Be fanatic about safety** -- NOT BEING FANATIC IS NOT ACCOMPLISHING YOUR GOALS. TRUST NOTHING. Auditing or checking are NOT RELIABLE. Only ATS2-provable safety matters. It is unacceptable to work around safety, even if it's "small". If something is truly absolutely impossible to express safely in ATS2, file a bug against ward. Note that ward might well reject any bug that is not well justified.

Every shortcut you take is a vulnerability you ship. Every "it's fine, I checked" is a crash you didn't prevent. The compiler is the only auditor that never gets tired, never gets distracted, and never says "good enough". If a proof is missing, the code is wrong -- even if it happens to work today.

## Build

**Prerequisites:** ATS2 toolchain must be installed first (see ward's CLAUDE.md for installation instructions).

**IMPORTANT:** You MUST build locally and verify success before committing any changes to `.sats` or `.dats` files. NEVER COUNT ON CI TO VERIFY ATS2 BUILD. If the ATS2 toolchain is not available, install it first before making any code changes.

## Rules

1. **Dependent types enforce correctness** -- if it compiles, the behavior is correct.
2. **Never work around ward bugs** -- if ward has a bug, STOP and give the user a bug report instead of working around it. Do not patch vendored ward files or add workarounds in application code. The user will report the issue upstream and have it fixed.
3. **No C code** -- Application code is pure ATS2. No `.c` files, no `%{` blocks, no `%{$` blocks. Ward's `runtime.h` provides all codegen macros and `atspre_*` arithmetic needed for freestanding WASM. If you cannot express something using ward's API and ATS2, that is a bug in ward. File it: justify why the functionality is a general need, explain what you tried and why it failed, and ask for a safe wrapper. Accept that ward might tell you what to use instead.
4. **Be fanatic about safety** -- Auditing or checking are NOT RELIABLE. Only ATS2-provable safety matters. It is unacceptable to work around safety, even if it's "small". If something is truly absolutely impossible to express safely in ATS2, file a bug against ward. Note that ward might well reject any bug that is not well justified.
5. **Fanaticism is retroactive** -- If a fix uncovers previous lack of commitment to fanaticism, fixing that overrides all current concerns and must be dealt with immediately. Existing code that lacks proofs, uses magic numbers, or has dead code is not "consistent with existing patterns" -- it is a deficiency that must be corrected when discovered. "But it was already like that" is never an excuse. The debt stops accruing NOW.

## Type Safety Requirements

**All functionality must be proven correct using ATS2's type system.**

The goal is **functional correctness**, not just safety. Prove that code *does the right thing*, not merely that it *doesn't crash*.

### Functional Correctness Examples

Use dataprops to encode relationships that guarantee correct behavior:

```ats
(* Lookup: prove the returned entry corresponds to the queried key *)
dataprop MAPS(key: int, value_idx: int) =
  | {k,i:nat} ENTRY_FOR(k, i)  (* key k maps to value index i *)

fun lookup {k:int}
  (key: int(k)): [i:int] (MAPS(k, i) | int(i))

(* Navigation: prove we land on the requested target *)
dataprop AT_TARGET(int) =
  | {t:nat} VIEWING(t)

fun go_to {target:nat}
  (t: int(target)): (AT_TARGET(target) | void)
```

### Safety as a Byproduct

Functional correctness proofs often imply safety, but safety alone is insufficient:

- Bounded array access proves you read *the correct element*, not just *some valid element*
- State machine proofs ensure operations happen *in the right order*, not just *without crashing*
- Linear resource tracking proves DOM nodes are *correctly parented*, not just *not leaked*

If you think C code is needed, that is a bug in ward -- file it (see rule 3).

### UI and Application Logic Proofs

UI code (state machines, event routing, async callback dispatch) must also be proven correct:

- **App state machines**: Define `dataprop` or `absprop` for valid app states and transitions. Prove that state changes only follow valid paths.
- **Node ID mappings**: When DOM node IDs map to application-level indices, prove the mapping is correct using `dataprop`.
- **Async callback dispatch**: Prove that callback routing delivers to the correct handler based on pending operation state.
- **Serialization roundtrips**: When data is serialized for storage and later deserialized, prove the roundtrip preserves the data using `absprop`.

```ats
(* App state machine: prove only valid transitions *)
dataprop APP_STATE_VALID(state: int) =
  | APP_INIT(0) | APP_LOADING(1) | APP_READY(2)

(* Serialization roundtrip: prove restore undoes serialize *)
absprop SERIALIZE_ROUNDTRIP(serialize_len: int, restore_ok: int)
```

## ATS2 Patterns

### Freestanding arithmetic

ATS2's built-in `+`, `*`, `>=`, `>` generate prelude template dispatch calls (`g0int_add`, `g0int_mul`, etc.) that don't exist in freestanding mode. Replace them with explicit extern functions and overloads:

```ats
extern fun add_int_int(a: int, b: int): int = "mac#myapp_add"
extern fun mul_int_int(a: int, b: int): int = "mac#myapp_mul"
overload + with add_int_int of 10   (* priority 10 beats built-in *)
overload * with mul_int_int of 10
```

For comparisons, explicit function calls are more reliable than overloads (overloads for `>=` can remain ambiguous):

```ats
extern fun gte_int_int(a: int, b: int): bool = "mac#myapp_gte"
(* Use: if gte_int_int(x, 255) then ... *)
```

### g0int vs g1int

Plain `int` is `g0int` (untracked). `int c` from `[c:nat] int c` is `g1int` (dependent, statically indexed). These are **different types** -- g0int overloads don't match g1int arguments, causing ATS2 to fall back to prelude templates (`g1int_mul`, `g1int_add`). Solutions:

- Use plain `int` returns when you don't need the static index
- Add separate g1int overloads if you need dependent arithmetic
- Use `castfn` to explicitly cast between the two

### ATS2 keywords to avoid

`op` is a reserved keyword in ATS2. Don't use it as any identifier -- not in dynamic variables, static variables, or dataprop indices. Use `opc`, `opcode`, etc.

## Writing Dataprops

Dataprops are compile-time proofs that are completely erased at runtime. Use them to make invalid states unrepresentable.

### Whitelist pattern: enumerate valid values

When only specific values are legal, create a dataprop with one constructor per valid value. The constructors ARE the whitelist -- no other values can produce a proof:

```ats
dataprop VALID_OPCODE(opc: int) =
  | OPCODE_SET_TEXT(1)
  | OPCODE_SET_ATTR(2)
  | OPCODE_CREATE_ELEMENT(4)

(* Only way to call: emit_diff(OPCODE_SET_TEXT(), 1, ...) *)
fn emit_diff {opc:int}
  (pf: VALID_OPCODE(opc), opcode: int opc, ...): void
```

This is stronger than `#define` constants -- even if you use the right numeric value, you must also produce the matching proof.

### Never use praxi in application code

`praxi` (proof axioms) are trusted assertions -- the compiler does not verify them. They belong only in ward's internal implementation where each use is individually justified. Application code must construct all proofs through dataprop constructors, which the compiler fully checks. If you cannot produce a proof through constructors, the design needs to change -- file a bug against ward if the API doesn't provide a way to construct the proof you need.

### dataprop vs dataview

- `dataprop` = non-linear (can be unused, duplicated). Use for most proofs.
- `dataview` = linear (must be consumed exactly once). Use when tracking resource ownership (e.g., a buffer lock that must be released).

### Constraint solver limitations

The ATS2 constraint solver handles linear integer arithmetic but NOT case analysis on dataprop constructors. If the solver needs to know that `VALID_ATTR_NAME(n)` implies `n <= 8`, add an explicit constraint alongside the proof parameter:

```ats
fun set_attr
  {nl:nat | nl <= BUF_CAP} {vl:nat | nl + vl <= BUF_CAP}
  (pf_attr: VALID_ATTR_NAME(nl), ..., name_len: int nl, ...): ...
```

The `nl <= BUF_CAP` is redundant with `VALID_ATTR_NAME` (max name is 8 chars) but necessary for the constraint solver.

## Static Unit Tests in ATS2

### The Core Idea

In ATS2, `bool(b)` is a singleton type — the only value assignable to `bool(true)` is `true`. This means a function declared to return `bool(true)` must, at compile time, be provably correct. The typechecker rejects any implementation that cannot statically guarantee the return value.

This makes it possible to write unit tests that never run. They are verified by the compiler during type-checking, and they impose zero runtime cost.

### What a Static Unit Test Looks Like

```ats
(* UNIT TEST *)
fun test_add_2_3(): bool(true) = add(2, 3) = 5
```

If `add` has a sufficiently precise dependent type signature — `{m,n:int} int(m) -> int(n) -> int(m+n)` — this typechecks, and the test passes at compile time. If `add` returns `Int` (an existentially quantified integer — some integer, we don't know which), the test fails to compile.

### Why This Matters

The test is not checking that `add(2, 3)` happens to return `5` when run. It is checking that the type system *knows* `add(2, 3)` returns `5`. These are different things.

A conventional unit test can be satisfied by an implementation that works on the tested inputs and lies about everything else. A static unit test cannot be satisfied unless the function's type signature is honest enough for the compiler to verify the property without executing anything.

The practical consequence: **a static unit test is a demand on the precision of the types, not just on the behavior of the implementation.** Writing the test and having it fail is how you discover that a type signature is weaker than it should be. The test failure tells you exactly where the types are not carrying enough information.

### The Discipline

Mark all static unit tests with a `(* UNIT TEST *)` comment immediately above the function. This makes them easy to identify, audit, and eventually strip from release builds.

```ats
(* UNIT TEST *)
fun test_sort_length {n:nat} (xs: list(int, n)): bool(true) =
  list_length(sort(xs)) = n

(* UNIT TEST *)
fun test_sort_idempotent {n:nat} (xs: list(int, n)): bool(true) =
  sort(sort(xs)) = sort(xs)
```

If a test cannot be written as returning `bool(true)`, that is a signal. Either the property is not statically verifiable with the current types, or the types are too weak. In either case, the test has done its job: it has located a gap.

### What Static Tests Cannot Cover

Static unit tests only work for properties that the type system can express and the constraint solver can verify. They are not a replacement for runtime testing of:

- Properties where the return value depends on runtime data that cannot be expressed as a static index
- Performance characteristics

A function that performs I/O can still have a static unit test, as long as its return type can be statically guaranteed regardless of what the I/O does. The test is on the type of the return value, not on the presence or absence of side effects. Error handling paths that are determined by the type of the input — preconditions, postconditions, bounds checks, nonzero requirements — are expressible in dependent types and should have static tests.

Where they apply, they are strictly stronger than runtime tests.

### Summary

| | Runtime unit test | Static unit test |
|---|---|---|
| When verified | At test execution | At compile time |
| Can be gamed by partial correctness | Yes | No |
| Demands type precision | No | Yes |
| Runtime cost | Non-zero | Zero |
| Identifies weak type signatures | No | Yes |

Write static unit tests for every function. If a test does not compile, your types need work. That is not a reason to skip the test — it is the point of writing it.

## Guidelines for Application Code

1. **Every state transition needs a proof witness**: Construct and consume a dataprop proof for every state transition.

2. **Never modify shared buffers between DOM operations**: If you must read or write a shared buffer between DOM calls, flush pending diffs first.

3. **Async operations require state setup BEFORE the call**: If a function triggers an async bridge operation, all state must be set BEFORE the call, not in a continuation or callback.

4. **Every bug fix must add a preventing proof or invariant**: When fixing a bug, don't just fix the code -- add a dataprop, absprop, or documented structural invariant that makes the same class of bug impossible to reintroduce. If the invariant can be encoded as a dataprop (data values, state transitions, bounds), use a dataprop. If it's structural (recursion shape, continuation pattern), document it as a formal invariant in the `.sats` file with the specific bug class it prevents.

5. **Test failures require dataprop analysis**: Every test failure MUST result in comprehensive analysis of all potential dataprops that could have prevented the failure, followed by implementation of those dataprops. The analysis should identify: (a) what runtime invariant was violated, (b) whether a dataprop/absprop could encode that invariant at compile time, (c) what proof obligations would prevent the same class of failure. Even if the fix is a one-line change, the dataprop analysis and implementation are mandatory.

6. **Errors must be impossible or indicate bad input**: Every error condition must either be (a) made impossible by dependent types / dataprops (compile-time elimination), or (b) the result of invalid external input (corrupt data, malformed input), in which case the user must see a clear visual indication of what was wrong. Console-only logging is never sufficient for user-facing errors.

7. **Comprehensive e2e tests are mandatory**: Every application MUST have comprehensive end-to-end tests using Playwright (see the E2E Testing section below). These tests are the final verification that the proven-correct code actually works in the browser. But e2e tests are *verification*, not *the fix* -- see the E2E Testing section for the correct response to test failures.

## E2E Testing

### Playwright is required

Every ward application MUST have comprehensive end-to-end tests using Playwright. These tests exercise the full stack: WASM module loading, bridge communication, DOM rendering, user interaction, and async operations.

### Test configuration

Use multiple viewport sizes to catch layout and rendering issues across device classes:

```js
// playwright.config.js
import { defineConfig } from '@playwright/test';

export default defineConfig({
  testDir: './e2e',
  timeout: 60000,
  expect: { timeout: 15000 },
  use: {
    baseURL: 'http://localhost:3737',
    screenshot: 'on',
    trace: 'on',
    headless: true,
  },
  webServer: {
    command: 'npx serve . -l 3737 --no-clipboard',
    port: 3737,
    reuseExistingServer: !process.env.CI,
  },
  projects: [
    { name: 'desktop', use: { browserName: 'chromium', viewport: { width: 1024, height: 768 } } },
    { name: 'mobile-portrait', use: { browserName: 'chromium', viewport: { width: 375, height: 667 } } },
    { name: 'mobile-landscape', use: { browserName: 'chromium', viewport: { width: 667, height: 375 } } },
    { name: 'tablet', use: { browserName: 'chromium', viewport: { width: 768, height: 1024 } } },
    { name: 'wide', use: { browserName: 'chromium', viewport: { width: 1440, height: 900 } } },
  ],
});
```

### Responding to e2e test failures

When an e2e test fails, the response protocol is strict:

1. **All crashes are ward bugs.** If the WASM module crashes (page crash, `RuntimeError`, `unreachable` executed), that is a bug in ward. STOP and file a bug report against ward. Do not attempt to fix the crash in application code -- ward's safety guarantees are supposed to make crashes impossible.

2. **Non-crash failures require dataprop analysis FIRST.** Before writing any fix, determine: (a) what runtime invariant was violated, (b) could a dataprop or absprop have prevented this at compile time, (c) what proof obligations would make this class of failure impossible. Implement the dataprops FIRST, then fix the behavior.

3. **Never fix the symptom without the proof.** A test failure that gets fixed with a one-line code change but no new dataprop is an incomplete fix. The proof prevents regression; the code change merely addresses today's instance.

### What to test

E2e tests must cover:

- **App lifecycle**: WASM loads, initializes, renders initial UI
- **User flows**: Complete user journeys (import data, interact, verify results)
- **State persistence**: Data survives page reload (IndexedDB roundtrip)
- **Navigation**: All navigation paths (forward, back, cross-boundary transitions)
- **Input methods**: Click zones, buttons, keyboard shortcuts
- **Error display**: Invalid input shows user-visible error (not just console)
- **Screenshots at every key step**: For visual regression tracking

### Package dependencies

```json
{
  "devDependencies": {
    "@playwright/test": "^1.56.0",
    "serve": "^14.2.0"
  }
}
```

## Proof Architecture

All proofs must be **enforced**: the ATS2 type system rejects incorrect code at compile time. If a function requires a `VALID_OPCODE` proof, there is no way to call it without constructing that proof through a dataprop constructor. Comments and conventions are not proofs. If an invariant cannot be enforced by the type system, the design must change until it can be.
