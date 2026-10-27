# Handoff 15 — Task 12a legacy triage + dead-analyzer deletion (Agent 16)

STATUS: COMPLETE

## Pre-flight

- HEAD: `6dcb64c` (experiment/swift-data) — "Delete the dead persistence layer and re-point currentFile gates (Task 11)"
- `git status --short`:
  ```
  ?? cartograph-dead-code-analysis.txt
  ```
  (untracked, off-limits per instructions — not touched)

## Triage

**Method**: every file under `Aether/Core/` + `Aether/Services/` (and every other file) referencing `BinaryFile`, `Function`, `Symbol`, `Instruction` was identified, then each candidate name was grepped repo-wide (`Aether AetherKit aether-cli`). No AetherKit/ or aether-cli/ reference to any candidate legacy name exists (verified). A name is **DEAD** only if its entire repo-wide reference set lies inside the deletion closure (dead views → commented sheets in `Aether/Scene/AetherContent.swift:34-80`, commented stub bodies, or other dead code). All 15 analysis-sheet instantiations in `AetherContent.swift` are commented; the only LIVE sheet is `CallGraphWindowView()` at `:154`, plus LIVE DetailView children `DisassemblyView`/`DecompilerView`/`CFGView`/`HexView`/`StatusBarView`.

### Aether/Core/Analysis/

| File | Consumes (legacy) | Repo-wide references (besides self) | Verdict |
| --- | --- | --- | --- |
| AIAnnotator.swift | BinaryFile, Function | **none** | **DEAD → delete file** |
| AdvancedDataFlowAnalyzer.swift | Instruction, BinaryFile, Function | Deobfuscator (dead), TypeRecovery (dead), AnalysisWrappers (dead), ControlFlowStructurer `StructuredCodePrinter` (dead class, zero refs of its own) | **DEAD → delete file** (after StructuredCodePrinter removal) |
| AnalysisWrappers.swift | (wraps dead Deobfuscator/TypeRecovery results) | AppState props `deobfuscationReport`/`recoveredTypes` (pruned), AnalysisViews dead views (pruned), Deobfuscator + TypeRecovery (deleted) | **DEAD → delete file** |
| ControlFlowStructurer.swift | Function, BasicBlock | **LIVE**: Decompiler.swift:7 (`structurer =`), :766/:770/:866/:1031 | **LIVE → keep file**; internal `class StructuredCodePrinter` (~:692) has **zero** references (Decompiler uses its own `EnhancedCodePrinter` at Decompiler.swift:756) → **remove dead class**; it is the sole remaining `AdvancedDataFlowAnalyzer.DataFlowResult` ref (:694/:698) |
| CryptoDetector.swift (AdvancedCryptoDetector) | BinaryFile | AppState:312 (comment), AnalysisViews:78 (dead view, pruned), PluginSystem (dead, deleted) | **DEAD → delete file** |
| DataFlowAnalyzer.swift | Instruction | **none** | **DEAD → delete file** |
| Deobfuscator.swift | BinaryFile, Function, BasicBlock, AdvancedDataFlowAnalyzer | AnalysisWrappers (deleted), AppState (comment only) | **DEAD → delete file** |
| DWARFParser.swift | BinaryFile | **none** | **DEAD → delete file** |
| EntropyAnalyzer.swift | BinaryFile | class: MalwareAnalyzer class (dead), EntropyView (dead view), PEAnomalyDetector class (dead) | **SPLIT: keep `EntropyResult`/`SectionEntropy`/`EntropyBlock`** (LIVE-anchored: `MalwareReport.entropyResult`, and MalwareReport is LIVE via AetherToolbar:106); **delete `EntropyAnalyzer` class** |
| FunctionAnalyzer.swift | Function, BinaryFile | AppState `functionAnalyzer` prop (pruned); all call sites commented | **DEAD → delete file** |
| IdiomRecognizer.swift | BinaryFile, Function | AnalysisViews:369 (dead view, pruned), AppState (comment) | **DEAD → delete file** |
| IoCExtractor.swift | BinaryFile | class: MalwareAnalyzer class (dead) | **SPLIT: keep `IoCReport`** (LIVE via `MalwareReport.iocReport`); **delete `IoCExtractor` class** |
| MalwareAnalyzer.swift | BinaryFile, PELoader | `MalwareReport` struct: **LIVE** (AetherToolbar:106 `appState.malwareReport == nil`, Scene untouchable) + AppState prop; class: AppState `analyzeMalware` stub (commented body) | **SPLIT: keep `MalwareReport`** (+ `ThreatLevel`); **delete `MalwareAnalyzer` class** |
| ObjCAnalyzer.swift | BinaryFile | **none** | **DEAD → delete file** |
| PackerDetector.swift | BinaryFile | class: MalwareAnalyzer class (dead) | **SPLIT: keep `PackerResult`** (LIVE via `MalwareReport.packerResults`); **delete `PackerDetector` class** |
| PEAnomalyDetector.swift | BinaryFile | class: MalwareAnalyzer class (dead) | **SPLIT: keep `PEAnomaly`** (+ `Severity`, LIVE via `MalwareReport.anomalies`); **delete `PEAnomalyDetector` class** |
| SignatureMatcher.swift | BinaryFile | **none** | **DEAD → delete file** |
| SwiftAnalyzer.swift | BinaryFile | **none** | **DEAD → delete file** |
| TypeRecovery.swift | BinaryFile, Function, AdvancedDataFlowAnalyzer | AnalysisWrappers (deleted), AppState (comment) | **DEAD → delete file** |
| XRefAnalyzer.swift | BinaryFile, Function | AppState `xrefAnalyzer` prop (pruned); all call sites commented | **DEAD → delete file** |

### Aether/Core/Binary/ (entire directory DEAD)

| File | References (besides self) | Verdict |
| --- | --- | --- |
| BinaryLoader.swift (protocol) | only the 3 legacy loaders below | **DEAD → delete** (live loader is `AetherKit/Sources/AetherKit/Load/MachOLoader.swift`, distinct `BinaryLoaderError`) |
| BinaryPatcher.swift | **none** | **DEAD → delete** |
| ELFLoader.swift | **none** | **DEAD → delete** |
| JARLoader.swift | JavaDecompiler (dead, deleted) | **DEAD → delete** |
| PELoader.swift | MalwareAnalyzer class (deleted) | **DEAD → delete** |

### Aether/Core/Decompiler/

| File | Verdict |
| --- | --- |
| Decompiler.swift | **LIVE** (Task 8 surface: `decompileCurrentFunction` → `Decompiler`). Consumes `Function`/`BinaryFile`/`Instruction`/`BasicBlock` — recorded, ported in later slice. Keep untouched. |
| JavaDecompiler.swift | **DEAD → delete** (zero references besides self; references JARLoader) |

### Aether/Core/Disassembler/

| File | Verdict |
| --- | --- |
| DisassemblerEngine.swift | **LIVE** (AppState `disassembler`, `disassembleIfNecessary`). Keep. |
| CapstoneDisassembler.swift | **LIVE** (pipeline). Keep. |
| DisassemblerPlugin.swift | **LIVE** (protocol conformed by CapstoneDisassembler). Keep. |
| DisassemblyInstruction | **LIVE** (DisassemblerEngine, CapstoneDisassembler, `Instruction.init` at Models/Instruction.swift:27). Keep. |
| JavaDisassembler.swift | **LIVE → keep** — file defines `extension DisassemblerEngine` (no type named `JavaDisassembler`); `disassembleJVM(data:address:)` is called from the LIVE engine at DisassemblerEngine.swift:92 (`case .jvm` branch). Part of the disassembly pipeline. (Initial "zero references" was a false negative — the grep searched the filename, not the extension's members.) |

### Aether/Core/Emulation/

| File | Verdict |
| --- | --- |
| Emulator.swift | **DEAD → delete** (zero references besides self). |

### Aether/Services/

| File | Verdict |
| --- | --- |
| AIClient.swift | **LIVE** — `AppState.aiClient` + `suggestVariableNames()` (LIVE method, toolbar "Rename Variables") calls `aiClient.suggestVariableNamesAsync`. Keep whole file (also defines `SecurityAnalysisResult`/`ChatMessage`/`MalwareFlowResult`/`CodeExplanation` value types, all plain data). |
| ExportManager.swift | **LIVE** — `ExportManager.ExportFormat` used by AetherCommands:129 (menu "Export to IDA Python..."). Keep. |
| FridaScriptGenerator.swift | **SPLIT**: enums `FridaPlatform` (:5) / `FridaHookType` (:12) **LIVE** (AetherToolbar ForEach/rawValue/icon + AppState `selectedFridaPlatform`/`selectedFridaHookType`, toolbar :118-131) → **keep**; `FridaScriptResult` (:36) / `AIFridaScriptResult` (:47) → **DEAD** (refs: AppState props to be pruned + FridaScriptView dead) → delete; `class FridaScriptGenerator` (:58+) → **DEAD** (only ref: AppState `fridaGenerator` prop, all call sites commented) → delete. File reduced to the two enums. |
| PluginSystem.swift | **DEAD → delete** (zero external references). |
| ScriptingEngine.swift | **DEAD → delete** (zero references besides self). |

### Other files referencing legacy types (triaged; deletions where provably dead)

| File | Consumes | Verdict |
| --- | --- | --- |
| Models/BinaryFile.swift, Function.swift, Symbol.swift, Instruction.swift, Disassembly.swift, Architecture.swift | (are the legacy types) | **KEEP** (explicitly out of scope; ported 12b/12c). `Disassembly.swift` kept: `DisassembledByte` used by `DisassemblyCollection` at BinaryFile.swift:145. `CrossReference` (Instruction.swift:105) kept (XRefsView was its only view consumer — deleted below; `getXRefsTo/From` pruned). |
| Models/AppState.swift | Function, Instruction, BinaryFile (stubs/helpers) | **PARTIAL PRUNE** — see "AppState deletions" below. LIVE parts untouched (Task 8/9/10/11 surfaces, disassembly cache, model-based renames/comments/bookmarks, kept stubs referenced by Scene). |
| UI/AnalysisViews/AIChatView.swift, AIRenameView.swift, ExplainCodeView.swift, SecurityAnalysisView.swift, FridaScriptView.swift, MalwareDashboardView.swift, MalwareFlowView.swift, EntropyView.swift, ImportExportBrowserView.swift | AppState + dead analyzer types (EntropyView instantiates `EntropyAnalyzer()` at :115) | **DEAD → delete all 9 files** (only instantiation sites are the commented sheets AetherContent:34-80) |
| UI/AnalysisViews/AnalysisViews.swift | contains 6 dead views (CryptoDetectionView, DeobfuscationView, TypeRecoveryView, IdiomRecognitionView, PseudoCodeView, ExportSheetView) + **LIVE `CallGraphWindowView`** (AetherContent:154) | **REDUCE to `CallGraphWindowView` only** |
| UI/Components/XRefsView.swift | `CrossReference`, AppState `getXRefsTo/From` | **DEAD → delete file** (zero instantiation sites repo-wide; sole consumer of `getXRefsTo/From`) |
| UI/Components/ThemeManager.swift | "Instruction" appears in comment/text only | **KEEP** (not a consumer) |
| UI/GraphView/CallGraphView.swift | `BinaryFile` (via `appState.currentFile`) | **LIVE** (inside `CallGraphWindowView`). Keep; `currentFile` stays. |
| UI/GraphView/CFGView.swift | — | **LIVE** (AetherContent:113). Keep. |
| UI/DisassemblyView/{DisassemblyView,HexView,BranchVisualization,ConditionalJumpsView}.swift | `Instruction` | **LIVE** (`BranchInfo` from BranchVisualization.swift used by DisassemblyView). Keep. |
| UI/DecompilerView/DecompilerView.swift | — | **LIVE**. Keep. |
| UI/MainWindow/StatusBarView.swift | — | **LIVE** (AetherContent:121). Keep. |
| UI/MainWindow/MainView.swift | — | **UNCERTAIN (KEEP)**: zero instantiation sites found, but not a legacy-type consumer and not in the analyzer island — out of task scope. Flagged for orchestrator. |
| Scene/AetherContent.swift, AetherCommands.swift, AetherToolbar.swift, AetherScene.swift | — | **OFF-LIMITS** (Scene). Everything they reference must keep compiling — this drives the "keep" list of AppState stubs + `show*` flags set by toolbar/commands. |

### AppState deletions (all grep-verified zero live refs post-deletion-closure)

**Forced (declared type is deleted):**
- props: `functionAnalyzer`, `stringAnalyzer`, `xrefAnalyzer`, `fridaGenerator`, `cryptoFindings` (AdvancedCryptoDetector.CryptoFinding), `deobfuscationReport` (DeobfuscationReportWrapper), `recoveredTypes` (RecoveredTypeWrapper), `recognizedIdioms` (IdiomRecognizer.Idiom), `fridaScriptResult` (FridaScriptResult), `aiFridaScriptResult` (AIFridaScriptResult)

**Orphaned data props (sole refs = deleted dead views / comments):**
- `structuredCode`, `securityAnalysisResult`, `securityAnalysisError`, `isAnalyzingWithAI`, `isAnalyzingMalware`, `isAnalyzingMalwareFlow`, `malwareFlowResult`, `malwareFlowError`, `isGeneratingFridaScript`, `fridaScriptError`, `preConfiguredBypassTechniques`, `preConfiguredPatchPoints`, `chatMessages`, `isChatLoading`, `chatError`, `codeExplanation`, `isExplainingCode`, `explainError`, `showExplainCode`, and orphan flags `showCryptoDetection`, `showDeobfuscation`, `showTypeRecovery`, `showIdiomRecognition`, `showPseudoCode`, `showSecurityAnalysis`, `showFridaScript`

**Methods (commented-only body or dead, zero live callers; all consume legacy types or feed deleted views):**
- `selectFunction(_:)` (legacy `Function`), private `buildBasicBlocks`/`generatePseudoCodeFromInstructions`/`extractCondition`/`arithmeticOp` (legacy `Instruction`/`Function`/`BinaryFile`; only call sites are commented lines inside `generateStructuredCode`), `sendChatMessage`, `clearChat`, `generateFridaFromSecurityAnalysis`, `getXRefsTo(address:)`/`getXRefsFrom(address:)` (live `[]` bodies, legacy `CrossReference`, sole caller = deleted XRefsView)

**Kept stubs (referenced by LIVE Scene menu/toolbar code — must stay even though bodies are commented):**
`analyzeAll`, `performAnalysis`, `findFunctions`, `runCryptoDetection`, `runDeobfuscation`, `runTypeRecovery`, `runIdiomRecognition`, `generateStructuredCode`, `exportTo`, `analyzeWithAI`, `analyzeBinaryWithAI`, `explainCurrentFunction`, `analyzeMalware`, `analyzeMalwareFlow`, `generateFridaScript`, `generateFridaScriptWithAI`, `generateMultiFunctionFridaScript` — plus LIVE members: `decompiler`, `aiClient`, `disassembler`, `currentFile`, `decompilerOutput`, `malwareReport`, `selectedFridaPlatform`/`selectedFridaHookType`, `suggestVariableNames` + rename UI block, all Task 8/9/10/11 surfaces, and every `show*` flag set by Scene (`showAIChat`, `showMalwareFlow`, `showMalwareDashboard`, `showEntropyView`, `showImportExportBrowser`, `showExportSheet`, `showJumpTable`, `showDecompiler`, `showHexView`, `showCFG`, `showGoToAddress`, `showSearch`, `showCallGraph`, …).

## Deletion plan (build after each group)

- **Group 1 — leaf dead files (15):** AIAnnotator, DataFlowAnalyzer, DWARFParser, SignatureMatcher, ObjCAnalyzer, SwiftAnalyzer (Analysis/); Emulator; JavaDisassembler; JavaDecompiler; PluginSystem, ScriptingEngine (Services/); BinaryLoader, BinaryPatcher, ELFLoader, JARLoader (Binary/).
- **Group 2 — analyzer island + dead views:** delete CryptoDetector, Deobfuscator, AdvancedDataFlowAnalyzer, FunctionAnalyzer, StringAnalyzer, XRefAnalyzer, IdiomRecognizer, TypeRecovery, AnalysisWrappers, PELoader; strip dead classes from MalwareAnalyzer/IoCExtractor/PEAnomalyDetector/PackerDetector/EntropyAnalyzer (keep value structs); remove `StructuredCodePrinter` from ControlFlowStructurer.swift; delete the 9 dead view files + XRefsView.swift; trim AnalysisViews.swift to `CallGraphWindowView`.
- **Group 3 — Services split + frida AppState prune:** strip FridaScriptGenerator class + result structs (keep enums); prune remaining frida AppState members (`fridaGenerator`, `fridaScriptResult`, `aiFridaScriptResult`, `isGeneratingFridaScript`, `fridaScriptError`, `preConfiguredBypassTechniques`, `preConfiguredPatchPoints`, `showFridaScript`).

## Group 1 — leaf dead files (DONE, BUILD SUCCEEDED)

Deleted (15 files): `Core/Analysis/{AIAnnotator,DataFlowAnalyzer,DWARFParser,SignatureMatcher,ObjCAnalyzer,SwiftAnalyzer}.swift`, `Core/Emulation/Emulator.swift` (dir removed), `Core/Decompiler/JavaDecompiler.swift`, `Services/{PluginSystem,ScriptingEngine}.swift`, `Core/Binary/{BinaryLoader,BinaryPatcher,ELFLoader,JARLoader,PELoader}.swift` (dir removed).
- Note 1: **JavaDisassembler.swift kept** — see corrected triage row (LIVE engine extension, `disassembleJVM` called at DisassemblerEngine.swift:92).
- Note 2: first group-1 build FAILED as expected — `PELoader` conformed to `BinaryLoaderProtocol` (deleted in-group) — fixed by pulling `PELoader.swift` deletion + `MalwareAnalyzer` class strip (kept `MalwareReport` struct) into the group. `MalwareAnalyzer.swift` now contains only the `MalwareReport` struct (+ `ThreatLevel`).
- Build: `xcodebuild -project Aether.xcodeproj -scheme Aether -destination 'platform=macOS' build` → **`** BUILD SUCCEEDED **`** [5.660 sec]. Remaining warnings are pre-existing (Decompiler/AnalysisWrappers/CryptoDetector/Deobfuscator/IdiomRecognizer/PEAnomalyDetector/AppState "never used" + AetherCommands security-scoped; most of those files are deleted in Groups 2-3).
- Note: `git status` also shows `M .qwen/team-memory/MEMORY.md` — pre-existing churn from before this agent's edits (agent wrote no team memory); not touched.

## Group 2 — analyzer island + dead views + AppState prune (DONE, BUILD SUCCEEDED)

Deleted whole files (10 analysis + 9 view + 1 component):
- `Core/Analysis/{CryptoDetector,Deobfuscator,AdvancedDataFlowAnalyzer,FunctionAnalyzer,StringAnalyzer,XRefAnalyzer,IdiomRecognizer,TypeRecovery,AnalysisWrappers}.swift`
- `UI/AnalysisViews/{AIChatView,AIRenameView,ExplainCodeView,SecurityAnalysisView,FridaScriptView,MalwareDashboardView,MalwareFlowView,EntropyView,ImportExportBrowserView}.swift`
- `UI/Components/XRefsView.swift` (zero instantiation sites repo-wide)

Rewritten to value-types-only (dead classes stripped, LIVE-anchored structs kept verbatim):
- `Core/Analysis/MalwareAnalyzer.swift` → `MalwareReport` only (done in Group 1)
- `Core/Analysis/IoCExtractor.swift` → `IoCReport` only
- `Core/Analysis/PEAnomalyDetector.swift` → `PEAnomaly` (+`Severity`) only
- `Core/Analysis/PackerDetector.swift` → `PackerResult` only
- `Core/Analysis/EntropyAnalyzer.swift` → `EntropyResult`/`SectionEntropy`/`EntropyBlock` only
- `Core/Analysis/ControlFlowStructurer.swift` → truncated at line 687, removing dead `class StructuredCodePrinter` (was :692–938; the sole remaining `AdvancedDataFlowAnalyzer.DataFlowResult` consumer)
- `UI/AnalysisViews/AnalysisViews.swift` → reduced to `CallGraphWindowView` only (LIVE, AetherContent:154); 6 dead views removed
- `Services/FridaScriptGenerator.swift` → reduced to enums `FridaPlatform`/`FridaHookType` + result structs `FridaScriptResult`/`AIFridaScriptResult` (Group 3 file, pre-truncated here; result structs kept — see risk R2)
- `Services/AIClient.swift` → removed dead `analyzeMalwareFlowAsync` + private `buildMalwareFlowPrompt`/`parseMalwareFlowResponse` (lines 126–283; sole caller was the commented `AppState.analyzeMalwareFlow` body). This also dropped the last uses of `MalwareFlowResult`/`MalwareFlowStage`, which were defined inside the now-deleted `MalwareFlowView.swift` — the build error that surfaced this is why the deletion happened here, not in the view group.

AppState.swift prune (1474 → 1179 lines):
- Props removed: `functionAnalyzer`, `stringAnalyzer`, `xrefAnalyzer`, `fridaGenerator`; `cryptoFindings`, `deobfuscationReport`, `recoveredTypes`, `recognizedIdioms`, `structuredCode`; `isAnalyzingWithAI`, `securityAnalysisResult`, `securityAnalysisError`; `chatMessages`, `isChatLoading`, `chatError`; `showExplainCode`, `codeExplanation`, `isExplainingCode`, `explainError`; `isAnalyzingMalware`; `isAnalyzingMalwareFlow`, `malwareFlowResult`, `malwareFlowError`; `isGeneratingFridaScript`, `fridaScriptResult`, `aiFridaScriptResult`, `fridaScriptError`, `preConfiguredBypassTechniques`, `preConfiguredPatchPoints`; orphan flags `showCryptoDetection`, `showDeobfuscation`, `showTypeRecovery`, `showIdiomRecognition`, `showPseudoCode`, `showSecurityAnalysis`, `showFridaScript`.
- Methods removed: `selectFunction(_:)`, private `buildBasicBlocks`/`generatePseudoCodeFromInstructions`/`extractCondition`/`arithmeticOp` (legacy `Instruction`/`Function`/`BinaryFile` consumers, comment-only callers), `sendChatMessage`, `clearChat`, `generateFridaFromSecurityAnalysis`, `getXRefsTo`/`getXRefsFrom`.
- Everything Scene-referenced kept (stubs `analyzeAll`…`generateMultiFunctionFridaScript`, `malwareReport`, `selectedFridaPlatform`/`selectedFridaHookType`, `showAIChat`/`showMalwareFlow`/`showMalwareDashboard`/`showEntropyView`/`showImportExportBrowser`/`showExportSheet`/`showJumpTable`/etc., Task 8 `decompileCurrentFunction`/`decompileOwner`/`decompiledOutputs`/`legacyBinary(for:)`, Task 10 operands, rename block incl. `suggestVariableNames`/`applySelectedRenames`).

Build: first build after file deletions **FAILED** — `AIClient.analyzeMalwareFlowAsync` referenced `MalwareFlowResult`/`MalwareFlowStage` (types lived in deleted `MalwareFlowView.swift`). Fixed by deleting that dead method + its two private helpers from AIClient.swift (zero live callers — only the commented `analyzeMalwareFlow` stub). Rebuild → **`** BUILD SUCCEEDED **`** [3.827 sec].

## Final verification (real output)

1. `xcodebuild -project Aether.xcodeproj -scheme Aether -destination 'platform=macOS' build` → **`** BUILD SUCCEEDED **`** (incremental 1.4 s; no CapstoneKit "no rule to process file" warnings appeared on the incremental pass; none new).
2. `cd AetherKit && swift build` → **`Build complete! (0.32 secs.)`**
3. `swift build --package-path aether-cli` → **`Build complete! (0.30 secs.)`**
4. Grep-proof (command: `for t in <46 deleted names>; grep -rn "$t" Aether AetherKit aether-cli --include='*.swift' | grep -v '^\s*//'`): **zero live (non-comment) hits for every deleted name.** Remaining hits are exclusively:
   - commented sheet lines in `Scene/AetherContent.swift:34-80` (e.g. `//  AIChatView()`) and commented stub bodies in `Models/AppState.swift` (e.g. `// let analyzer = MalwareAnalyzer()` at :135/:163, `// let detector = AdvancedCryptoDetector()` at :272, `// aiClient.analyzeMalwareFlowAsync(` at :191) — all inside KEEP-mandated stubs;
   - `runTypeRecovery` (kept Scene-referenced stub, matches substring `TypeRecovery`) + `showTypeRecovery` comment at AetherContent:39;
   - `showEntropyView` (LIVE flag set by AetherToolbar:123 — view itself deleted, flag kept per Scene rule);
   - `PluginContext` hits are inside `aether-cli/.build/checkouts/swift-argument-parser/` (third-party checkout, unrelated type).
5. `git diff --stat`: **45 files changed, 63 insertions(+), 20092 deletions(-)** (34 deletions + 11 rewrites + team-memory churn unrelated to this task).

## Risks / caveats

- **R1 (intended, flag for review):** all analysis menu/toolbar actions (Analyze → Find Functions/Crypto/Deobfuscate/Type Recovery/Idioms/Structured Code, AI Analyze/Explain, Malware Analyze/Flow, Frida generate, Export sheet, AI chat/explain/rename *sheets*, entropy/import-export dashboards) are now no-ops or show nothing — their sheets were already commented out before this task, so behavior is unchanged, but the orchestrator should confirm this matches the migration intent (features re-land when views are re-wired in later slices).
- **R2:** `FridaScriptResult`/`AIFridaScriptResult` structs kept in FridaScriptGenerator.swift though now unreferenced (only commented refs) — kept to minimize churn in the LIVE enum file; trivially deletable in 12c.
- **R3:** `MalwareReport` + its 5 value-type clusters (IoCReport, PEAnomaly, PackerResult, EntropyResult/SectionEntropy/EntropyBlock) survive **only** because `AetherToolbar.swift:106` (Scene, untouchable) reads `appState.malwareReport == nil`. They are pure data now; the moment the toolbar condition is reworked they can go.
- **R4:** `Models/Disassembly.swift` kept (its `DisassembledByte` is used by `DisassemblyCollection` in `BinaryFile.swift:145`); `MainView.swift` kept (UNCERTAIN — zero instantiations, but not a legacy consumer).
- **R5:** pre-existing `M .qwen/team-memory/MEMORY.md` churn predates this task; left untouched.
- **R6:** no git ops performed beyond read-only status/diff/show; no commit made.

## Recommended 12b / 12c split

- **12b — port the decompiler to models (the only remaining legacy-consumer island).** `Decompiler.swift` + `ControlFlowStructurer.swift` still consume `Function`/`BasicBlock`/`BinaryFile`/`Instruction`; AppState's `decompileCurrentFunction` builds `legacyFunction`/`legacyBinary(for:)` adapters. Port them to `ProcedureModel`/`SymbolModel`/`BinaryModel`/`Pcode`, delete the adapters, then delete legacy type files `Models/{Function,BinaryFile,Disassembly}.swift` (`DisassemblyCollection` goes with BinaryFile) + `InstructionType`/`CrossReference`/`XRefType` once `Models/Instruction.swift` is gone. Verify `XRefsView`-era gaps (xrefs currently stubbed `[]`).
- **12c — residual legacy sweep:** `Models/{Symbol,Instruction,Architecture}.swift` (Instruction is still consumed by the LIVE disassembly cache: `AppState.instructions`, `instruction(at:)`, `DisassemblyView`, `DisassemblerEngine`/`DisassemblyInstruction` — this is the real remaining work: re-point the disassembly pipeline onto the model/pcode side), plus cleanup of `MainView.swift` (if confirmed orphan), `FridaScriptResult`/`AIFridaScriptResult` (R2), the `MalwareReport` cluster (R3, after toolbar rework), and uncomment-or-delete the dead `.sheet` blocks in `AetherContent.swift:34-80` (Scene change — needs an explicit Scene-touching slice).

## Manual UI smoke steps (for orchestrator)

1. Launch Aether (scheme Aether, My Mac), create/open a `.aetherproj` document.
2. **Import** `thin_test` via File → Import Binary… (⇧⌘O) → confirm it appears in the Programs navigator.
3. Right-click the binary → **Load…** → confirm sections/symbols populate and the **disassembly view** renders instructions.
4. Select a function → **⇧⌘D** (decompile) → confirm pseudo-code appears in the DecompilerView (Task 8 path, must be unregressed).
5. Navigate: click instructions (selection highlight), **Go to Address** (⇧⌘L-ish sheet), **Search** (⌘F sheet), toggle Hex/CFG (toolbar), scroll — confirm no crashes.
6. Touched menus/toolbar: Analysis menu items (Find Functions, Crypto Detection, Deobfuscate, Type Recovery, Idiom Recognition, Structured Code) → should be silent no-ops (bodies were empty stubs already); Tools → Export to IDA Python… → no sheet appears (sheet was already commented); AI menu items (Analyze with AI, Explain, Rename Variables → rename flow should still show the rename error/success path since `suggestVariableNames` is LIVE, but the rename *sheet* is gone) → no-ops; Malware Analyze / Flow → no-ops; Frida Generate (3 items) → no-ops; **Call Graph** (⌃⌘C or menu) → CallGraphWindowView still opens and closes (it is LIVE).
7. Toolbar Frida Platform/Hook pickers (LIVE enums) still render.
8. ⌘W / document close → clean shutdown, no autosave errors.
