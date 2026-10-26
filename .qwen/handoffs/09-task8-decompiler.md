# Handoff 09 — Task 8: re-enable the decompiler (F1) + the two blockers

Date: 2026-10-26. Branch `experiment/swift-data`, HEAD `6e42cb9` at start. Executed by **Agent 10 (worker)**. No commit made here (orchestrator commits after verification).

## 1. Files changed

| File | Change |
| --- | --- |
| `Aether/Models/AppState.swift` | (a) `instructions(in:)`: `guard remaining - c >= 0` → `guard c <= remaining` (Blocker 1). (b) Disassembly cache: new `disassembledFor: PersistentIdentifier?` (which binary the cache belongs to) + `disassemblyCacheGeneration: Int` (reset token); new public `resetDisassemblyCache()`; `disassembleIfNecessary` now (i) auto-resets on binary-identity mismatch, (ii) no longer marks `data(in:) == nil` ranges as disassembled (marks per-range only after a successful disassembly), (iii) drops disassembler results if a reset happened while suspended at the actor `await` (Blocker 2). (c) Decompiler: `decompileCurrentFunction()` is now `async`, calls the real `Decompiler` (via legacy `Function`/`BinaryFile` adapters), caches output in `decompiledOutputs: [PersistentIdentifier: String]` keyed by `procedure.persistentModelID`, exposes `decompileState: .running/.done/.failed(String)` and `selectedProcedureID`; new private `legacyBinary(for:)` adapter. |
| `Aether/UI/DecompilerView/DecompilerView.swift` | Body now switches on `decompileState` (spinner / failure panel / code). The `.task` is now `.task(id: appState.selectedProcedureID) { await appState.decompileCurrentFunction() }` — switching selection cancels the in-flight decompile and starts a fresh one. |
| `Aether/Navigator/ProgramNavigator.swift` | "Load..." context-menu action now calls `appState.resetDisassemblyCache()` before **and** after `MachOLoader.load(binary)` (the explicit invalidation hook; see §2.1). |
| `Aether/Scene/AetherCommands.swift` | "Decompile" (⇧⌘D) command wraps the now-async `decompileCurrentFunction()` in `Task { @concurrent in await … }`. |

Not touched: Task 5 annotation/bookmark/rename code, Task 6 `MachOLoader.scanStrings`, Task 7 navigator filters/SearchSheet, Schema's `.project` model list, legacy `BinaryFile`/`Function` loader paths (only *adapter* values are constructed for the decompiler), `ORCHESTRATOR_NOTES.md`. `AetherKit/Package.resolved` untouched (no `swift test` run).

## 2. Decisions + reasoning

### 2.1 Blocker 2 — cache-invalidation hook
**Chosen: explicit reset in the Load path, plus two cheap defensive layers.**
- **Primary hook:** `ProgramNavigator`'s "Load..." action (the only place a binary's models are (re-)parsed) calls `appState.resetDisassemblyCache()` immediately before *and* after `try await MachOLoader.load(binary)`. Rationale: (a) the AppState cache is address-keyed with no data generation; a re-Load replaces the model rows (Task 2 reset-first) and may change the on-disk bytes, so any pre-Load cache is invalid by definition — dropping it up front also prevents serving stale rows while the load runs; (b) a *failed* re-Load leaves the old (still-valid) models in place — the second reset (only on success) then covers the changed-bytes case; a pre-reset alone would have wiped a valid cache for no reason on failure. (c) This is the only user-visible "Load happened" event in the app; watching `selectedBinary` changes instead would also fire on multi-binary document switching and on auto-select, which is broader than the failure mode.
- **Defensive layer 1 (binary identity):** `disassembledFor: PersistentIdentifier?` records which binary the cache was built for; `disassembleIfNecessary` resets if it no longer matches `selectedBinary.persistentModelID`. `persistentModelID` survives the reset-first re-parse (same model row, rows re-inserted), so this layer is what makes re-Load safe *even without* the explicit hook (belt-and-braces).
- **Defensive layer 2 (mid-flight reset):** the disassembler is an actor — `disassembleIfNecessary` suspends at the `await`, during which a Load could run. A monotonically increasing `disassemblyCacheGeneration` (bumped by `resetDisassemblyCache()`) is captured before the loop and re-checked after each `await`; a stale result is dropped instead of being inserted into the freshly-cleared cache (otherwise pre-Load instructions would be re-cached for the new bytes).
- **No mark on nil data:** the old code did `disassembled.formUnion(requestedSet)` *before* the `data(in:)` read, so an unbacked range was marked disassembled forever (its bytes could appear on a later Load). Now each range is marked only after a non-empty successful disassembly.

### 2.2 Blocker 1 — underflow: honest correction
The audit described `guard remaining - c >= 0` as a **UInt64 underflow trap**. It is not: `remaining = range.count` is `Int` and `c = instructions[upperBound].addressRange.count` is `Int`, so on this 64-bit platform `0 - 4` yields `-4`, the guard fails, and the loop breaks — no trap. Verified with the standalone mirror (`.qwen/tmp/underflow_check.swift`, `old` mode runs A→B→A without trapping). The prescribed fix (`guard c <= remaining`) was applied anyway: it is behaviourally identical on every input, removes the subtract-before-compare idiom entirely, and can never trap even if the operands are later retyped to an unsigned type. **Net: Blocker 1 is a latent foot-gun, not a live crash; the fix is still correct and in.**

### 2.3 Decompiler input approach
**Chosen: legacy adapters (plan-recommended; full port stays Task 12).** `decompileCurrentFunction` builds:
- a `Function(name: function.displayName, startAddress: symbol.address, endAddress: symbol.address + symbol.size)` with `callees` mapped from `procedure.callees` (always empty today → linear decompile path; `ControlFlowStructurer` is unreachable until blocks exist);
- a `BinaryFile` via `Self.legacyBinary(for: BinaryModel)` — format/arch/endian/is64/entryPoint/baseAddress/data copied from the model, sections as `_Section` values each carrying its own byte slice (`binary.data(in: section.addressRange) ?? Data()` — needed because `Decompiler.buildStringCache`/`scanForStrings` index `section.data` directly), symbols as legacy `Symbol` values.
Why not port `Decompiler` to models: it is a 1000-line legacy-type consumer (`Function`, `BinaryFile`, `_Section`, `Symbol`, `EnhancedCodePrinter`, `ControlFlowStructurer`); porting mid-task would explode the diff and risk the acceptance build. The adapter is ~40 lines, keeps Task 8 scoped, and the decompiler's per-binary string cache (`cachedBinaryID`) is a `BinaryFile.ID` (== address) so it rebuilds per decompile — a small cost, fine for now.

### 2.4 `.task(id:)` cancellation correctness
- The view's `.task(id: appState.selectedProcedureID)` is the *only* decompile trigger in the UI (the ⇧⌘D command is a separate manual entry that reuses the same method and state). When the id changes — selection switch **or** re-Load (new row → new `persistentModelID`) — SwiftUI cancels the old task and starts a new one.
- `decompileCurrentFunction` checks `Task.isCancelled` (a) after `await disassembleFunction` and (b) before publishing, and swallows `CancellationError`. Cancellation of a cancelled task therefore publishes neither output nor `.failed` — no stuck state, no false failure.
- State scoping: `decompileState` transitions (`.running` → `.done`/`.failed`) are written only by the *current* task; a cancelled task returns at the first `Task.isCancelled` point before writing. The re-entrancy guard (`if case .running { return }`) only bites for the manual command racing the view task; the view's own rapid id switches always proceed (the old task has already returned or will publish nothing).
- Stale-output impossibility: output is keyed by `persistentModelID` in `decompiledOutputs`, and `decompilerOutput` is only ever assigned from the current task's own result or from `decompiledOutputs[currentKey]`. A stale fetch from a previous function is structurally unreachable.
- Re-Load: `.task(id:)` re-fires on the new procedure id; `decompiledOutputs` still holds the old key (harmless memory until window close; keys of deleted rows simply go unreferenced).

### 2.5 Concurrency note
`decompile()` runs synchronously on the MainActor (app default isolation). Kept that way deliberately: running it off-actor would require making the shared mutable `Decompiler` instance thread-safe (it is a `nonisolated final class` with mutable `binary`/`strings`/`variableNames` state), which is a Task 12 port concern. Prototype-scale functions decompile in milliseconds; the `await disassembleFunction` hop is where the real wait happens, and it is cancellable at the actor boundary.

## 3. Evidence

- **Build:** `xcodebuild -project Aether.xcodeproj -scheme Aether -destination 'platform=macOS' build` → `** BUILD SUCCEEDED ** [6.180 sec]` (only pre-existing CapstoneKit "no rule to process file" warnings). (One red build en route: three compile errors — enum-with-associated-values `!=`, `persistentIDStringValue` doesn't exist on `PersistentIdentifier`, and a `UInt64`/`Int` mismatch in the underflow fix — all fixed; `PersistentIdentifier` used directly as the dictionary key.)
- **Underflow mirror:** `.qwen/tmp/underflow_check.swift` (git-ignored) mirrors both guard forms and runs A→B→A (A = one 12-byte insn at 0x100, B = one 4-byte insn at 0x200, requested after both cached):
  ```
  OK (fixed): A→B→A returned 1 instruction(s), 12 bytes
  OK (old): A→B→A returned 1 instruction(s), 12 bytes
  ```
  Both return exactly A's instructions; old mode's `0 - 4` is a non-trapping `Int` negation (§2.2) — the correction to the audit's "UInt64 underflow trap" claim is documented there.
- **Diff/trace — decompiler is live:** `git diff Aether/Models/AppState.swift` shows the stub (`decompilerOutput = "// Decompiling..."` + fully commented `Task`) replaced by: `await disassembleFunction(function)` → real `decompiler.decompile(function: legacyFunction, instructions:, binary: legacyBinary)` → `decompiledOutputs[key] = output` with `key = function.persistentModelID` → `.done`; failure → `.failed(error.localizedDescription)`. `DecompilerView` now has `.task(id: appState.selectedProcedureID)` + the three-state switch (spinner `Decompiling...`, `ContentUnavailableView("Decompilation failed")`, `SyntaxHighlightedCode`). Grep confirms the permanent placeholder string `// Decompiling...` is gone from `Aether/`.
- **Grep — invalidation wiring:** `resetDisassemblyCache` defined once in AppState, called twice in `ProgramNavigator` Load action; `disassembledFor`/`disassemblyCacheGeneration` referenced only in AppState. `data(in:) == nil` ranges are no longer unioned (mark moved to the post-success site).

## 4. What Agent 11 (Task 9: HexView B8/B9) needs

- **Do NOT touch** anything in this handoff's §1 list (AppState decompile section, disassembly cache machinery, DecompilerView, ProgramNavigator Load action, AetherCommands Decompile command).
- Task 9 surface is intact: `BinaryModel.read(at:count:)` / `readString(at:)` still index `data` with the **raw virtual address** (no `baseAddress` adjustment) — B8; `HexView` still loads the whole file with `baseAddress = section.address` — B9. `BinaryModel.data(in:)` is already bounds-guarded and is what this task's adapter uses — prefer it.
- The disassembly cache now resets on Load: if Task 9's spot-check flow involves a re-Load, the HexView will (after its fix) simply show the section's slice; no cache interaction expected.
- `BinaryModel.span(in:)`/`data(in:)` semantics: ranges below `baseAddress` → empty/nil; partially-out-of-file ranges → clamped (span) or nil (data). Keep HexView's range fully inside the section's file-backed range.

## 5. Manual UI smoke steps (for the user, at end of session)

Smoke binary: `.qwen/tmp/thin_test` (thin arm64).
1. New document → Import Binary... (⇧⌘O) → pick `.qwen/tmp/thin_test` → Programs navigator → **Load...**.
2. **Functions tab → click `sumOfSquares`** → Decompiler panel (right) shows a brief "Decompiling..." spinner, then real pseudo-code: signature line (`int64_t sumOfSquares(...)`) and per-instruction pseudo lines. No permanent `// Decompiling...` placeholder.
3. **Rapid switching:** click `sumOfSquares` → `factorial` (or any second function) → back to `sumOfSquares` quickly, several times. The panel must always end in either the spinner or *that function's* pseudo-code — never another function's output, never a stuck spinner, never a spurious "Decompilation failed".
4. **⇧⌘D (Decompile) command** re-triggers decompilation for the selected function (same states).
5. **Re-Load:** Programs navigator → **Load...** on the same binary again → click a function → decompile. Output appears again (cache was reset; nothing served stale). Disassembly list also repopulates (was reset too).
6. **Copy button** in the Decompiler header copies the current pseudo-code to the clipboard.
7. Select a function whose body is entirely undecodable bytes (none in `thin_test` — skip unless testing exotic inputs) → expect the "Decompilation failed" panel with a message, not a stuck spinner.

## 6. Risks / known interim states

- `decompile()` on the MainActor can briefly block the UI on very large functions (documented §2.5; Task 12 port is the real fix).
- The linear decompiler is still the heuristic it always was (no block structuring — `basicBlocks` is never populated from the models; `callees` empty). Pseudo-code quality is unchanged by this task; F1 dormancy is what's fixed.
- `decompiledOutputs` grows with distinct procedures per window session (strings only, bounded by function count × output size) — fine until documents get large.
- `AetherToolbar`'s copy/export-ish gate `decompilerOutput.isEmpty` now flickers empty during `.running` (previously it was permanently non-empty after the placeholder) — the Copy button is disabled while decompiling, which is the more correct behavior.
- Dead-code candidates for Task 11 (unchanged list from handoff 08 + nothing new; the commented Java path inside the old stub was deleted with it — `decompileJavaMethod` is now referenced only by the deleted comment, i.e. **unreferenced but still compiles**; confirm no other callers before deleting in Task 11 — I found none by grep).
