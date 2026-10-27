# Handoff 14 — Task 11 Schema housekeeping + dead-code deletion (Agent 15)

STATUS: IN PROGRESS

## Pre-flight

- `git status --short`: ` M ORCHESTRATOR_NOTES.md` (pre-existing; not mine to touch)
- HEAD: `1ae26cf`, branch `experiment/swift-data`
- Note: `.qwen/settings.json` reportedly dirty — `git status --short` shows only ORCHESTRATOR_NOTES.md at start; will not touch either way.

## Decision 1 — `.project` model list: KEEP the current 6

Current list (AetherKit/Sources/AetherKit/Schema/Schema.swift:4-14):
`[BinaryModel, SegmentModel, SectionModel, SymbolModel, AnnotationModel, BookmarkModel]`.
Not listed: `ProcedureModel`, `BlockModel`, `StringModel`, `CrossReferenceModel`.

**Decision: keep the current list (document = cascade).** Reasoning:

1. SwiftData's `Schema(_:)` initializer *automatically includes model types related to the ones provided* (Apple docs). All 4 unlisted models are reachable: `BinaryModel.procedures` (`.cascade`, inverse `\ProcedureModel.binary`), `BinaryModel.strings` (`.cascade`), `BinaryModel.references` (`.cascade`), and `ProcedureModel.blocks` (`.cascade`, inverse `\BlockModel.procedure`). So `Schema(.project)` resolves to the **same 10 model descriptions** with or without the 4 — the persisted store schema is byte-identical; only the list literal changes.
2. Undo/autosave operate at the `ModelContext` level, not per root-listed type: autosave fires on any pending context change regardless of model class, and undo is registered per object operation. Listing children at the root therefore **cannot change undo grouping or autosave behavior** — there is no behavioral alternative to "test"; the two lists produce identical schemas.
3. The list currently doubles as documentation of which types are document *roots* (directly openable/fetchable entry points) vs cascade children. Adding the 4 blurs that without benefit.
4. No schema-shape change → aether-cli's store access (`ModelContainer(for: .project)` in aether-cli/Sources/Aether.swift:28) is structurally unaffected, so the CLI store smoke is not required (still building the CLI as verification).

## Decision 2 — asymmetric commented inverses: REMOVE the dead comments, no code change

`ProcedureModel` (Schema.swift): `callers` is `@Relationship(deleteRule: .nullify, inverse: \ProcedureModel.callees)`; `callees` is a **plain** stored property with a commented-out `@Relationship` line. Same shape for `BlockModel.successors`/`predecessors`.

This is the **correct and only legal** SwiftData pattern for a self-referential to-many relationship: the inverse keypath is declared on exactly one side; the opposite side must be a plain property, which SwiftData keeps in sync automatically. You cannot "implement the missing inverse" — a second `@Relationship` declaration on the other side is not supported. The commented lines are dead suggestion-code → **delete both commented lines** (the "remove dead commented code" branch of the task). No relationship semantics change.

## Reference table (name → all repo refs → verdict)

Greps run over `*.swift` in Aether/, AetherKit/, aether-cli/ (whole repo):

| # | Candidate | References (file:line) | Verdict |
|---|-----------|------------------------|---------|
| 1 | `Project` struct | Models/Project.swift:4 (def) + intra-file only. (aether-cli `var project: String` and `UTType.project`/`Schema.project` are unrelated names) | **DELETE** (whole Project.swift, #2-#4) |
| 2 | `ProjectManager` | Models/Project.swift:50-51 (def) — zero external refs | **DELETE** |
| 3 | `ExportService` | Models/Project.swift:144 (def) — zero external refs (live exporter is `ExportManager` in Services/, untouched) | **DELETE** |
| 4 | `Bookmark` struct | Models/Project.swift:15,37 (intra-file), AppState.swift:1761 (comment), 1791-1792 (`UndoAction` cases) — all inside deletion closure (#5, #11) | **DELETE** |
| 5 | persistence tail: `saveProject` 1703, `loadProject` 1716, `openProject` 1734, `saveProjectAs` 1747, `ProjectData` 1796, `PatchData` 1803, `UndoAction` 1787 | Only mutual refs inside AppState.swift; **no menu commands or views call them** (grep of whole repo: zero other matches) | **DELETE** |
| 6 | `loadFile`/`openFile`/`closeFile` | No live definitions anywhere; only 2 commented refs (Scene/AetherContent.swift:152, AppState.swift:1721) | nothing to delete; comments die with their blocks (#5, #14) |
| 7 | `currentFile` | AppState:10 (def, **never assigned**); live consumers: Services/PluginSystem.swift:51, Services/ScriptingEngine.swift:72,132,141, UI/GraphView/CallGraphView.swift:48,53, UI/MainWindow/StatusBarView.swift:24,60,100,111, UI/DisassemblyView/ConditionalJumpsView.swift:182,187,222, UI/AnalysisViews/EntropyView.swift:112, UI/AnalysisViews/AIChatView.swift:48, UI/AnalysisViews/MalwareFlowView.swift:108, UI/AnalysisViews/MalwareDashboardView.swift:164, UI/AnalysisViews/AnalysisViews.swift:493; commented: Scene/AetherContent.swift:184 | **KEEP property** — NOT fully replaced: CallGraphView (`CallGraphViewModel.buildGraph(from: [Function], binary: BinaryFile)`:558), EntropyView (`EntropyAnalyzer.analyze(binary: BinaryFile)`), and PluginSystem (plugin API `analyze(binary: BinaryFile, context:)`:104,355,402,471) depend on the legacy `BinaryFile` type that has no model-based replacement yet (Task 12 ports analyzers). Re-point the 13 re-pointable gate/data sites to `selectedBinary` (Group F) and delete the 1 commented ref. Residual refs after: AppState:10, CallGraphView:48,53, EntropyView:112, PluginSystem:51. |
| 8 | old MachOLoader path | Aether/Core/Binary/MachOLoader.swift **whole file** = the legacy path: `extension MachOLoader: BinaryLoaderProtocol` (8), `canLoad` (14), `load(data:)` (21), `loadFatBinary` (37), `loadMachO` (69), `MachOHeader` (154), `parseMachOHeader` (157), `parseSegment32` (184), `parseSegment64` (~217), `parseSection32` (~256), `parseSection64` (~289), `parseSymtab` (~316), `processSymbol` (~348), `parseUnixThread` (~383). Everything private except `canLoad`/`load`, and those are reachable only via `BinaryLoader` dispatch (#9). `Self.mapCPUType` at :132 resolves to AetherKit/Sources/AetherKit/Load/MachOLoader.swift:365 — nothing app-side-only is lost. | **DELETE file** |
| 9 | `BinaryLoader` dispatch | Core/Binary/BinaryLoader.swift:11 (class def); only consumer: AppState.swift:170 `private let binaryLoader = BinaryLoader()` — and `binaryLoader` has **zero other refs** (whole-repo grep). `detectFormat` (45): def only. `BinaryLoaderProtocol` (5) is conformed to by ELFLoader:5, PELoader:6, JARLoader:8 (kept — Task 12 gives those loaders model paths) | **DELETE class + AppState property**; **KEEP `BinaryLoaderProtocol`** (ELF/PE/JAR conformance stays, untouched) |
| 10 | `SearchView` | UI/Components/SearchView.swift:3 (def) — **zero references** since Task 7 repointed `SearchSheetModifier` to `SearchSheet()` (Scene/AetherContent.swift:204) | **DELETE file** |
| 11 | search closure: `search(query:type:)` 1552, `searchAll` 1579, `searchFunctions` 1600, `searchStrings` 1611, `searchSymbols` 1621, `searchBytes` 1640, `parseAddress` 1669, `searchResults` 164, `isSearching` 165, `SearchResult` 1763, `SearchResultType` 1770, global `SearchType` 1778 | All intra-closure: `search` ← SearchView.swift:116 (deleted #10); `searchAll`/`searchBytes` only called from commented lines; `parseAddress` only from `search`/`searchAll` (GoToAddressSheet has its own local `parseAddress` in MainView.swift); `SearchResultRow`/`SearchResultType` ext only in SearchView.swift (deleted). The **live** `SearchSheet` (MainView.swift:139) uses its own *nested* `SearchType`/`SearchResult` — unaffected. | **DELETE** all of it |
| 12 | `decompileJavaMethod` | AppState:775 (def) — **zero callers** (Task 8 removed the commented Java call path; whole-repo grep confirms) | **DELETE** |
| 13 | `javaDecompiler` property | AppState:176 (def); only use: decompileJavaMethod:787 (deleted #12). The `JavaDecompiler` class (Core/Decompiler/JavaDecompiler.swift) stays — Task 12 | **DELETE property only** |
| 14 | inert patch stubs: `patchBytes` 1251, `nopInstruction` 1265, `revertPatch` 1279, props `patcher` 153, `patches` 154, `hasUnsavedChanges` 155 | `patchBytes` ← loadProject:1728 (deleted #5) only; `nopInstruction`/`revertPatch` — zero callers; props used only by the stubs' commented bodies + deleted tail (`saveProject` 1706 reads `patches`). Handoff 05 explicitly deferred these to Task 11. `BinaryPatcher` class file (Core/Binary/BinaryPatcher.swift) becomes fully unreferenced but is **not on the deletion list → KEPT**, flagged for follow-up | **DELETE stubs + 3 props** |
| 15 | `WelcomeView` | UI/MainWindow/MainView.swift:8 (def); refs: Scene/AetherContent.swift:185 **commented** only | **DELETE** |
| 16 | `LoadingOverlay` | UI/MainWindow/MainView.swift:54 (def); refs: Scene/AetherContent.swift:177 **commented** only | **DELETE** |
| 17 | `FormatBadge` | MainView.swift:35 (def); only used by WelcomeView:24-26 (deleted #15) | **DELETE** (closure of #15) |
| 18 | `OverlayModifier` + its call | Scene/AetherContent.swift:173 (def; body is 100% comments referencing #15/#16 + `loadingMessage`/`loadingProgress` which no longer exist on AppState), call at :47 | **DELETE** modifier + call (no-op after comments removed) |
| 19 | `OperandType.function` | Def DisassemblyView.swift:349; never produced — `classifyOperand` (DisassemblyView:274-302 and BranchVisualization:733-753) only emits `.register/.memory/.symbol/.immediate/.other`; comparison/switch sites: DisassemblyView:362,393 and BranchVisualization:788,830 | **DELETE case** + update the 4 sites (clean, 2 files) |

## NOT deleted (explicitly kept)

- Legacy model types `BinaryFile`, `Function`, `Symbol`, `Instruction` (Models/) — Task 12, still consumed by analyzers/decompiler (`EntropyAnalyzer.analyze(binary:)`, `FunctionAnalyzer`, `Decompiler`, `legacyBinary(for:)` Task 8 adapter, …).
- `ELFLoader`/`PELoader`/`JARLoader` legacy `BinaryFile` paths + `BinaryLoaderProtocol` — Task 12.
- `BinaryPatcher` class file — becomes unreferenced after #14 but is not on the Task 11 list; kept, flagged.
- `isLoading` (AppState:11, never set true — all writers are commented) — used live by StatusBarView:98,108; not on the list; kept, noted.
- `getXRefsTo/getXRefsFrom` stubs, `exportTo`/`ExportManager`, `analyzeMalware*` stubs — not on the list; kept.
- `AppState.legacyBinary(for:)` — Task 8 decompiler surface; untouched.
- aether-cli/Sources — untouched (hard rule).
- `.qwen/settings.json` — untouched (instruction).

## Work log

- **Group A** (AetherKit): replaced the two dead commented `@Relationship` inverse lines in Schema.swift with doc comments (ProcedureModel.callees, BlockModel.predecessors). `cd AetherKit && swift build` → `Build complete! (1.44 secs.)`.
- **Group B** (file): `rm Aether/Models/Project.swift` (Project, Bookmark, ProjectManager, ExportService).
- **Group C** (AppState.swift, 1808 → 1474 lines): deleted Patching State props (`patcher`/`patches`/`hasUnsavedChanges`), Search State props (`searchResults`/`isSearching`), `binaryLoader` prop, `javaDecompiler` prop, `decompileJavaMethod`, the 3 inert Patching stubs + `// MARK: - Patching`, the whole Search closure (`search`/`searchAll`/`searchFunctions`/`searchStrings`/`searchSymbols`/`searchBytes`/`parseAddress`), the persistence tail (`saveProject`/`loadProject`/`openProject`/`saveProjectAs` + `// MARK: - Project Save/Load`), and all Supporting Types (`SearchResult`/`SearchResultType`/global `SearchType`/`UndoAction`/`ProjectData`/`PatchData`). Kept `registerUndoRedo` (Task 5 undo) and `getXRefsTo/getXRefsFrom` stubs.
- **Group D** (file): `rm Aether/UI/Components/SearchView.swift` (SearchView, SearchResultRow, `extension SearchResultType`).
- **Build after B+C+D** → `** BUILD SUCCEEDED ** [6.056 sec]` (only the normal CapstoneKit "no rule to process file" warnings).
- **Group E**: `rm Aether/Core/Binary/MachOLoader.swift` (entire legacy `BinaryFile`-returning path; `Self.mapCPUType` resolves to AetherKit's at Load/MachOLoader.swift:365 — nothing app-side-only lost). BinaryLoader.swift: deleted the `BinaryLoader` class + `detectFormat`, kept `nonisolated protocol BinaryLoaderProtocol` (still conformed to by ELFLoader:5, PELoader:6, JARLoader:8 — Task 12 files, untouched). Closure of dispatch: class's only consumer was `AppState.binaryLoader` (deleted in C) and it had zero other refs. **Build after E** → `** BUILD SUCCEEDED ** [5.492 sec]`.
- **Group F** (re-point `currentFile` → `selectedBinary` + scene cleanup):
  - StatusBarView.swift: file-info `if let file = appState.selectedBinary` (`file.fileSize` → `file.data.count`), 3 gates → `selectedBinary`.
  - AIChatView.swift:48, AnalysisViews.swift:493, MalwareFlowView.swift:108, MalwareDashboardView.swift:164 — re-pointed.
  - ScriptingEngine.swift: `getCurrentBinary`/`readBytes`/`readString` blocks → `selectedBinary` (`fileSize` → `binary.data.count`).
  - ConditionalJumpsView.swift: both sites → `selectedBinary`; **plus two fixes the re-point surfaced**: added `import AetherKit` (AetherKit model members need it — `#MemberImportVisibility`) and `BinaryModel.data(in:)` returns `Data?` (legacy `BinaryFile.data(in:)` returned `Data`) → `guard let bytes = … else { continue }`.
  - AetherContent.swift: deleted `OverlayModifier` (100%-commented body referencing deleted WelcomeView/LoadingOverlay/nonexistent `loadingMessage`/`loadingProgress`) + its `.modifier(OverlayModifier())` call; also deleted the fully-commented `LoadOnDropModifier` block (its only live-adjacent ref was the commented `appState.loadFile(data:)`) and the 2 commented `.modifier(...)` lines.
  - **Build after F** → first attempt FAILED (ConditionalJumpsView optional-`Data` + missing AetherKit import, shown above); after fixes: `** BUILD SUCCEEDED ** [4.272 sec]` (one more intermediate fix: `import AetherKit` added to AnalysisViews.swift for the `selectedBinary?.name` member-visibility error — same `#MemberImportVisibility` class).
- **Group G**: MainView.swift — deleted `WelcomeView`, `FormatBadge`, `LoadingOverlay` (272 → 195 lines). Kept `GoToAddressSheet` and `SearchSheet` (SearchSheet's *nested* `enum SearchType` + `struct SearchResult` are the live search UI — untouched). **Build after G** → `** BUILD SUCCEEDED ** [3.666 sec]`.
- **Group H**: removed `Operand.OperandType.function` case (never produced: both `classifyOperand` implementations emit only register/memory/symbol/immediate/other) and cleaned the 4 comparison/switch sites: DisassemblyView.swift (`if operand.type == .symbol {`, `case .symbol: return .accent`) and BranchVisualization.swift (same two). **Build after H** → `** BUILD SUCCEEDED ** [3.784 sec]`.

## Final verification (real output)

1. `xcodebuild -project Aether.xcodeproj -scheme Aether -destination 'platform=macOS' build` → `** BUILD SUCCEEDED ** [1.124 sec]` (incremental; every intermediate group build also succeeded; only the normal CapstoneKit "no rule to process file" warnings).
2. `cd AetherKit && swift build` → `Build complete! (0.26 secs.)`; `swift test` → `Test run with 0 tests in 0 suites passed after 0.001 seconds.` (0 test cases expected).
3. `swift build --package-path aether-cli` → `Build complete! (6.39 secs.)`.
4. CLI store smoke: **SKIPPED** — Decision 1: no schema/model-list/relationship changes (`.project` list and all relationships byte-identical to before); CLI build (item 3) suffices.
5. Grep-proofs (all over `Aether AetherKit/Sources aether-cli/Sources`; empty unless noted):
   - `ProjectManager` / `ExportService` / `ProjectData|PatchData|UndoAction` / `saveProject|loadProject|openProject|saveProjectAs` / `SearchView|SearchResultType|SearchResultRow` / `decompileJavaMethod|javaDecompiler` / `hasUnsavedChanges` / `WelcomeView|LoadingOverlay|FormatBadge|OverlayModifier|LoadOnDropModifier` → **all empty**.
   - `revertPatch` → only `Aether/Core/Binary/BinaryPatcher.swift:210,244` (method *of* the kept `BinaryPatcher` class — expected, not a ref to the deleted AppState stub).
   - `(struct|enum|class) Project\b` and `Project(` → **empty** (remaining "project" identifiers are `UTType.project`/`Schema.project`/aether-cli `var project: String` — unrelated).
   - `\bBookmark\b` excluding BookmarkModel → **empty** (only `BookmarkModel` remains).
   - `\bBinaryLoader\b` → only `Aether/Core/Binary/JARLoader.swift:862` — a pre-existing comment "Data extensions are defined in BinaryLoader.swift" (comment stale on content but in a Task 12 file I was told not to touch; harmless).
   - `\bSearchType\b` → only MainView.swift:69,73,116 — the **nested** enum inside live `SearchSheet` (unrelated to the deleted global one).
   - `\bMachOLoader\b` → only AetherKit Load/MachOLoader.swift (model-based, kept) + its live callers (ProgramNavigator.swift:26, aether-cli Import.swift:31).
   - `type == .function` / `case function` → no `OperandType.function` refs; all hits are unrelated `SymbolType.function` (legacy Symbol — Task 12), `case functions` in the nested SearchSheet enum, and unrelated analyzer enums (`functionPrologue` etc.).
   - `\bcurrentFile\b` residual (documented, not dead): AppState.swift:10 (property, kept — never assigned, Task 12 analyzers need it), CallGraphView.swift:48,53 (`buildGraph(from: [Function], binary: BinaryFile)`), EntropyView.swift:112 (`EntropyAnalyzer.analyze(binary: BinaryFile)`), PluginSystem.swift:51 (plugin API), plus a local variable named `currentFile` in ConditionalJumpsView.swift:183,188 that now holds `selectedBinary` (cosmetic, left as-is).
   - `\b(loadFile|openFile|closeFile)\b` → **empty** (both commented refs died with LoadOnDropModifier and the loadProject tail).
- `git status --short`: exactly the intended 17 changes (3 deletions: Core/Binary/MachOLoader.swift, Models/Project.swift, UI/Components/SearchView.swift; 14 modifications listed below) + pre-existing ` M ORCHESTRATOR_NOTES.md` + untracked `.qwen/handoffs/14-task11-cleanup.md` (this file) and untracked `cartograph-dead-code-analysis.txt` (appears to be a build artifact of the Cartograph build-time check, not created by me — left in place, flag for orchestrator). **AetherKit/Package.resolved: unchanged.**

## Residuals / follow-ups (for later tasks)

- `BinaryPatcher` class file (Aether/Core/Binary/BinaryPatcher.swift) is now fully unreferenced (its only caller, the AppState patch stubs, was deleted). Not on the Task 11 deletion list → **kept**, flag for Task 12 or a future cleanup.
- `AppState.currentFile` property kept (never assigned; 4 documented Task-12 consumers). Can be deleted in Task 12 when the analyzers get model-based inputs.
- `isLoading` (AppState:11, never set true; used by StatusBarView) — not on the list, kept.
- Stale comment JARLoader.swift:862 (see grep-proofs).

## Manual UI smoke steps (for user)

1. Open the app (scheme Aether). Open/create an `.aetherproj` document.
2. Import `thin_test` via ⇧⌘O (Import Binary…), file at `.qwen/tmp/thin_test`.
3. In the Programs navigator, right-click the program → **Load…**. Confirm the disassembly pane populates and the status bar shows the file name/format/arch/size and "Ready" (status bar was re-pointed to `selectedBinary`).
4. Select a function, rename it (context menu / rename). Verify undo (⌘Z) restores the name.
5. Try the disassembly operand rendering (a `call`/`jmp` to a known symbol should render as a clickable symbol — `OperandType.function` removal path) and the conditional-jumps sheet if available (`analyzeJumps` now reads from `BinaryModel`).
6. Close the document, reopen it. Confirm the program persists, the rename persists, and disassembly re-loads.

STATUS: COMPLETE
