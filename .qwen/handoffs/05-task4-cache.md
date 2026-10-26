# Handoff 05 — Agent 5 (Task 4: delete `clearDisassemblyCache` + bounded disassembly-cache audit)

Date: 2026-10-26. Branch `experiment/swift-data`, HEAD `f084113` (agent does not commit; orchestrator commits with `git -c commit.gpgsign=false`).

## 1. Task 4 — what changed

**Decision: DELETE, not fix.** Handoff 04's claim (zero live callers) was independently re-verified:

- `grep -rn 'clearDisassemblyCache' Aether/` → the only pre-deletion occurrences were the method definition (old `AppState.swift:1203-1209`) and 3 **commented-out** call sites. No live call.
- The 3 stub functions that contained the commented sites (`patchBytes`, `nopInstruction`, `revertPatch`) were themselves grepped (`\.patchBytes\(|\.nopInstruction\(|\.revertPatch\(`) → zero callers anywhere in `Aether/`. `BinaryPatcher` is deprecated (PLAN B5); the patch layer is dead until Task 11's open question settles "revert to original file = re-read `fileURL`".

**Deletions (all in `Aether/Models/AppState.swift`, tabs preserved; net −14 lines, 1624 → 1610):**

| Old lines | What |
| --- | --- |
| 1155–1156 | `patchBytes`: `//` blank-comment line + `//			// Clear cache for affected section` + `//			clearDisassemblyCache(in: address..<(address + UInt64(newBytes.count)))` (3 lines) |
| 1171 | `nopInstruction`: `//			clearDisassemblyCache(in: address..<(address + UInt64(size)))` (1 line) |
| 1185 | `revertPatch`: `//			clearDisassemblyCache(in: patch.address..<(patch.address + UInt64(patch.newBytes.count)))` (1 line) |
| 1203–1210 | the `func clearDisassemblyCache(in range: Range<UInt64>)` method + its trailing blank line (9 lines) |

The (now fully inert) stub functions `patchBytes`/`nopInstruction`/`revertPatch` were left in place — deleting them is Task 11 scope, not Task 4.

**Post-deletion grep evidence:** `clearDisassemblyCache` → **0 matches under `Aether/`**. The only repo-wide remaining mentions are documentation in `PLAN.md` (lines 19, 67, 141 — the bug table B5/D11 row and Task 4's own spec); expected and left as-is.

**Build:** `xcodebuild -project Aether.xcodeproj -scheme Aether -destination 'platform=macOS' build` → `** BUILD SUCCEEDED ** [6.375 sec]` (only the pre-existing capstone "no rule to process file … .inc" warnings).

**`git status --short` at agent end:** exactly `M Aether/Models/AppState.swift` (`git diff --stat`: 1 file changed, 14 deletions). No incidental drift to restore.

## 2. Audit — AppState's disassembly transient state (recon for Tasks 5/8/10/11)

Line numbers below are **post-deletion** (`AppState.swift`, 1610 lines).

### 2.1 Ownership & lifecycle

- `AppState` is a **per-window session**: `AetherRootView` owns `@State session = AppState()` and injects it into the environment. One `AppState` per window/document; **a new window or new document gets a fresh, empty cache**.
- The cache is **session-scoped, never persisted, and never cleared** by any model operation. The only clearing path in the codebase was the just-deleted dead `clearDisassemblyCache`.
- The disassembler engine is a plain member: `private let disassembler = DisassemblerEngine()` (line 161) — an actor, model-agnostic (takes `data` + `address` + `architecture`); no port needed (confirmed Task 1).

### 2.2 State inventory (`MARK: - Disassembly`, lines 1187–1192)

```swift
@ObservationIgnored var disassembled = RangeSet<UInt64>()   // 1189 — every byte address ever marked disassembled
var instructionMap: [UInt64: Int] = [:]                     // 1190 — NOT @ObservationIgnored (observable)
@ObservationIgnored var instructions: [Instruction] = []    // 1191 — flat array, address-ordered
@ObservationIgnored var pcode: [Pcode] = []                 // 1192 — flat array
```

- **Keying is by virtual address, not model ID.** `instructionMap` maps **every byte address** in each instruction's `addressRange` → index into `instructions`.
- Each `Instruction` (legacy type, `Models/Instruction.swift`) carries `pcode: Range<Int>` — a half-open range into the flat `pcode` array. `Inspector.swift:52` indexes it directly: `appState.pcode[instruction.pcode]`. The pcode ranges are **advanced** by a running `pcodesIndex` at insertion (below), so old instructions keep pointing at their own bytes even as `pcode` grows.
- `instructions` is kept **sorted by address**: new ranges are inserted at `instructions.lastIndex { $0.address < range.lowerBound } ?? 0`.

### 2.3 Populate path — exactly one writer

Only `private func disassembleIfNecessary(_ addresses: Range<UInt64>) async` (line 1211) mutates the four vars:

1. `remaining = addresses.subtracting(disassembled)` (RangeSet subtraction).
2. **`disassembled.formUnion(addresses)` runs unconditionally** — the requested range is marked done *before* the data is even read.
3. For each remaining sub-range: `selectedBinary.data(in: range)`; **if `nil`, the range is silently skipped but stays marked disassembled** (consequence below).
4. `await disassembler.disassemble(data:address:architecture: selectedBinary.architecture)` (Capstone).
5. Sorted insertion into `instructions`; each instruction's `pcode` range advanced by `pcodesIndex`; `instructionMap[addr] = index` for every address in the instruction.

Public wrappers (all `async -> ArraySlice<Instruction>`, each = `disassembleIfNecessary(range)` then `instructions(in: range)`):

- `disassemble(section: SectionModel)` — line 1245
- `disassembleFunction(_ function: ProcedureModel)` — line 1250, range = `function.symbol.addressRange`
- `disassembleRange(start:end:)` — line 1255

Readers: `instruction(at:)` (1194), `instructions(in:)` (1198), and the computed `selectedInstruction` (lines 45–55, `@ObservationIgnored`, resolves through `instructions(in: selectedAddressRange)`).

**Consumers:**

- `DisassemblyView.swift` — `loadInstructions()` calls `appState.disassembleFunction(function)` (line 99) or `appState.disassemble(section:)` (line 101, gated on `section.containsCode`); triggered by `.onChange(of: appState.selectedBinary / selectedFunction / selectedSection)` + `.onAppear`; row tap → `appState.select(insn.addressRange)`. Results are copied into the view's own `@State instructions: ArraySlice<Instruction>`.
- `Inspector.swift:8` — `appState.selectedInstruction` (drives `InstructionInspector`); `Inspector.swift:52` — `appState.pcode[instruction.pcode]`.
- `OperandsView` (same file as DisassemblyView) reads `appState.symbolsByAddress[target]`, `functionsByAddress[target]`, `symbolsByName[text]` — see §2.7 (dead caches, Task 10).

### 2.4 The 500-instruction cap

**View-side only.** `DisassemblyView` has `@State private var maxInstructions = 500` and applies `result = result.prefix(maxInstructions)` after each load. **The AppState cache is unbounded** — `instructions`/`pcode`/`instructionMap`/`disassembled` grow for every range ever disassembled in the window, with no eviction.

### 2.5 Stale-cache on re-Load: **YES, the cache survives re-Load** (audit answer)

Mechanism:

1. Re-Load goes through `MachOLoader.machO(for:)`. Task 2's reset-first guard (lines 97–106 of `MachOLoader.swift`) deletes only **SwiftData model rows** (`model.procedures/sections/symbols/segments.removeAll()` + resets `entryPoint`/`stackSize`/`baseAddress`) and then re-parses into fresh model objects. **It never touches AppState** — nothing in the loader or the Programs-navigator "Load..." path reaches the session caches.
2. `disassembled` is only ever unioned. After re-Load, the fresh `ProcedureModel`/`SectionModel` objects have the **same address ranges** as before (same file), so in `disassembleIfNecessary`, `remaining = addresses.subtracting(disassembled)` is **empty** → the method returns immediately and `disassemble(section:)`/`disassembleFunction` serve **the old cached `instructions(in:)` slice without ever calling `selectedBinary.data(in:)` again**.
3. Meanwhile `DisassemblyView.onChange(selectedBinary/selectedFunction/selectedSection)` *does* fire (the model references are new objects), so the view re-runs `loadInstructions()` and happily re-displays the pre-Load cache.

Consequences:

- **Same file bytes** → content is identical, so this is benign *today*.
- **File edited on disk between Loads** (or any future path that changes `BinaryModel.data`, e.g. the Task 11 "patch = re-read file" decision) → the view serves **stale instructions** at unchanged addresses, and `Inspector`'s "Bytes" row (`appState.selectedBinary?.format(hex:)`, which *does* re-read current `model.data`) will visibly disagree with the stale assembly.
- **Failed ranges stay marked**: because `formUnion` happens before the `data(in:)` check, a range whose `data(in:)` returned `nil` is permanently "disassembled" with no instructions — a later re-Load cannot recover it either.
- Only a **new window/document** (fresh `AppState`) resets the cache.
- Task 8 (decompilation of `selectedFunction`) and Task 10 will both consume this same cache; any fix belongs to whichever task first owns cache lifetime. Suggested minimal fix (for the owner, **not** applied here): on `machO(for:)` re-parse success, or via an `AppState` hook the loader call site invokes, reset all four vars together — they are only coherent as a set (`instructionMap` indexes into `instructions`, `Instruction.pcode` indexes into `pcode`, `disassembled` gates re-disassembly).

### 2.6 Latent crash in `instructions(in:)` (line 1198) — **not fixed, out of Task 4 scope; document for Task 8**

```swift
var remaining = range.count
while upperBound < instructions.endIndex {
	let c = instructions[upperBound].addressRange.count
	guard remaining - c >= 0 else { break }   // line 1204
	remaining -= c
	upperBound += 1
}
```

Swift evaluates `remaining - c` **before** the comparison. Once the requested range's bytes are fully consumed (`remaining == 0`) and the loop visits the *next* array element — which belongs to a later-disassembled range whenever more than one range has been cached — `UInt64` **underflow traps** (fatal error, both debug and release).

Repro trigger: select function A, then function B at a higher address (both disassemble fine — B's range is at the array tail), **then select A again** → `instructions(in: A)` consumes A, `remaining` hits 0, next element is B's first instruction → crash. Equivalently: disassemble a function, then any section that ends before the cached array's tail, then go back to the function. This is directly on Task 8's acceptance criterion ("switching quickly between two functions never leaves stuck/stale output" — it's not just stuck, it traps). The guard should be `c <= remaining` (or `remaining >= c`) before the subtraction.

### 2.7 Adjacent transient state (for Task 5/10/11 context)

- **Never-populated symbol caches** (lines 136–138, all `@ObservationIgnored`): `symbolsByAddress: [UInt64: Symbol]`, `symbolsByName: [String: Symbol]`, `functionsByAddress: [UInt64: Function]`. Read at lines 1290/1300 (`getDisplayName`) and by `OperandsView` — always empty, so branch-target/symbol operands never resolve (B10, Task 10). These key off **legacy** `Symbol`/`Function` types, not models — Task 10 must re-key them to `SymbolModel`/`ProcedureModel` (or build them from `@Query`).
- **`currentFile: BinaryFile?`** (line 9): never assigned, dead; full 20-reference inventory was produced by Agent 4 (see its PLAN.md entry); Task 11 deletes it.
- **Rename/comment/bookmark dicts** (lines 149–152): `renamedFunctions: [UInt64: String]`, `renamedSymbols: [UInt64: String]`, `comments: [UInt64: String]`, `bookmarks: [UInt64: Bookmark]`. All mutating methods wrap the dict edits in **manual** `registerUndoRedo` (calls at 1265, 1276, 1309, 1325, 1335; the helper is at 1482). `Bookmark` is the legacy struct in `Models/Project.swift` (Task 11 deletes it *after* Task 5). Schema already has `AnnotationModel` and `BookmarkModel` (Schema.swift; both cascade-reachable via `BinaryModel` but not in the `.project` model list). **Task 5 = replace these dicts + the manual undo with `AnnotationModel`/`BookmarkModel` rows; check `modelContext.undoManager` — the manual `UndoAction` list exists precisely because SwiftData undo was never wired up.**

### 2.8 What does *not* touch this cache

- `goToAddress` (Agent 4's warning stands: it has a pre-existing ⌘G triple-bind; do not "simplify" it into unconditional section re-resolution).
- The ~25 stubbed `analyze*` methods in AppState (Task 11 inventory).
- Any navigator/selection setter — selection changes only *trigger* `loadInstructions()`; they never mutate the cache.

## 3. For Agent 6 (Task 5: annotations/bookmarks/renames modelization)

Task 5's surface is the dict block at `AppState.swift:149-152` and its six mutating readers around lines 1265–1345 (all manual `registerUndoRedo`), plus `getDisplayName` (1290/1300) which consults the rename dicts, and `Bookmark` in `Models/Project.swift`. The SwiftData targets exist (`AnnotationModel`, `BookmarkModel`; renames likely fold into `SymbolModel`/`ProcedureModel` name fields or `AnnotationModel` — the `.project` model-list question in Task 11 step 1 is coupled: if `AnnotationModel`/`BookmarkModel` should be undo-able/autosaved as first-class document rows, the model-list decision matters). Check `modelContext.undoManager` before re-introducing any manual undo; the manual `UndoAction` mechanism at line 1482 is the thing being retired, not extended. **Do not touch the disassembly block (1187–1258)** — Task 8/10 owns it per §2.5/§2.6.
