# Handoff 08 — Task 7: search filters + SearchSheet (B12)

Date: 2026-10-26. Branch `experiment/swift-data`. Executed by **Agent 9**. No commit made here (orchestrator commits after verification).

## 1. Files changed

| File | Change |
| --- | --- |
| `Aether/Navigator/FunctionsNavigator.swift` | Commented `filteredFunctions` block replaced with live `filteredProcedures: [ProcedureModel]` (in-memory, `shortDisplayName.localizedCaseInsensitiveContains`); `List` now iterates `filteredProcedures` (selection binding + `.tag` unchanged). |
| `Aether/Navigator/StringsNavigator.swift` | Same pattern: live `filteredStrings: [StringModel]` filtering `$0.value.localizedCaseInsensitiveContains`; `List(filteredStrings)`. Comment records the @Transient rationale. |
| `Aether/Navigator/SymbolNavigator.swift` | Live `filteredSymbols: [SymbolModel]` filtering `$0.displayName.localizedCaseInsensitiveContains`; `List(filteredSymbols)`. |
| `Aether/Navigator/ImportsNavigator.swift` | Same as Symbols (query still `#Predicate { $0.isImport }` at the SwiftData level; the text filter is an in-memory pass over the query result). |
| `Aether/Navigator/ExportsNavigator.swift` | Same as Imports (`$0.isExport`). |
| `Aether/UI/MainWindow/MainView.swift` | `SearchSheet`: added `import SwiftData` + `@Environment(\.modelContext)`; replaced the commented-out `performSearch` switch with live cases (symbols/strings/functions fetch via `FetchDescriptor` + in-memory filter, `.prefix(50)`; addresses = hex parse). Added a close button (xmark, `.keyboardShortcut(.cancelAction)`) — the shell had no dismiss control. `GoToAddressSheet` untouched. |
| `Aether/Scene/AetherContent.swift` | `SearchSheetModifier` now presents `SearchSheet()` instead of `SearchView()` (one line). **This was necessary:** `SearchSheet` was presented *nowhere* — the modifier was showing the legacy `SearchView` (backed by `appState.search`/`searchResults` stubs), so re-enabling `SearchSheet`'s cases alone would have left the re-enabled sheet unreachable. Mirrors `GoToAddressSheetModifier`. |

Not touched: `scanStrings`/`__cstring` preference/vaddr formula, AppState disassembly cache, Task-5 annotation/bookmark/rename code, `.project` model list, legacy `BinaryFile` loader path, `ORCHESTRATOR_NOTES.md`.

## 2. Decisions + reasoning

1. **In-memory filter for all five navigators** (plan explicitly allows it at prototype scale). Two reasons in-memory wins over a dynamic `#Predicate` even where the field is stored:
   - **Strings is forced in-memory** (hard constraint from handoff 07 §4): `StringModel.value = cached ?? "not loaded"` and `cached` is `@Transient` — not persisted, so `#Predicate` cannot query it.
   - **The other four filter on the *display* name**, which is a computed property (`SymbolModel.displayName` / `ProcedureModel.shortDisplayName` strip the leading `_` and attempt demangling) — exactly what the row shows the user. `#Predicate` can only reference stored properties (`name`/`identifier`), so a predicate-filtered list would mismatch the visible text (e.g. typing `main` would not match the displayed `main` for stored `_main`… it would match, but typing a demangled name would not). One consistent in-memory approach for all five is simpler and matches user-visible text. The `#Predicate` (name LIKE/`localizedStandardContains`) path remains the upgrade if lists get large; note the Strings tab can *never* use it while `value` is `@Transient` — it would need the string bytes persisted (e.g. a stored `value` column).
2. **Filter fields per navigator:** Functions → `ProcedureModel.shortDisplayName`; Symbols/Imports/Exports → `SymbolModel.displayName`; Strings → `StringModel.value`. All case-insensitive (`localizedCaseInsensitiveContains`), matching the style of the original commented code.
3. **SearchSheet re-wired against models via `modelContext.fetch(FetchDescriptor<T>())`** (fetched in `performSearch`, i.e. on each keystroke/type change) + in-memory filter + `.prefix(50)` cap, keeping the shell's own `SearchResult` struct and the `goToAddress`-then-`dismiss` row behavior. `.strings` case filters `$0.value` in memory for the same @Transient reason. Not `@Query`/`@FetchRequest`: those can't be rebuilt per keystroke without an extra container view, and the sheet is a document-scoped one-shot fetch — the context is the document's `ModelContext`, so results are naturally scoped to the open document.
4. **Presentation fix (AetherContent.swift):** see §1. The legacy `SearchView` (`UI/Components/SearchView.swift`) + `appState.search(query:type:)`/`searchResults`/`isSearching` (AppState ~1364–1410, 156–157, 1590 global `SearchType`) are now **unreferenced by the UI but still compile** — left in place (deletion is Task 11's dead-code sweep; the AppState members may have other references to check). Flagging here so Task 11 doesn't assume `SearchView` is live.
5. Row-tap = `goToAddress` behavior untouched in all five navigators; no selection bindings added.

## 3. Evidence

- **Build:** `xcodebuild -project Aether.xcodeproj -scheme Aether -destination 'platform=macOS' build` → `** BUILD SUCCEEDED ** [6.720 sec]` (only the pre-existing CapstoneKit "no rule to process file" warnings).
- **Grep — navigators live (each file: filter defined + `List(filtered…)` in body):**
  ```
  FunctionsNavigator.swift:13:  var filteredProcedures: [ProcedureModel] {
  FunctionsNavigator.swift:25:  List(filteredProcedures, selection: $appState.functionNavigator)
  StringsNavigator.swift:13:    var filteredStrings: [StringModel] {
  StringsNavigator.swift:24:    List(filteredStrings)
  SymbolNavigator.swift:11:     var filteredSymbols: [SymbolModel] {
  SymbolNavigator.swift:22:     List(filteredSymbols)
  ImportsNavigator.swift:13:    var filteredSymbols: [SymbolModel] {
  ImportsNavigator.swift:24:     List(filteredSymbols)
  ExportsNavigator.swift:13:    var filteredSymbols: [SymbolModel] {
  ExportsNavigator.swift:24:     List(filteredSymbols)
  ```
- **Grep — SearchSheet cases uncommented + presented:**
  ```
  MainView.swift:239: case .symbols:
  MainView.swift:240: let symbols = (try? modelContext.fetch(FetchDescriptor<SymbolModel>())) ?? []
  MainView.swift:246: case .strings:
  MainView.swift:249: let strings = (try? modelContext.fetch(FetchDescriptor<StringModel>())) ?? []
  MainView.swift:255: case .functions:
  MainView.swift:256: let procedures = (try? modelContext.fetch(FetchDescriptor<ProcedureModel>())) ?? []
  MainView.swift:262: case .addresses:
  AetherContent.swift:208: SearchSheet()
  ```
- Per-navigator field filtered: Functions `shortDisplayName` (ProcedureModel) · Strings `value` (StringModel, in-memory forced) · Symbols `displayName` (SymbolModel) · Imports `displayName` over the `isImport` query · Exports `displayName` over the `isExport` query.

## 4. What Agent 10 (Task 8: re-enable the decompiler, F1) needs

- **Two pre-existing blockers that must be fixed *with or before* Task 8** (documented, not fixed by this task): (1) `instructions(in:)` **UInt64 underflow trap** in AppState (~line 1204) — `guard remaining - c >= 0` underflows when a cached range sits past the requested one; repro: function A → higher-address function B → A again. (2) **Stale disassembly cache** — the `disassembled` RangeSet is union-only and a `data(in:) == nil` skip is still marked disassembled, so re-Load serves pre-Load instructions (handoff 05 §2.5/§2.6). Both directly block Task 8's "switch between functions" acceptance.
- Task 8 surface per PLAN.md: `decompileCurrentFunction` (currently sets the permanent `// Decompiling...` placeholder), key output by the procedure's `persistentModelID`, `.task(id:)` in `DecompilerView` to cancel stale work, and either a `BinaryFile` adapter from `BinaryModel` or porting `Decompiler` to `BinaryModel` + `DisassemblyResult` (record the choice).
- Search state is not stored anywhere — closing/reopening a sheet or navigator resets filters. Not a bug at prototype scale; no action needed for Task 8.
- Dead-code candidates added by this task for the Task 11 sweep: `SearchView` (`UI/Components/SearchView.swift`) and, if unreferenced after Task 11's own deletions, AppState `search(query:type:)` / `searchFunctions/Strings/Symbols` / `searchResults` / `isSearching` / the global `SearchType` (AppState.swift:1590) — but grep for other references before deleting.

## 5. Manual UI smoke steps (for the user, at end of session)

1. New document → Import Binary... (⇧⌘O) → pick `.qwen/tmp/thin_test` → Programs navigator → **Load...**.
2. **Functions tab:** type a partial name (e.g. `sum`) → list narrows to `sumOfSquares`; clear the field → full list back. Clicking a row still selects/disassembles.
3. **Strings tab:** type `sum` → only the `sumOfSquares(3, 4) = ` row remains; tap it → `goToAddress` lands at `0x100000b00`.
4. **Symbols / Imports / Exports tabs:** type any prefix of a visible name → list narrows (underscore-stripped display names, so type without the leading `_`); tap a row → `goToAddress`.
5. **Search sheet** (toolbar search button or ⌘-menu "Search..."):
   - *Symbols*: type a name prefix → up to 50 hits, tap → jumps to address, sheet closes.
   - *Functions*: same, matched on the short display name.
   - *Strings*: type `sum` → hit at `0x100000b00`.
   - *Addresses*: type `0x100000b00` → single Address row.
   - Esc (or the xmark) closes the sheet.

## 6. Risks / known interim states

- Every keystroke re-filters the full `@Query` array (navigators) or re-fetches from the document store (SearchSheet). Fine at prototype scale (hundreds–thousands of rows); the documented upgrade is `#Predicate` for the four name-based lists (never possible for Strings while `value` is `@Transient`).
- `SearchSheet` searches the **whole document** (all binaries in it), not just `selectedBinary` — deliberate (a search sheet is expected to search everything open); per-binary scoping can be added if multi-binary documents make it noisy.
- `SearchView`/legacy `appState.search` path still compiles but is unreferenced from the UI (see §2.4) — Task 11 candidate.
- The `.addresses` SearchSheet case is a pure hex parse (no validation that the address is backed by a segment) — same behavior as the original commented code; `goToAddress` on an unmapped address is a no-op-ish jump, pre-existing behavior.
