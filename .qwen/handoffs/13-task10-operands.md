# Handoff 13 — Task 10 Operand symbol resolution (Agent 14)

STATUS: COMPLETE

## Pre-flight
- HEAD: `635b1a7` (experiment/swift-data) "Fix HexView hex display (B8/B9)"
- `git status --short`: only `M ORCHESTRATOR_NOTES.md` (orchestrator's file — not touching)

## Findings (so far)
- Dead cache reads found in two places:
  - `Aether/UI/DisassemblyView/DisassemblyView.swift:290,293,301` — `OperandsView` (line 244)
  - `Aether/UI/DisassemblyView/BranchVisualization.swift:742,745,751` — `EnhancedOperandsView` (line 703); used at line 566
- Dead cache declarations: `Aether/Models/AppState.swift:137-139` (`symbolsByAddress`, `symbolsByName`, `functionsByAddress`)
- `Inspector.swift:45` is a comment only.

## Current state (read 2026-10-26)

- `OperandsView` (`DisassemblyView.swift:244`) and `EnhancedOperandsView` (`BranchVisualization.swift:703`, used at :566) each have a `classifyOperand(_:)` that:
  - for a hex-ish operand with `instruction.branchTarget`: reads `appState.symbolsByAddress[target]` (`.symbol`) then `appState.functionsByAddress[target]` (`.function`)
  - otherwise reads `appState.symbolsByName[text]` (`.symbol`, `address: symbol.address`)
  - all three caches (`AppState.swift:137-139`, `@ObservationIgnored`, typed against legacy `Symbol`/`Function`) are **declared but never populated anywhere** → resolution is 100% dead; every operand falls through to `.immediate`/`.other`.
- Navigation already exists and is independent of the caches: `OperandText`/`EnhancedOperandText` render `.symbol`/`.function` as an accent-colored `Button` calling `appState.goToAddress(operand.address)`; `goToAddress` (AppState) updates `selectedSection`/`selectedFunction`/`selectedAddress`, and `DisassemblyView.onChange(of: appState.selectedAddress)` scrolls to it. So making resolution populate `.symbol` operands automatically delivers the navigate-on-click acceptance.
- `.symbol` and `.function` render identically in both `operandColor` switches and both button paths → collapsing to `.symbol` is visually a no-op. (`Operand`/`OperandType` are shared between the two files; `SearchView`/`AnalysisViews` `.function` matches are unrelated enums.)
- Load path: `ProgramNavigator` "Load..." → `resetDisassemblyCache()` before/after `MachOLoader.load(binary)`; re-Load keeps the **same `BinaryModel`** (persistentModelID survives), so any model-derived cache keyed by binary identity must also be cleared in `resetDisassemblyCache()`.
- `BinaryModel.symbols`/`procedures` relationships are already in memory (Task 8's `legacyBinary(for:)` maps `binary.symbols` directly) → no `FetchDescriptor` needed; iterate the relationships.
- `SymbolModel.displayName` strips one leading `_`; `ProcedureModel.displayName` falls back to `sub_<addr>` for empty names; `ProcedureModel.symbol` is the `SymbolModel` backing the procedure (typically the same instance as the row in `binary.symbols` at that address).
- Task 5 already deleted `getDisplayName(forFunctionAt:)`/`(forSymbolAt:)`; no other live references to the dead caches (grep above; `Inspector.swift:45` is a comment).

## Design

AppState gains (Swift 5 mode, MainActor default isolation — all synchronous, on MainActor):

```swift
@ObservationIgnored private var operandSymbolsByAddress: [UInt64: SymbolModel] = [:]
@ObservationIgnored private var operandSymbolsByName: [String: SymbolModel] = [:]
@ObservationIgnored private var operandLookupsFor: PersistentIdentifier?

func operandSymbol(at address: UInt64) -> SymbolModel?     // procedure-preferred
func operandSymbol(named name: String) -> SymbolModel?     // name + identifier keys
private func ensureOperandSymbolLookups()                   // lazy build, keyed by persistentModelID
```

- **Lazy build** on first access (DisassemblyView body), iterating `binary.symbols` then `binary.procedures` (procedures overwrite at the same address → function display name preferred for call/branch targets; `sub_<addr>` fallback for unnamed procs means function targets resolve even without a symbol name). Symbol counts are small (thin_test 26, TF3 a few thousand) — one pass, cached.
- Storing live `SymbolModel` refs (not copied strings) means **user renames stay fresh for free** — `displayName` reads `name` at render time, no invalidation hook needed in the rename mutators.
- `resetDisassemblyCache()` clears the tables + `operandLookupsFor` (piggyback, sanctioned) so a reset-first re-parse (new symbol rows, same BinaryModel) is picked up. Existing disassembly-cache logic otherwise untouched.
- Views: `appState.symbolsByAddress[target]` + `functionsByAddress[target]` → single `appState.operandSymbol(at: target)` (`.symbol`); `appState.symbolsByName[text]` → `appState.operandSymbol(named: text)`. Falls through to `.immediate`/`.other` (address display) when nothing resolves — unchanged.
- Then delete the three dead cache declarations (zero remaining references).

## Edits (all made 2026-10-26)

1. `Aether/Models/AppState.swift` — replaced the dead `// MARK: - Lookup Caches (for O(1) access)` block (old lines 137-139, `symbolsByAddress`/`symbolsByName`/`functionsByAddress`) with the Task 10 declaration block: `operandSymbolsByAddress: [UInt64: SymbolModel]`, `operandSymbolsByName: [String: SymbolModel]`, `operandLookupsFor: PersistentIdentifier?` (all `@ObservationIgnored private`).
2. `Aether/Models/AppState.swift` — new `// MARK: - Operand Symbol Resolution (Task 10)` section after `disassembleRange`: `operandSymbol(at:)`, `operandSymbol(named:)`, `ensureOperandSymbolLookups()` (lazy build from `binary.symbols` then `binary.procedures`, keyed by `persistentModelID`).
3. `Aether/Models/AppState.swift` — `resetDisassemblyCache()` now also clears the three operand-lookup fields (piggyback; documented in its doc comment). Existing disassembly-cache lines untouched.
4. `Aether/UI/DisassemblyView/DisassemblyView.swift` — `OperandsView.classifyOperand`: `symbolsByAddress[target]` + `functionsByAddress[target]` → `appState.operandSymbol(at: target)` (`.symbol`); `symbolsByName[text]` → `appState.operandSymbol(named: text)`. Falls through to `.immediate`/`.other` unchanged.
5. `Aether/UI/DisassemblyView/BranchVisualization.swift` — `EnhancedOperandsView.classifyOperand`: same replacement.

Navigation untouched: `.symbol` operands render as accent `Button` → `appState.goToAddress(addr)` (existing, works for both operand views). Renames stay fresh because the tables hold live `SymbolModel` refs and `displayName` reads `name` at render time.

## Verification (real output, 2026-10-26)

1. `xcodebuild -project Aether.xcodeproj -scheme Aether -destination 'platform=macOS' build` (from repo root) → `** BUILD SUCCEEDED ** [5.835 sec]`, exit 0 (background task `bg_b1531957`).
2. `cd AetherKit && swift build` → `Build complete! (0.24 secs.)` (unchanged package, incremental).
3. `swift build --package-path aether-cli` → `Build complete! (0.25 secs.)` (unchanged, incremental).
4. Grep-proof, repo-wide `symbolsByAddress|functionsByAddress|symbolsByName`: the **only** hit outside the new `operandSymbolsBy*` identifiers is `PLAN.md:18` (documentation row, off-limits to me — orchestrator may retire the B10 row). Zero live references to the deleted dead caches. `operandSymbol(` grep: defined at `AppState.swift:1415/1422`, called at `DisassemblyView.swift:290/298` and `BranchVisualization.swift:743/750` — resolution now demonstrably reads the model-built tables.
5. `git status --short`: my changes are exactly `Aether/Models/AppState.swift`, `Aether/UI/DisassemblyView/DisassemblyView.swift`, `Aether/UI/DisassemblyView/BranchVisualization.swift` + this handoff. Pre-existing/unrelated: `M ORCHESTRATOR_NOTES.md`, `M .qwen/settings.json` (orchestrator's). **No `Package.resolved` churn.**

## Manual UI smoke steps (for the orchestrator/user)

1. Open a project containing `thin_test` (has `__TEXT,__stubs` and `main`/`sumOfSquares`). Load it (right-click → Load...), select `main` in the Functions navigator.
2. In Disassembly, the `call`/branch-target operands (e.g. the stub call into `sumOfSquares` at `__TEXT,__stubs`) should now render as **accent-colored, hover-underlined** names instead of bare `0x…` hex.
3. Click one → the disassembly view should scroll/navigate to that function (existing `goToAddress` path: updates `selectedFunction`/`selectedAddress`, `DisassemblyView` auto-scrolls on `selectedAddress` change).
4. Unresolved targets (e.g. a branch to an unmarked address) still show the raw hex address and remain non-clickable — unchanged behaviour.
5. Rename a target function (Functions navigator → rename), switch away and back: the operand should show the new name immediately (live `SymbolModel` refs, no cache staleness).
6. Re-Load the binary: lookups rebuild (cleared in `resetDisassemblyCache`), names still resolve.

## Risks / notes

- `.function` `OperandType` case is now never produced (only `.symbol` is); rendering was already identical for the two, so it's visually a no-op. Kept the enum case (shared with other UI code paths; deleting it is Task 11 dead-code territory).
- `operandSymbol(at:)` prefers the procedure's symbol at an address (function display name, `sub_<addr>` fallback for unnamed procs) where the old dead code would have preferred a plain symbol first — practically the same `SymbolModel` instance in either order; only affects pathological binaries where two distinct rows share an address.
- Lazy build happens synchronously inside view body (MainActor) on first render per binary: one pass over `binary.symbols` + `binary.procedures` (thin_test: 26 symbols; TF3: a few thousand) — negligible, but it is in the render path.
- The `operandSymbol(named:)` path only fires if the disassembler ever emits a bare symbol name as operand text (Capstone emits hex today); kept for parity with the old code's structure.
- No changes to disassembly, decompiler surface, HexView/schema reader, `Aether/Scene/`, or `aether-cli/` (hard-rule compliance).
