# Handoff 17 — Task 12c: final legacy-type sweep (pipeline re-point, legacy model deletions, residual dead clusters) (Agent 18)

STATUS: COMPLETE

## Pre-flight

- HEAD: `1034f24` (experiment/swift-data) — "Port the decompiler to SwiftData models and delete the legacy value types (Task 12b)"
- `git status --short`:
  ```
   M .qwen/team-memory/MEMORY.md        (pre-existing, not mine)
  ?? cartograph-dead-code-analysis.txt  (pre-existing build artifact)
  ```
  Confirmed matches expected pre-flight state. No edits made yet.

## Design decisions

1. **New instruction value type lives in the APP target** (`Aether/Core/Disassembler/DisassembledInstruction.swift`). Reasoning: the entire pipeline machinery it depends on — `DisassemblyInstruction`, `InstructionKind`, `DisassemblyBranch`, `DisassemblyOperand`, `OperandAccess` (DisassemblyInstruction.swift) — is already app-target code, and AetherKit (strict Swift 6, Sendable-heavy, shared with aether-cli) has zero references to any of it. AetherKit is the p-code/store layer; a Capstone-flavored disassembly row is not shared IR. Keeping it in the app target also avoids forcing `Sendable`/Swift 6 conformance onto the engine's scratch types and keeps the CLI surface untouched.
2. **Rename legacy `Instruction` → `DisassembledInstruction`** (the verification gate requires zero `Instruction` type refs repo-wide). Field set is byte-identical to the legacy struct (addressRange/mnemonic/operands/architecture/pcode/kind/comment + computed address/size/id/text/isControlFlow/isBranch/endsBasicBlock, `==`/`hash` by address) so every live consumer (AppState cache, Decompiler, DisassemblyView, BranchVisualization, ConditionalJumpsView, Inspector) compiles unchanged apart from the type name. Not marked `Sendable` — the legacy type wasn't either and the engine/actor flow already compiles (app is Swift 5 mode, approachable concurrency).
3. **Rename legacy `InstructionType` → `InstructionCategory`** (same zero-ref gate). Cases unchanged (16). The `color: String` property on the legacy enum had **zero callers** repo-wide (grep: only its definition) — dropped. `DisassemblyInstruction.swift:72` (`InstructionKind.type`) and `JavaDisassembler.decodeJVMInstruction`'s return tuple updated to the new name.
4. **`XRefType` is NOT a legacy type** — `Aether/Models/Instruction.swift`'s `CrossReference` used **AetherKit's** `XRefType` (Arch.swift:186, live via `CrossReferenceModel.type`). The legacy `CrossReference` struct (Instruction.swift:105) is deleted (zero refs outside itself, re-verified); AetherKit's `XRefType` stays. Grep expectation for `XRefType`: only AetherKit hits.
5. **AetherKit minimal opening (item A):** only `BlockModel`'s `startAddress`/`endAddress`/`type`/`successors`/`predecessors` become `public` (the exact set the app reads via the `cfg*` bridge). `procedure`/`size`/init stay internal — the app reaches blocks through `ProcedureModel.blocks` (already public) and never reads `block.procedure` or `block.size`. All other model classes' stored fields are already `public` (verified: BinaryModel, SegmentModel, SectionModel, SymbolModel, ProcedureModel, StringModel, AnnotationModel, BookmarkModel); `CrossReferenceModel` has internal fields but the app references it nowhere — left alone.
6. **`extension SymbolType { icon }` re-homed** to a new small file `Aether/UI/Components/SymbolTypeIcon.swift` (consumers: `Aether/Navigator/SymbolNavigator.swift:42`, `Aether/Scene/AetherToolbar.swift:198` — both untouched, same module). `Models/Symbol.swift` (legacy `Symbol` struct — zero refs outside itself, re-verified) deleted.
7. **`extension Architecture` re-homed into `Aether/Core/Decompiler/Decompiler.swift`** (the only consumer, ported in 12b). Only the 4 members the Decompiler reads are kept: `stackPointerName`, `framePointerName`, `argumentRegisters`, `returnValueRegister`. The other 5 (`instructionAlignment`, `pointerSize`, `returnAddressLocation`, `is64Bit`, `generalPurposeRegisters`) had **zero consumers** repo-wide (the MachOLoader `is64Bit` hit is a local var in a different module) — deleted. `Models/Architecture.swift` deleted.
8. **`AIFridaScriptResult` is NOT orphaned** (contrary to 12a's R2): `AIClient.swift` still defines live-compiling `generateFridaScriptAsync`/`parseFridaResponse`/`parseFridaJSON` that construct it. Zero *callers* of `generateFridaScriptAsync` (only ref: commented AppState stub line :797), so those 3 AIClient methods are deleted together with both Frida result structs. `FridaScriptGenerator.swift` ends up as the two enums only.
9. **`MainView.swift` verdict: KEEP.** The file contains exactly two types — `GoToAddressSheet` and `SearchSheet` — and both are LIVE: instantiated by `GoToAddressSheetModifier`/`SearchSheetModifier` in `Aether/Scene/AetherContent.swift` (untouchable Scene file), whose flags `showGoToAddress`/`showSearch` are set by AetherCommands:160/165 and AetherToolbar:214/222. Nothing to reduce. (12a's "zero instantiations" was the false negative: the instantiations live in Scene modifiers, not in the file's own type set.)
10. **Scene slice:** delete the fully-commented `.sheet`/`.alert` block at `AetherContent.swift:33–88` (the 15 commented sheets + commented error alert). Post-deletion flag sweep (grep-verified): every declared `show*` flag on AppState still has ≥1 live (non-comment) reference except **`showSettings`** — and `showSettings` was *not* referenced by the deleted block, so it is kept and flagged (zero setters; possibly future Settings-sheet plumbing). **`showError`/`errorMessage` were never declared on AppState** (grep of `var showError`/`var errorMessage` in AppState: no declarations; the only refs anywhere were the deleted comment block + a commented line inside the kept `exportTo` stub at AppState:384–385) → nothing to delete; comment refs left in place. Same for `showFridaScript`/`showExplainCode`/`showCryptoDetection`/`showDeobfuscation`/`showTypeRecovery`/`showIdiomRecognition`/`showPseudoCode`/`showSecurityAnalysis`: referenced *only* in comments (deleted block + commented AppState stub bodies), never declared — nothing to delete. **No AppState `show*` declarations were removed by this task.** (DisassemblyView:409 has its own local `@State errorMessage` — unrelated, left alone.)
11. **MalwareReport cluster: untouched** (per task rule; `AetherToolbar:106` reads `appState.malwareReport == nil` and AetherToolbar is off-limits). `DisassemblerPlugin` model-native init: **not** re-added (decision left to user; see closing).

## Edit log

### Group A — AetherKit `BlockModel` public + bridge deletion (DONE)

1. `AetherKit/Sources/AetherKit/Schema/Schema.swift` — `BlockModel`: `startAddress`, `endAddress`, `type`, `successors`, `predecessors` → `public`. `procedure`, `size`, `init` stay internal (app never reads them; blocks reached via public `ProcedureModel.blocks`). No other model class needed opening (decision 5).
2. `Aether/Core/Analysis/ControlFlowStructurer.swift` — deleted the `private extension BlockModel` `cfg*` Mirror bridge (18 lines) + the "Task 12b workaround" comment; the 3 `cfg*` call sites (`structure(procedure:instructions:)` CFGBlock derivation + `entryAddr`) now read the properties directly. No other change to the file (algorithms untouched).

Intermediate AetherKit gate (real output):
```
cd AetherKit && swift build
→ Build complete! (1.72 secs.)
swift test
→ Test run with 0 tests in 0 suites passed after 0.001 seconds.  (x2 test bundles)
```

### Group B — pipeline re-point + legacy model deletions (DONE)

1. **Created** `Aether/Core/Disassembler/DisassembledInstruction.swift` — the new pipeline value type: `DisassembledInstruction` (Identifiable, nonisolated; field set byte-identical to the legacy `Instruction`: `addressRange`/`mnemonic`/`operands`/`architecture`/`pcode`/`kind`/`comment` + computed `address`/`size`/`id`/`type`/`branchTarget`/`text`/`isControlFlow`/`isBranch`/`endsBasicBlock`; `==`/`hash` by address) and `InstructionCategory` (ex-`InstructionType`, 16 cases unchanged; dead `color: String` dropped). Init still takes the engine scratch `DisassemblyInstruction` + `bytes: Range<UInt64>` + `address` + `arch` (+ optional `pcode`).
2. Word-boundary perl renames `s/\bInstruction\b/DisassembledInstruction/g` in: `DisassemblerEngine.swift` (incl. `AetherDisassemblyContext.submitted`, `DisassemblyResult(instructions:pcode:)`, `let next = DisassembledInstruction(...)`), `JavaDisassembler.swift`, `AppState.swift` (`selectedInstruction: DisassembledInstruction?` :46, `instructions` cache :868, `instruction(at:)`, `instructions(in:)`, `disassemble(section:)`/`disassembleFunction`/`disassembleRange`), `Inspector.swift` (`InstructionInspector`), `DisassemblyView.swift` (`@State instructions`, `OperandsView`), `BranchVisualization.swift` (`BranchAnalyzer`, `EnhancedInstructionRow`, `EnhancedOperandsView`, …), `ConditionalJumpsView.swift`, `Decompiler.swift` (~30 param sites), `ControlFlowStructurer.swift` (`CFGBlock.instructions`, `structure(procedure:instructions:)`). Verified safe: `DisassemblyInstruction` (engine scratch), `selectedInstruction`, `InstructionInspector` contain no `\bInstruction\b` boundary and were untouched. Two perl-mangled MARK comments manually fixed ("Enhanced Disassembly Row with Branch Info", "MARK: - Disassembly Decompilation").
3. `s/\bInstructionType\b/InstructionCategory/g` in `DisassemblyInstruction.swift` (`InstructionKind.type`) and `JavaDisassembler.swift` (`decodeJVMInstruction` return tuple).
4. **Deleted** `Aether/Models/Instruction.swift` (legacy `Instruction`, `InstructionType`, `CrossReference`, `StringReference` — `CrossReference`'s `XRefType` field was AetherKit's live enum, kept in AetherKit).
5. **Created** `Aether/UI/Components/SymbolTypeIcon.swift` — re-homed `extension SymbolType { var icon: String }` (identical switch body: .function→"f.square", .data→"d.square", .object→"cube", .section→"square.stack", .file→"doc", .unknown→"questionmark.square"). Consumers `SymbolNavigator:42` and `AetherToolbar:198` untouched. **Deleted** `Aether/Models/Symbol.swift` (legacy `Symbol` struct — zero live refs outside itself).
6. Appended `extension Architecture` to `Aether/Core/Decompiler/Decompiler.swift` (top of file, after imports) with exactly the 4 live members verbatim from the old file: `stackPointerName`, `framePointerName`, `argumentRegisters`, `returnValueRegister` (Tab-indented to match the file; original 4-space body converted). The 5 dead members dropped (decision 7). **Deleted** `Aether/Models/Architecture.swift`.
7. `ls Aether/Models/` → `AppState.swift` only (immediately after deletions).

Intermediate app build (real output):
```
xcodebuild -project Aether.xcodeproj -scheme Aether -destination 'platform=macOS' build
→ ** BUILD SUCCEEDED ** [4.891 sec]
   (stale-object cleanup notes confirm Architecture.o / Instruction.o / Symbol.o
    removed from the build — the new files DisassembledInstruction.swift and
    SymbolTypeIcon.swift were auto-picked-up by the filesystem-synchronized
    project.xcproj target: no target-membership errors)
```

### Group C — residual dead clusters (DONE)

1. `Aether/Services/FridaScriptGenerator.swift` — deleted `FridaScriptResult`, `AIFridaScriptResult` + the `// MARK: - Result Structures` header (file was 4-space indented; the two kept enums `FridaPlatform`/`FridaHookType` preserve their 4-space style). File is now 34 lines, enums only.
2. `Aether/Services/AIClient.swift` — deleted (a) `generateFridaScriptAsync` (23 lines, incl. its doc comment; the last remaining live constructor of `AIFridaScriptResult`), and (b) the whole Frida section: `// MARK: - Frida Script Generation` + `buildFridaPrompt`/`parseFridaResponse`/`parseFridaJSON` (200 lines, deleted by verified line range 649–848 with boundaries read first; class-closing brace preserved). Post-delete grep `Frida\|AIFridaScriptResult` in AIClient.swift → zero hits.
3. `Aether/Scene/AetherContent.swift` — deleted the fully-commented block after `.modifier(CallGraphModifier())`: 15 commented `.sheet` blocks + the commented `.alert("Error", isPresented: $appState.showError)` (15→2-line region; the live sheets live in the separate `GoToAddressSheetModifier`/`SearchSheetModifier`/`CallGraphModifier` structs, untouched).
4. `show*` flag sweep (decision 10): **no AppState declarations removed.** `showSettings` kept + flagged (0 live refs but not a comment-block artifact). `showError`/`errorMessage`/`showFridaScript`/`showExplainCode`/`showCryptoDetection`/`showDeobfuscation`/`showTypeRecovery`/`showIdiomRecognition`/`showPseudoCode`/`showSecurityAnalysis` were never declared (comment refs only); the commented `exportTo` stub lines at AppState:384–385 (`// showError = true` etc.) left in place — they're comments inside a kept stub.

Intermediate app build (real output):
```
xcodebuild -project Aether.xcodeproj -scheme Aether -destination 'platform=macOS' build
→ ** BUILD SUCCEEDED ** [3.803 sec]
```

## Grep evidence

All commands run from the repo root after all edits.

```
$ grep -rn "\bInstruction\b" Aether --include='*.swift' | grep -v "DisassemblyInstruction\|DisasmentedInstruction"
Aether/UI/Components/ThemeManager.swift:15:    // Instruction colors
```
→ single hit is a comment; **zero `Instruction` type refs**. ✅

```
$ grep -rn "InstructionType" Aether AetherKit/Sources aether-cli/Sources --include='*.swift'
Aether/Core/Disassembler/DisassembledInstruction.swift:74:/// `InstructionType`; the dead `color: String` property was dropped).
```
→ only the rename-provenance doc comment. ✅

```
$ grep -rn "CrossReference" Aether --include='*.swift' | grep -v "CrossReferenceModel"
(no matches)
```
✅ (legacy struct gone; SwiftData `CrossReferenceModel` untouched in AetherKit)

```
$ grep -rn "XRefType" Aether AetherKit/Sources aether-cli/Sources --include='*.swift' | grep -v "AetherKit/"
(no matches outside AetherKit)
```
✅ (matches the expectation: `XRefType` is AetherKit's live enum, Arch.swift:186, via `CrossReferenceModel.type`)

```
$ grep -rn "StringReference" Aether AetherKit/Sources aether-cli/Sources --include='*.swift' | grep -v "string reference\|String reference"
Aether/Services/ExportManager.swift:9:/// `Function` / `StringReference`) and were removed in Task 12b — their only
```
→ only a historical Task-12b doc comment in ExportManager. ✅

```
$ grep -rwn "Symbol" Aether AetherKit/Sources aether-cli/Sources --include='*.swift'
MainView.swift:168: ... type: "Symbol" }          (UI string literal)
BranchVisualization.swift:749: // Symbol reference - O(1) lookup against the models   (comment)
DisassemblyView.swift:297:   // Symbol reference ... (comment)
SymbolTypeIcon.swift:4-5:   // Task 12c: re-homed from the deleted `Models/Symbol.swift` ... (comment)
AppState.swift:99 / 975:    // MARK: - Operand Symbol Resolution (Task 10)   (comment)
AetherKit Arch.swift:131/141: /// Symbol type / /// Symbol binding   (comments)
AetherKit MachOLoader.swift:148: "Symbol table extends past end of file ..."  (error string)
```
→ **zero `Symbol` type refs**; hits are all comments/string literals (and no `SymbolModel`/`SymbolType`-adjacent type usage of the legacy name). ✅

```
$ grep -rn "FridaScriptResult" Aether AetherKit/Sources aether-cli/Sources --include='*.swift'
Aether/Models/AppState.swift:744/780/809/837: // ... aiFridaScriptResult = ...   (all commented stub lines)
$ grep -rn "AIFridaScriptResult" Aether AetherKit/Sources aether-cli/Sources --include='*.swift'
(no matches)
```
✅ (both structs deleted; only commented AppState stub lines mention the old local var `aiFridaScriptResult`)

```
$ ls Aether/Models/
AppState.swift
```
✅

Deleted/never-declared `show*` flags:
```
$ grep -rn "showCryptoDetection\|showDeobfuscation\|showTypeRecovery\|showIdiomRecognition\|showPseudoCode\|showSecurityAnalysis\|showFridaScript\|showExplainCode\|showError\b\|errorMessage" Aether --include='*.swift' | grep -vE ":\s*//"
Aether/UI/DisassemblyView/DisassemblyView.swift:409: @State private var errorMessage: String?   (+440/475/482 — its own local hex-input state, unrelated to AppState)
```
✅ no live AppState refs; every `show*` flag that WAS declared (15 total, `var show*` grep) either has ≥1 live setter/reader (all except `showSettings`) or is `showSettings` (kept + flagged, decision 10). No `show*` declarations were deleted this task (none existed for the comment-block-only flags).

## Verification

Gate 1 — app build (final run after all edits):
```
$ xcodebuild -project Aether.xcodeproj -scheme Aether -destination 'platform=macOS' build
** BUILD SUCCEEDED ** [1.560 sec]
```
(Two earlier in-task runs also SUCCEEDED: 4.891s after Group B, 3.803s after Group C — outputs in the edit log above.)

Gate 2 — AetherKit:
```
$ cd AetherKit && swift build
Build complete! (0.21 secs.)
$ swift test
Test run with 0 tests in 0 suites passed after 0.001 seconds.   (x2 test bundles)
```

Gate 3 — aether-cli (field-visibility-only AetherKit change; no persisted field added/removed/retyped, so store smoke not required):
```
$ swift build --package-path aether-cli
[12/15] AetherKit
[15/16] aether-product
Build complete! (1.87 secs.)
```

Gate 4 — grep-proofs: see "Grep evidence" above (all pass).

Gate 5 — `ls Aether/Models/` → `AppState.swift` only (above). ✅

Gate 6 — manual UI smoke: listed below for the user (not run; headless session).

## Risks / notes

- **New-file target membership (realized OK):** Xcode 26's file-based `project.xcproj` used filesystem-synchronized groups — both new files (`Aether/Core/Disassembler/DisassembledInstruction.swift`, `Aether/UI/Components/SymbolTypeIcon.swift`) compiled in without any project-file edit, proven by the Group B build. The pre-flight risk did not materialize.
- **Decompiler output equivalence:** `Decompiler.decompile` is untouched algorithmically; it receives the same field values under a renamed type (`ArraySlice<DisassembledInstruction>`), so output for a given disassembly is byte-identical. Task 8 UX (spinner, `decompileOwner`, `decompiledOutputs`, ⇧⌘D) and Task 10 `appState.operandSymbol(at:)`/`operandSymbol(named:)` compile unchanged and operate on the same fields (`address`, `operands`, `mnemonic`, `addressRange`).
- **`DisassemblyInstruction` name collision risk (avoided):** the engine scratch struct keeps its name; the word-boundary rename proved it doesn't shadow or match.
- **`showSettings`:** 0 live refs, kept (not a comment-block artifact). Flag for the user: either wire it to a Settings sheet or delete it with its declaration.
- **Commented AppState stub bodies** (Task 12b leftovers) still contain dead references (`aiFridaScriptResult`, `showFridaScript`, `showError`…). Left as-is per "if in doubt, keep and flag"; they don't compile.
- **`FridaScriptView` / `FridaScriptGenerator` enums:** the two enums (`FridaPlatform`, `FridaHookType`) are now the whole file and have zero non-comment consumers outside it — left per task scope ("only enums stay"). Candidate for a later pass if Frida UI is revived or abandoned.
- **`ThemeManager.instruction` color** (lowercase property, still named after the old type) — cosmetic; left untouched (ThemeManager not in scope).
- **Cartograph** dead-code check runs as a build step and did not fail the builds; the new `DisassembledInstruction`/`InstructionCategory`/`SymbolType.icon`/`Architecture` extensions are all consumed.

## Manual UI smoke steps (Gate 6 — for the user)

1. Launch Aether (scheme Aether, My Mac). Open a project doc (or New).
2. File ▸ Import Binary… (⇧⌘O) → pick `.qwen/tmp/thin_test`.
3. In the Programs navigator, right-click the imported binary → **Load…** — confirm the disassembly renders with operand highlighting and comments.
4. Select a procedure (Functions navigator) → ⇧⌘D **Decompile** — confirm the decompile spinner shows and the output panel appears with pseudo-C for the procedure.
5. Rapidly switch A→B→A between two procedures (decompile owner switch) — no stale output, no crash.
6. Rename a symbol/operand (double-click in disassembly) — rename sticks and operand symbols refresh (Task 10 `operandSymbol(at:)`).
7. ⌘F search — SearchSheet opens (SearchSheetModifier), finds a symbol.
8. Go to Address (⌘L / toolbar) — GoToAddressSheet opens, jump to an address, disassembly scrolls.
9. Toggle Hex view and CFG view (bottom panel) — CFG renders blocks (exercises the new direct `BlockModel.startAddress/successors/predecessors` reads via `ControlFlowStructurer`).
10. Close and reopen the document — disassembly/CFG/decompiler still work (SwiftData round-trip; no schema change was made, so this is a sanity pass only).

## Closing — is the migration complete?

**Yes — the legacy→SwiftData type migration is complete at the type level.** After this task:
- `Aether/Models/` contains only `AppState.swift` (the per-window session object, which is intentional — it is UI state, not persistence state; SwiftData owns persistence).
- Zero type refs remain to any deleted legacy type: `Instruction`, `InstructionType`, `CrossReference`, `StringReference`, `Symbol` (legacy), `FridaScriptResult`, `AIFridaScriptResult` (grep-proofs above). `XRefType` and `SymbolType` live on in AetherKit as the store layer's enums — correctly.
- The disassembly pipeline (engine → `AetherDisassemblyContext` → `DisassembledInstruction` → `AppState` cache → views/Decompiler) and the CFG/Decompiler all run on AetherKit SwiftData models + the app-target `DisassembledInstruction` value row.

**Left for user decisions:**
1. **MalwareReport toolbar line** — `AetherToolbar.swift:106` reads `appState.malwareReport == nil` (toolbar off-limits per task rules). Product decision: keep the Malware toolbar entry (and its AppState state) or remove it when the MalwareReport cluster is next touched.
2. **`DisassemblerPlugin` model-native init** — the legacy `DisassemblerPlugin.init?(for binary: BinaryModel)` was dropped in an earlier task and not revived here (decision 11). If the plugin system is to be re-activated, it needs a model-native entry point written against `BinaryModel`.
3. **`showSettings` flag** — 0 live refs; wire to a Settings sheet or delete.
4. **Commented AppState stub bodies** — large comment-only method shells remain (crypto/Frida/security/AI-analysis paths); deleting or re-implementing them is a product decision, not a type migration one.
