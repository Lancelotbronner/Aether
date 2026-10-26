# Plan: complete the SwiftData migration

Rewritten 2026-10-26 by Agent 1 (exploration pass) on branch `experiment/swift-data`, HEAD `1c51b64`.
Replaces the deleted phase-based plan (recovered copy: `.qwen/tmp/PLAN.md.prev`) and folds in the SwiftUI anti-pattern audit (recovered copy: `.qwen/tmp/SwiftUI.md.prev`).

## Current state (verified against code at 1c51b64, 2026-10-26)

### Document layer — working

- `AetherScene` is a `DocumentGroup` on the private `_SwiftData_SwiftUI` bridge: `editing: .project`, `contentType: .project`, per-document `ModelContainer`, built-in autosave. `prepareDocument` is empty and `bootstrap()` is commented out — **this is not a gap**: file entry is the `AetherCommands` "Import Binary..." (⇧⌘O) `.fileImporter(allowedContentTypes: [.executable])`, which creates a `BinaryModel` (`data` = mapped file bytes, `fileURL`, `name`) and inserts it; the Programs navigator's "Load..." context menu then parses it via `Task { @concurrent in try await MachOLoader.load(binary) }`, and "Delete" removes it via `modelContext.delete`.
- `AetherRootView` owns `@State session = AppState()` per window, injected via `.environment(session)`, `.focusedSceneValue(session)`, `.focusedSceneValue(\.modelContext, context)`.

### AppState — hybrid

- Selection is model-based and adopted: `selectedBinary/selectedSegment/selectedSection/selectedFunction: *Model?`, `selectedAddressRange`. `currentFile: BinaryFile?` remains and is **never set** — everything gated on it is permanently dead (see B6).
- ~25 stubbed analysis methods (`analyzeAll`, `findFunctions`, `analyzeCrypto`, …; the whole Analysis menu calls them). `decompileCurrentFunction` is a stub that sets `decompilerOutput = "// Decompiling..."` permanently (F1 dormancy, confirmed in `DecompilerView` which does `.task { appState.decompileCurrentFunction() }` and then shows the non-empty placeholder forever).
- Renames, comments, bookmarks live in plain dictionaries (bookmarks use the old `Bookmark` struct from `Models/Project.swift`); undo goes through a manual `registerUndoRedo`, not `modelContext.undoManager`.
- `symbolsByAddress` / `functionsByAddress` / `symbolsByName` caches are **never populated** — everything reading them (OperandsView resolution) is dead (B10).
- `clearDisassemblyCache` (D11) indexes a possibly-empty instruction map (crash) and never touches the `disassembled` RangeSet (B5).
- Persistence tail `saveProject/loadProject/openProject/saveProjectAs` + `ProjectData`/`PatchData`/`UndoAction` (~1508–1620): **zero callers — dead**.

### Schema (`Aether/Schema/Schema.swift`)

- `UTType.project`: `.package`-conforming, `com.lancelotbronner.aetherproj`.
- `Array<any PersistentModel.Type>.project` = `[BinaryModel, SegmentModel, SectionModel, SymbolModel, AnnotationModel, BookmarkModel]`. **ProcedureModel/BlockModel/StringModel/CrossReferenceModel are not listed** — reachable only via the `BinaryModel` cascade.
- `BinaryModel`: `data: Data` (file bytes), `baseAddress`; bounds-guarded `data(in:)`/`span(in:)`; **but `read(at:count:)`/`readString(at:)` index the Data with the raw virtual address — no baseAddress adjustment (B8)**.
- `SymbolModel`: `size: UInt64 = 1` default, never assigned by the loader (B2); `#Unique<SymbolModel>([\.binary, \.address])`.
- `StringModel`: `@Transient cached: String?`, `value = cached ?? "not loaded"` — nothing populates `cached` (B11).
- Asymmetric commented-out inverses: `ProcedureModel.callees` declares inverse `\ProcedureModel.callees` while the reverse side is commented (same for `BlockModel.successors/predecessors`).

### Navigators — all `@Query`

- `FunctionsNavigator`: `@Query [ProcedureModel]`, working model-selection binding, context menu (Rename/Go to/Copy); search filter commented out; size column shows `1 B` for every function (B2 visible).
- `StringsNavigator` / `SymbolNavigator` / `ImportsListView` (`#Predicate { $0.isImport }`) / `ExportsListView`: `@Query`-driven, **button rows only** (row tap = `goToAddress`, no selection binding); all search filters commented out (B12).
- `ProgramNavigator`: `@Query [BinaryModel]` hierarchy (program/segment/section) with selection tags, "Load..." and "Delete" context menus, auto-selects when exactly one program exists.

### Views

- `DisassemblyView`: model-driven (`selectedFunction` → `appState.disassembleFunction(_:)`, else `selectedSection` → `disassemble(section:)`), `@State instructions: ArraySlice<Instruction>`, 500-instruction cap, `BranchAnalyzer`, selection via `appState.select(addressRange)`. OperandsView resolves symbols through the dead AppState caches (B10).
- `HexView`: on `selectedSection` change does `data = section.binary.data` (whole file) with `baseAddress = section.address` — bytes shown are file bytes labeled from the section address (B9); `scrollTo` builds all rows (performance FIXME).
- `DecompilerView`: F1 as above.
- `AetherToolbar`: Analyze/AI/Malware/Plugins menus + Go-to disabled on `currentFile == nil` (B6); the "CFG" button calls `appState.analyzeAll()` instead of showing the CFG panel (B7/N2).
- `UI/MainWindow/MainView.swift`: hosts the **live** `GoToAddressSheet` and `SearchSheet` (used by AetherContent sheets; SearchSheet's result cases are commented out — a shell), plus `WelcomeView`/`LoadingOverlay` which are **likely dead — unverified**.
- `Inspector/Inspector.swift`: reads `appState.selectedInstruction`, bytes via `selectedBinary.format(hex:)`, p-code via `appState.pcode`; comment display commented out.

### Disassembler

- `DisassemblerEngine` (actor) is **model-agnostic**: single `func disassemble(data: Data, address: UInt64, architecture: Architecture) -> DisassemblyResult` with a static Capstone dict keyed by `CapstoneArch` and a JVM fallback. **No port needed.** (Resolves an open question from the old plan.)
- `DisassemblyResult { instructions: [Instruction]; pcode: [Pcode] }` uses the legacy `Instruction` type — that's fine until the analyzer/decompiler conversion (Task 12).

### Loaders

- `MachOLoader` has a **dual path**:
  - New: `@concurrent static func load(_ model: BinaryModel) async throws` → `machO(for:)`. Segment address = `vmaddr` (correct), section address = `sectheader.addr` (correct). **LC_SYMTAB is broken (B1)**: `bytes` is the per-load-command stream (advanced `cmdsize` per iteration), yet `strings = bytes.extracting(droppingFirst: Int(command.stroff))` and `symbolBytes = ...droppingFirst: Int(command.symoff)` apply the **file-relative** `stroff`/`symoff` to the command-relative base → names are garbage. The old path had the correct form: `strOffset = binaryOffset + Int(symtab.stroff)` into the whole file.
  - `symbol.size` is never assigned (B2). `nlist_64` has **no size field** — must be derived (see Task 1).
  - Fat handling is commented out → `fatalError("32-bit files aren't supported")` also fires for fat and non-Mach-O inputs (B3). **No re-parse guard**: a second "Load..." appends duplicate segments/symbols (`#Unique([\.binary, \.address])` conflict risk).
  - Old path intact: `load(data:) -> BinaryFile`, `loadFatBinary`, `parseSegment32/64`, `parseSection32/64`, `parseSymtab`, `processSymbol` (`size: 0`), `parseUnixThread`, `mapCPUType`.

## Known bugs (all code-verified in the 2026-10-26 pass)

| ID | Bug | Where |
| --- | --- | --- |
| B1 | LC_SYMTAB: file-relative `stroff`/`symoff` applied to the command-relative byte stream → symbol names garbage/empty | `MachOLoader.machO(for:)` |
| B2 | `symbol.size` never assigned → default 1 → every function disassembles to one byte; FunctionsTab shows "1 B" | `MachOLoader.machO(for:)`, visible via `Text(Int64(function.symbol.size), format: .byteCount(style: .memory))` |
| B3 | Fat (0xcafebabe) / 32-bit (MH_MAGIC) / non-Mach-O input → `fatalError`; fat handling commented out; no re-parse guard (duplicate appends) | `MachOLoader.load(_:)` |
| B4 | G1 remnant: `sectionNavigator` setter ignores `newValue` (functionNavigator was fixed) | `AppState` |
| B5 | D11: `clearDisassemblyCache` indexes an empty instruction map (crash) and never maintains the `disassembled` RangeSet | `AppState` |
| B6 | L1 variant: toolbar Analyze/AI/Malware/Plugins/Go-to clusters permanently disabled on never-set `appState.currentFile == nil` | `AetherToolbar` |
| B7 | N2: toolbar "CFG" button calls `appState.analyzeAll()` instead of showing the CFG panel | `AetherToolbar` |
| B8 | `BinaryModel.read(at:count:)` / `readString(at:)` use raw virtual addresses as Data offsets (no baseAddress adjustment) | `Schema.swift` |
| B9 | HexView shows whole-file bytes mislabeled from `section.address` | `HexView` |
| B10 | OperandsView symbol resolution reads never-populated AppState caches | `DisassemblyView` |
| B11 | `StringModel.cached` never populated → Strings tab shows "not loaded" | loader/AppState |
| B12 | Search filters commented out in all 5 navigators; SearchSheet result cases commented out | `Navigator/*`, `MainView.swift` |

## Dead code (grep-verified: zero external references)

- `ProjectManager` (singleton, Application Support + UserDefaults "RecentProjects") — dead.
- `ExportService` (takes old `[Instruction]` + `BinaryFile`) — dead. `ExportManager` in `Services/` is the **live** exporter.
- `Project` struct — dead.
- AppState `saveProject/loadProject/openProject/saveProjectAs` + `ProjectData`/`PatchData`/`UndoAction` — dead.
- `Bookmark` struct (`Models/Project.swift`) is **live** (AppState bookmarks dict) — delete only after Task 5 migrates bookmarks to `BookmarkModel`.
- `WelcomeView`/`LoadingOverlay` (`UI/MainWindow/MainView.swift`) — likely dead, **unverified**; verify by build in Task 11.

## Build / test baseline (2026-10-26)

- `xcodebuild -project Aether.xcodeproj -scheme Aether -destination 'platform=macOS' build` → `** BUILD SUCCEEDED ** [12.287 sec]`, exit 0; only CapstoneKit "no rule to process file" warnings.
- `cd AetherKit && swift test` → pass, **0 test cases** (XCTest 0 + swift-testing 0).
- `cd CoreAether && swift test` → pass, **0 test cases**.
- Note: there is no meaningful automated test coverage; acceptance is build + manual smoke.

## Conventions

- **Indentation:** tabs, not spaces. App target is Swift 5 (MainActor default isolation, experimental Lifetimes); packages are strict Swift 6.
- **Build** (after every task; do NOT use the xcode MCP server — it cannot enumerate schemes of the single-file `project.xcproj`):
  ```sh
  xcodebuild -project Aether.xcodeproj -scheme Aether -destination 'platform=macOS' build
  ```
- **Smoke binary:** `/bin/ls` (thin arm64 Mach-O). Flow: new document → Import Binary... (⇧⌘O) → pick the binary → Programs navigator → "Load...".
- **Handoff convention:** each executing agent appends a dated entry to the Progress log below and writes its own handoff file `.qwen/handoffs/NN-slug.md` (findings, decisions, exactly what the next agent needs). The orchestrator commits between agents.
- **No commits by agents.** Orchestrator only.
- One task per agent session; the app must build after each task.

## Tasks

### Task 1 — Fix LC_SYMTAB: real symbol names + sizes (B1, B2)

- **Goal:** after "Load...", symbols have real names and sane sizes; functions disassemble to their full body.
- **Files:** `Aether/Core/Binary/MachOLoader.swift` (possibly `Aether/Schema/Schema.swift` for `addressRange` semantics).
- **Steps:**
  1. `stroff`/`symoff` are **absolute file offsets**. The thin image is at offset 0 in `model.data`, so read them straight from `model.data` via bounds-guarded access (existing `data(in:)`-style accessor), *not* from the per-load-command `bytes` stream. The old path's `strOffset = binaryOffset + Int(symtab.stroff)` is the reference form.
  2. `nlist_64` has no size field. Two passes: collect `(address, n_sect, type, name)` in pass 1; per section sort by address; `size = next.address − this.address`, 0 if last/unknown. Keep `size` 0 (or 1 as a last-symbol fallback — record the decision in the handoff) for `N_ABS`/`N_UNDF`.
  3. Procedures are still created only from `N_SECT` (N_ABS → `.unknown` is already correct).
- **Acceptance:** with `/bin/ls`: Symbols tab shows real names (`_main`, `_dyld_*`, …); FunctionsTab sizes are not "1 B"; clicking a function disassembles the whole function (many instructions, sensible end).
- **Verification:** build (green) + the smoke flow above. Test with a fresh document per run — Task 2's re-parse guard doesn't exist yet, so repeated "Load..." appends duplicates.

### Task 2 — Loader robustness: no crashes, idempotent re-parse (B3)

- **Goal:** unsupported formats fail cleanly; "Load..." is idempotent.
- **Files:** `Aether/Core/Binary/MachOLoader.swift` (new `MachOError` enum or reuse existing error type).
- **Steps:** replace `fatalError` with a thrown typed error for: fat (`0xcafebabe`), 32-bit (`0xfeedface`), non-Mach-O (header mismatch). Add a re-parse guard at the top of `machO(for:)`: if `model.segments` is non-empty, return (or reset first — record the choice).
- **Acceptance:** "Load..." on a fat binary (e.g. `/usr/bin/python3.13` if fat, or any Homebrew fat binary) and on an ELF file logs/records an error and does not crash; "Load..." twice → no duplicate segments/symbols; no `#Unique` conflict log.
- **Verification:** build + both manual checks above.
- **Updates from Agent 2's Task 1 findings (2026-10-26):**
  - All system binaries are **fat 3-arch** — the smoke flow needs a freshly compiled thin binary (see handoff 02 for the exact `swiftc` command; keep the produced binary in `.qwen/tmp/`).
  - `symoff`/`stroff` are **slice-relative** in fat images (`binaryOffset + symoff`); the thin path (base 0) is what Task 1 shipped. Record this for whoever adds slice support (Task 12 territory) — do not slice in this task.
  - Use `unsafeLoadUnaligned` for any new struct reads at computed offsets.
  - Watch for `#Unique<SymbolModel>([\.binary, \.address])` violations when loading a real thin binary (local+global aliases share an address); dedupe or drop the constraint and record the choice.

### Task 3 — Session fixes: G1 remnant, N2, toolbar enablement (B4, B6, B7)

- **Goal:** sections are selectable; toolbar reacts to the imported model; CFG button shows the CFG panel.
- **Files:** `Aether/Models/AppState.swift`, `Aether/Scene/AetherToolbar.swift` (and `AetherCommands.swift` if it also gates on `currentFile`).
- **Steps:**
  1. `sectionNavigator` setter must honor `newValue` (mirror the fixed `functionNavigator`).
  2. Replace every `appState.currentFile == nil` gate with `appState.selectedBinary == nil`.
  3. "CFG" button → set the CFG-panel visibility flag (verify the exact flag name in `AppState`/`AetherContent` — the bottom panel shows CFG/HexView).
- **Acceptance:** after Import + Load, toolbar menus/buttons are enabled; CFG button toggles the bottom CFG panel; clicking a section row in the Sections tab selects it (disassembly follows the section).
- **Verification:** build + the smoke flow.

### Task 4 — D11: make `clearDisassemblyCache` safe (B5)

- **Goal:** no crash path, correct cache invalidation.
- **Files:** `Aether/Models/AppState.swift`.
- **Steps:** find all callers. If zero: delete the method. If referenced: make it bounds-safe (guard empty `instructions`, remove by address-range membership, maintain the `disassembled` RangeSet alongside the instruction array).
- **Acceptance:** build; if deleted, grep shows zero references; if fixed, no path can index an empty map.
- **Verification:** build + grep.

### Task 5 — Modelize annotations, bookmarks, renames; undo via modelContext

- **Goal:** user metadata lives in SwiftData models and survives close/reopen; undo uses the document's undo manager.
- **Files:** `Aether/Models/AppState.swift`, `Aether/Schema/Schema.swift` (`BookmarkModel` exists; verify fields), the Rename/Comment/Bookmark sheet call sites.
- **Steps:**
  1. `setComment/getComment` → look up / insert `AnnotationModel` (`.inline`/`.trailing`) via `modelContext`.
  2. `addBookmark/removeBookmark` → `BookmarkModel` insert/delete.
  3. Renames → write the model's name field (verify which field on `SymbolModel`/`ProcedureModel`; drop the dict).
  4. Check `modelContext.undoManager` is non-nil in the document window; if so, route model writes through it and retire the manual `registerUndoRedo` paths they replace.
- **Acceptance:** rename a function, add a comment, add a bookmark → save, close, reopen the document → all three persist; ⌘Z reverts a rename in-session.
- **Verification:** build + the close/reopen smoke flow.

### Task 6 — Populate strings (B11)

- **Goal:** Strings tab shows real strings with correct addresses.
- **Files:** `Aether/Core/Binary/MachOLoader.swift` or `AppState` + `Aether/Core/Analysis/` (StringAnalyzer) + `Navigator/StringsNavigator.swift`.
- **Steps:** Mach-O has no string table, so scan the `__TEXT` segment bytes for C-strings (minimum length threshold) and insert `StringModel` rows with `cached` set. Decide and record: eager at Load (recommended for now) vs. on "Analyze".
- **Acceptance:** after Load of `/bin/ls`, the Strings tab lists real strings at correct addresses; row tap (`goToAddress`) lands on the string bytes.
- **Verification:** build + smoke.

### Task 7 — Search filters + SearchSheet (B12)

- **Goal:** every navigator filter works; the search sheet returns results.
- **Files:** `Aether/Navigator/*.swift`, `Aether/UI/MainWindow/MainView.swift` (SearchSheet).
- **Steps:** enable `searchText` in Functions/Strings/Symbols/Imports/Exports — in-memory `filter` is acceptable at prototype scale, `#Predicate` (name LIKE) is the upgrade path; re-enable the SearchSheet result cases against the models.
- **Acceptance:** typing in each navigator's field narrows its list; SearchSheet returns hits for symbol and string queries.
- **Verification:** build + manual per-tab check.

### Task 8 — Re-enable the decompiler (F1)

- **Goal:** selecting a function shows real decompiled pseudo-code.
- **Files:** `Aether/Models/AppState.swift` (`decompileCurrentFunction`), `Aether/UI/DecompilerView.swift`, `Aether/Core/Decompiler/Decompiler.swift` (consumes legacy types — build the `BinaryFile` adapter from `BinaryModel` per old plan §3.5, or port `Decompiler` to take `BinaryModel` + `DisassemblyResult` — record the choice).
- **Steps:** disassemble the selected function (already works via Task 1's sizes), run the decompiler, store output keyed by the procedure's `persistentModelID`; key the view with `.task(id:)` so switching selection cancels stale work; show running/done/failed states instead of the permanent `// Decompiling...` placeholder.
- **Acceptance:** select a function → real pseudo-code appears; switching quickly between two functions never leaves stuck/stale output.
- **Verification:** build + smoke.

### Task 9 — HexView slice + BinaryModel read fixes (B8, B9)

- **Goal:** hex view shows the section's own bytes at its real addresses.
- **Files:** `Aether/Schema/Schema.swift` (`BinaryModel.read(at:count:)`/`readString(at:)`), `Aether/UI/HexView.swift`.
- **Steps:** fix the readers to adjust by `baseAddress` (virtual → file offset) using bounds-guarded `data(in:)`; HexView should load only the section's byte slice (e.g. `binary.data(in:)` over the section's file range) with `baseAddress = section.address`.
- **Acceptance:** hex row addresses line up with the disassembly's addresses; spot-check a known address's bytes against `xxd` of the file.
- **Verification:** build + spot check.

### Task 10 — Operand symbol resolution (B10)

- **Goal:** operands that reference known addresses show symbol names and are navigable.
- **Files:** `Aether/UI/DisassemblyView.swift` (OperandsView), `Aether/Models/AppState.swift`.
- **Steps:** replace the dead cache reads with model-based lookups against `selectedBinary`'s `SymbolModel`/`ProcedureModel` (a session-side dictionary built at Load from the models is acceptable and simplest).
- **Acceptance:** in a test function containing calls/branches, target operands display the symbol name (accent styling) and clicking navigates to it.
- **Verification:** build + smoke.

### Task 11 — Schema housekeeping + dead-code deletion

- **Goal:** remove the verified-dead persistence layer; settle the two open schema questions.
- **Files:** `Aether/Schema/Schema.swift`, `Aether/Models/Project.swift`, `Aether/Models/AppState.swift`, `Aether/Core/Binary/MachOLoader.swift` (old path), `Aether/UI/MainWindow/MainView.swift`, `Aether/Scene/*` (if `currentFile` gates remain).
- **Steps:**
  1. Decide the `.project` model list: keep the current 6 (document = cascade) or explicitly add `ProcedureModel`/`BlockModel`/`StringModel`/`CrossReferenceModel`. Test the alternative for undo/autosave behavior changes before choosing; record the decision and why.
  2. Fix or remove the asymmetric commented inverses (`ProcedureModel.callees`, `BlockModel.predecessors`).
  3. Delete (after Tasks 2–5 make each safe): `Project`, `ProjectManager`, `ExportService`, the `Bookmark` struct (post-Task 5), the AppState persistence tail (`saveProject/loadProject/openProject/saveProjectAs`, `ProjectData`, `PatchData`, `UndoAction`), `currentFile` + `loadFile/openFile/closeFile` if fully replaced, the old `MachOLoader` `BinaryFile` path (`load(data:)`/`loadFatBinary`/`parse*`/`processSymbol`) **after** checking `BinaryLoader` dispatch, and `WelcomeView`/`LoadingOverlay` if unreferenced (verify by build after removal).
  4. Do **not** delete the legacy model types (`BinaryFile`, `Function`, `Symbol`, `Instruction`) — Task 12 territory.
- **Acceptance:** build clean; grep confirms zero references to every deleted name; the full smoke flow (import, load, rename, close, reopen) still works.
- **Verification:** build + grep + smoke.

### Task 12 — (larger, later) Convert analyzers/decompiler to models; retire legacy types

- **Goal:** eventually delete `BinaryFile`/`Function`/`Symbol`/`Instruction`; `BinaryLoader` dispatch goes to model-based loaders; ELF/PE/JAR loaders get model paths.
- **Steps (placeholder — split per-analyzer when reached):** port `Core/Analysis` analyzers one at a time to consume `BinaryModel`/`DisassemblyResult`-shaped inputs; port `Decompiler` if Task 8 used the adapter; add the ELF/PE/JAR model loaders; then delete the legacy types and the `DisassemblerEngine` `Instruction` return type in a final pass.
- **Acceptance:** each sub-step: build + the affected UI flow still works; final: legacy type names gone from grep.

## Open questions

- **Multi-binary documents:** default selection when a document holds >1 binary (auto-select only happens at count == 1 today).
- **Patching semantics vs autosave:** the embedded `Data` *is* the saved document; "revert to original file" = re-read `fileURL`. No separate patch layer exists post-migration.
- ~~**`#Unique<SymbolModel>([\.binary, \.address])`:** local + global symbols sharing an address on real binaries may collide — watch for conflicts in Tasks 1–2; drop the constraint if so.~~ **Resolved 2026-10-26 (Task 2 + orchestrator follow-up):** key is now `(binary, address, identifier)`; the loader dedupes exact (address, name) repeats in-pass, so aliases and address-0 imports all coexist.
- **`.project` list changes:** does adding the 4 cascade-only models alter undo/autosave behavior? (Task 11.)

## Progress log

Convention: each executing agent appends a dated entry here and writes `.qwen/handoffs/NN-slug.md`. The orchestrator commits between agents.

- **2026-10-11** — Direction analysis: migrate to SwiftData `DocumentGroup` via the private `_SwiftData_SwiftUI` bridge (option 2). SwiftUI anti-pattern audit completed; findings (G1, F1, D11, L1, N2, …) folded into the tasks above.
- **2026-10-12** — `DocumentGroup` + per-document `ModelContainer` landed (`591c157`); `Schema.swift` created; `ProjectDocument` deleted; `AetherRootView` per-window session pattern established. `MachOLoader.machO(for:)` parses segments/sections; LC_SYMTAB ported (`2551f10`, `83d09b3`) — carrying the then-unknown B1/B2 bugs. Function-selection crash fixed via bounds-guarded `data(in:)`; N_ABS symbols map to `.unknown`.
- **2026-10-25** — Selection fields retyped to `*Model`; `ProgramNavigator` selection tags; all six sidebar tabs `@Query`-based; `DisassemblyView` made model-driven; instruction selection fixed.
- **2026-10-26** — **Agent 1 (exploration):** full verification pass against code (this document's "Current state" + bug table B1–B12); build baseline green (xcodebuild Aether SUCCEEDED 12.3 s; AetherKit/CoreAether `swift test` pass, 0 test cases); dead code confirmed by grep (`ProjectManager`, `ExportService`, `Project`, AppState persistence tail); `DisassemblerEngine` confirmed model-agnostic (no port needed); old `PLAN.md`/`SwiftUI.md` (deleted from root in `1c51b64`) recovered to `.qwen/tmp/*.prev` and folded into this file.
- **2026-10-26** — **Agent 2 (Task 1: B1/B2) — entry backfilled by orchestrator** (agent did not write it or its handoff; see ORCHESTRATOR_NOTES.md). `machO(for:)` LC_SYMTAB now reads `symoff`/`stroff` as absolute file offsets from `model.data` (bounds-guarded, throws `corruptedFile` on truncated table); two-pass size derivation: per `n_sect`, sorted by `n_value`, `size = next − this`; **decision: size 0** for last-per-section, `N_ABS`, `N_UNDF` (an unknown size is not a fabricated 1-byte body); N_ABS/N_UNDF also get `.unknown` type + `.external`/`.undefined` binding. Verified by standalone script `.qwen/tmp/symtab_check.swift` (16-byte `nlist_64` stride from Apple's MachO overlay) — matches `nm` entry-for-entry on `/bin/ls` (93 entries, 91 `N_UNDF` + `__mh_execute_header`; no `_main`/`_dyld_*` in ls). Build green. **New facts for Task 2:** (a) all system binaries (`/bin/ls`, `/usr/bin/*`) are **fat 3-arch** — the thin-only loader path cannot load them; smoke needs a freshly compiled thin arm64 binary; (b) in fat images `symoff`/`stroff` are **slice-relative** (e.g. x86_64 slice at base `0x4000`: table at `0x4000+0x66e8`), so any fat/slice support must add the slice base (`binaryOffset + symoff`); (c) the new nlist read uses alignment-strict `Span.unsafeLoad` — switch to `unsafeLoadUnaligned` when introducing non-zero slice bases; (d) `#Unique<SymbolModel>([\.binary, \.address])`: the loader appends **all** entries, so local+global aliases at one address create duplicate `(binary, address)` rows — watch for SwiftData unique violations, dedupe if needed.
- **2026-10-26** — **Agent 3 (Task 2: B3 loader robustness).** `MachOLoader` model path no longer traps: magic gate at top of `machO(for:)` throws `BinaryLoaderError.unsupportedBinary` for fat (0xcafebabe/cigam) and 32-bit (0xfeedface/cigam) and `.invalidMagic` for non-Mach-O (`.invalidHeader` if <4 bytes) — new `BinaryLoaderError` cases, no parallel error type. `load(_:)` is now a thin wrapper delegating to `machO(for:)`; the dead commented fat block and the 32-bit `fatalError` are gone. **Re-parse guard: reset-first, not skip** — a previously *failed* load can leave partial rows (appends happen before later throws), which a skip guard would wedge forever; reset makes "Load..." idempotent and all four child relationships are `.cascade` so `removeAll()` deletes rows. Magic validation runs **before** the reset so a bad Load leaves previously parsed content intact. **`#Unique` decision: in-pass dedupe, keep the constraint** — per address the highest-preference entry wins (N_SECT > N_ABS > N_UNDF, external > local within a kind) so a real body is never replaced by an absolute constant or undefined stub; `#Unique<SymbolModel>([\.binary, \.address])` stays as the safety net. **Known consequence:** all N_UNDF symbols sit at address 0, so every binary's imports collapse to one representative row (thin_test: 13 imports → 1 row) — the Imports tab will look wrong until the constraint is revisited (e.g. unique on (binary, address, identifier)). Load... call site already logs thrown errors (`Logger.app.error`) — no change needed. No new struct reads, so no new `unsafeLoadUnaligned` sites. Smoke binary at `.qwen/tmp/thin_test(.swift)` (thin arm64, named funcs + global, runs: 25/55/67). Build green (`** BUILD SUCCEEDED ** [4.547 sec]`).
- **2026-10-26** — **Orchestrator follow-up to Task 2 (imports collapse):** Agent 3's per-address dedupe correctly satisfied `#Unique(binary, address)` but collapsed *all* N_UNDF imports (every import sits at address 0) to one row, gutting the Imports/Exports tabs. Fixed in-task-scope: `#Unique<SymbolModel>` → `(binary, address, identifier)` and the in-pass dedupe now keys on (address, name) — aliases (same address, different names) and imports (different names at 0) are all kept; only exact (address, name) repeats collapse. The safety net now surfaces as a model-save failure if a future path appends out-of-pass duplicates. Handoff 03 patched to match.
