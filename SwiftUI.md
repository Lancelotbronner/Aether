# SwiftUI anti-pattern audit — views reachable from `AetherScene`

Method: `the-swiftui-way` checklist (view-value comparison vs @Observable dependency tracking,
minimum dependencies, stable identity, async in `.task(id:)`, no per-row inline work).

Scope traced so far:
`AetherScene` → `AetherContentView` → `AetherSidebar` (+ navigators), `DetailView` →
`DisassemblyView`, `DecompilerView`, `CFGView`, `HexView`, `StatusBarView`; sheets and
`Inspector` are attached at `AetherContentView`.

---

## Aether/Scene/AetherContentView.swift

### A1. Root view reads ~20 properties of the god model — root body re-runs on almost any change
`body` reads `appState.isInspectorPresented`, `showGoToAddress`, `showSearch`, `showCallGraph`,
`showCryptoDetection`, `showDeobfuscation`, `showTypeRecovery`, `showIdiomRecognition`,
`showPseudoCode`, `showExportSheet`, `showSecurityAnalysis` (+ `securityAnalysisResult`,
`isAnalyzingWithAI`, `securityAnalysisError`), `showFridaScript`, `showAIChat`, `showExplainCode`,
`showAIRename`, `showMalwareDashboard`, `showImportExportBrowser`, `showEntropyView`,
`showMalwareFlow`, `isLoading`, `loadingMessage`, `loadingProgress`, `currentFile`, `showError`,
`errorMessage`.

With per-property `@Observable` tracking, the whole `AetherContentView.body` re-evaluates whenever
ANY of these mutates — i.e. every time any sheet flag flips, any analysis starts/finishes, or the
file is replaced. That re-runs the body that hosts `NavigationSplitView`, the toolbar, the sidebar,
and the entire detail tree. This is the main structural amplifier of every other issue below.

Fix: split `AppState` into sub-models (file/analysis state, per-feature UI state, AI state) and
let each sheet/feature own its `isPresented` binding locally or read from a narrower model.

### A2. ~18 `.sheet` modifiers stacked on one view
Each sheet modifier is evaluated on every root body pass; more importantly, all presentation state
lives in the root, which couples everything (see A1). Grouping sheets with the views that own the
feature would also let each feature's invalidation stay local.

### A3. `onAppear { appState.undoManager = undoManager }`
Side effect in `onAppear` mutating the model (mitigated only because `undoManager` is
`@ObservationIgnored`). `onAppear` can fire repeatedly (window resize/restore, split-view
reappearance on some platforms) — should be idempotent or moved to `.task`/document lifecycle.

### A4. `DetailView` — conditional children break structural identity
- `if appState.showDecompiler { DecompilerView() }` inside `HSplitView`: toggling removes/recreates
  the decompiler subtree (state loss, re-init cost). Skill: prefer `.opacity` toggles / conditional
  *parameters* over `if/else` for frequently shown/hidden expensive views.
- Bottom panel: `ZStack { if showCFG { CFGView() } else if showHexView { HexView() } }` — same
  problem; switching Hex/CFG discards both.
- `bottomPanelHeight` `@State` feeds `idealHeight` but nothing in `HSplitView` resizes the bottom
  panel — dead state (or a missing resize handle).

### A5. `handleDrop`
OK-ish, but: spawns an unstructured `Task { }` from the `onDrop` closure (not tied to view
lifecycle, not cancelled); duplicates the file-reading logic of `openFile` (memory-map read is
copy-pasted). Centralize in `appState.loadFile(from: URL)` on the model.

---

## Aether/Scene/AetherSidebar.swift

### B1. `SidebarTab` switch = full teardown/rebuild on every tab change
`switch tab` produces a different view per case, so switching tabs destroys the previous navigator
(scroll position, in-progress edits, `@State`). If that is intended, fine; but combined with A1,
the *segmented picker* re-renders all six navigator bodies? No — only the selected one is in the
tree. The real cost is losing per-tab scroll/state. Consider a `ZStack` of all six with
`.opacity`/`accessibilityHidden` if preserving scroll position matters (six Lists is heavy, so
this is a trade-off — at minimum preserve via a per-tab `ScrollViewReader` anchor in the model).

### B2. `RenameSheet.Reset` saves an empty name
```swift
Button("Reset") {
	newName = ""
	onSave("")      // ← calls the save closure with "" — does a "reset" really persist a rename to empty?
	dismiss()
}
```
Behavior bug: "Reset" should be equivalent to Cancel (or restore `currentName`), not invoke
`onSave("")`. Check the callers — if `onSave("")` clears a symbol/function name in the model, the
user has just renamed a symbol to an empty string.

### B3. Segmented `Picker` as the tab control
Fine functionally; `.labelsHidden()` + `Label(...).help(...)` keeps accessibility. Note the
`ForEach(NavigatorTab.allCases)` has no explicit `id:` — relies on `Identifiable` (`id: Self`),
which is stable and correct. No issue.

---

## Aether/UI/DisassemblyView/DisassemblyView.swift

### C1. O(n²) per body evaluation: `branches.first { $0.sourceAddress == insn.address }` inside `ForEach`
```swift
ForEach(instructions) { insn in
	let branchInfo = branches.first { $0.sourceAddress == insn.address }
	...
}
```
For 500 instructions × branches, every row does a linear scan — and this runs on **every** body
re-evaluation of `DisassemblyView` (which, via A1, happens often). Precompute
`let branchByAddress: [UInt64: BranchInfo]` once in `loadInstructions()` and pass the dictionary.
(Skill: pre-filter in the model, never inline filter/sort in ForEach.)

### C2. `allInstructions: instructions` passed to every `EnhancedInstructionRow`
Each row receives the *entire* instruction slice as a stored value → the whole array enters the
per-row view-value comparison, defeating lazy-row skipping. Pass only what the row renders
(instruction, its own branch info, selection flag, a lookup closure/dictionary at most).

### C3. `DisassemblyHeader` receives `branches` and `instructions` but only uses `branches.count`-style filters and `instructions.isEmpty`
Pass counts/flags instead of the collections. (`branches.filter{...}.count` is also recomputed
twice per body pass — compute once.)

### C4. `@State var instructions: ArraySlice<Instruction>`
An `ArraySlice` retains its **base array**. If `appState.disassemble(section:)`/`disassembleFunction`
return a slice into a larger cached array, `@State` keeps the *entire* disassembly alive in memory
forever (until the next load). Either copy (`Array(...)`) or be deliberate about the retention.

### C5. Load pipeline: `onAppear` + 3× `onChange` + uncancelled `Task`
- `onAppear` and `onChange(of: appState.currentFile?.id)` both fire when a file is already loaded
  at first appearance → **double load** (two racing `Task`s both writing `instructions`,
  `branches`, `isLoading`; last writer wins).
- No cancellation: leaving the tab / switching file mid-disassembly lets a stale task write into
  state after a newer load started.
- Skill: this is exactly the `.task(id:)` case:
  `.task(id: LoadKey(fileID, functionID, sectionID)) { ... }` with one structured task that is
  auto-cancelled on change/disappear, plus a `Task.checkCancellation()` after the await.

### C6. `OperandsView.parseOperands()` — string splitting on every body evaluation, per row
Each instruction row re-splits `instruction.operands` and re-classifies every operand (including
dictionary lookups) on every render. Cache the parsed `[Operand]` on the `Instruction` value when
disassembling (or in a `[UInt64: [Operand]]` cache) — body must be a pure mapping of state.

### C7. `ForEach(Array(parseOperands().enumerated()), id: \.offset)`
Index-based identity — anti-pattern: when the operand list changes, rows reuse wrong identities
and re-init spuriously. Operands are derived text; give each a stable id (e.g. `"\(index)-\(text)"`
is still fragile — better: parse once (C6) and id by a stored index on the model side, since
operands of one instruction are stable per instruction).

### C8. `isRegister` builds a `Set` of ~60 strings on every call
Called per operand per row per body pass. Make it a static `Set` (or better, use Capstone's
operand kind — the disassembler already knows which operands are registers).

### C9. Minor
- `DisassemblyHeader` "toggle branch arrows" button renders the same SF Symbol for both states
  (`showBranchArrows ? A : A`) — only the color changes; use `.opacity`/a distinct symbol or
  `Image(systemName:).symbolVariant(.fill)`.
- `ContentUnavailableView`/`ProgressView` branches: fine (status switch).
- `ScrollViewReader` + `withAnimation { proxy.scrollTo }` on `selectedAddress` change: OK.
- `sheet(isPresented:)` for jump table / conditional jumps pass `branches`/`instructions`
  collections — fine for sheets (presented once), but same minimum-data note applies.

---

## Aether/Models/AppState.swift (part 1, lines 1–823)

### D1. God model: one `@Observable` class with ~100 stored properties
Spans file state, navigation, ~15 sheet flags, Frida state, AI chat state, malware state,
analysis results, caches, patching, annotations. Per-property tracking means only readers are
invalidated — *if* readers are narrow. In practice `AetherContentView` (A1) and probably the
navigators read broad swaths, so invalidation is near-global. Split into sub-models:
`BinaryDocument` (file, symbols, functions, sections), `NavigationModel`, `FeatureUI` (sheet
flags per feature cluster), `AIState`. `@Observable` sub-models composed on the root model give
both narrow invalidation and smaller files.

### D2. `loadTask` is a tracked, non-`Sendable`-friendly stored var
`private var loadTask: Task<Void, Never>?` is **not** `@ObservationIgnored` → every
assignment (start, completion→nil) is an observable change, invalidating any view reading it
(none should) — mark it `@ObservationIgnored`. Same audit needed for other non-UI stored vars.

### D3. `analyzeMalwareFlow()` runs `MalwareAnalyzer().analyze(binary:)` synchronously on the main actor
```swift
if malwareReport == nil {
	let analyzer = MalwareAnalyzer()
	malwareReport = analyzer.analyze(binary: binary)   // heavy, main-actor blocking
}
```
`AppState` is main-actor-isolated (app target uses `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`).
This blocks the UI for the whole static-analysis pass. `analyzeMalware()` below correctly uses
`Task.detached`; make them consistent.

### D4. `analyzeMalware()` — `Task.detached` + `[weak self]` + new analyzer inside
Works, but the detached task captures `binary` (a value? check `BinaryFile`) and there is no
cancellation path if the file is closed mid-analysis: the completion still writes
`malwareReport`/`isAnalyzingMalware` for a *different* document. Guard with a generation/file id.

### D5. Navigation properties with side-effecting setters
```swift
var functionNavigator: Function? {
	get { selectedFunction }
	set { guard let selectedFunction else { return }
		goToAddress(selectedFunction.startAddress) }
}
```
The setter navigates but the "selection" actually lives in `selectedFunction` — a List bound to
this property will set it, which then re-sets state and can re-trigger the same list's
invalidation. Also the setter's `guard let` shadows the parameter confusingly (it reads the
*parameter*, OK, but the name collision is a trap). Prefer: List binds to `selectedFunction`
directly, and a `.onChange`/explicit action does the navigation. Same pattern for
`sectionNavigator`.

### D6. `symbols: [Symbol] { currentFile?.symbols ?? [] }`
Computed property returning `[]` — every reader of `appState.symbols` re-tracks `currentFile`
and creates a fresh array wrapper each time; if `currentFile.symbols` is itself a stored array,
prefer reading `currentFile?.symbols` at the use site or caching.

### D7. `goToAddress` — O(n) linear scans
`functions.first { $0.contains(address:) }` per click; with large binaries use a binary search on
sorted `functions` or `functionsByAddress` upper-bound lookup. (Correctness fine; perf note.)

### D8. `closeFile` doesn't reset everything
Leaves `xrefs`, `cryptoFindings`, `recoveredTypes`, `recognizedIdioms`, `structuredCode`,
`searchResults`, `chatMessages`, `malwareFlow*`, patcher/patches (patcher *is* niled? no —
`patcher` is not reset in `closeFile`), UI flags (`showDecompiler` etc. fine), and
`selectedAddressRange` stays 0..<1? (`selectedAddress = 0` → range 0..<1). Audit against
`loadFile`'s write set — every property written by a load/analysis should be cleared on close.

### D9. Duplicated file-read logic
`openFile()` and `AetherContentView.handleDrop` both do `Task.detached { Data(contentsOf:options:.mappedIfSafe) }`
with duplicated logging. One `appState.loadFile(from: URL)` is enough.

### D10. `apiKey` computed prop hits the Keychain per access
`KeychainHelper.load` on the main thread each time `apiKey` is read; cache it (invalidate on
settings change).

---

---

## Aether/Models/AppState.swift (part 2, lines 824–1836)

### D11. `clearDisassemblyCache(in:)` is broken — patches corrupt the instruction cache
```swift
let lowerBoundI = instructionMap[range.lowerBound, default: 0]
let upperBoundI = instructionMap[range.upperBound, default: 0]
let lowerBoundP = instructions[lowerBoundI].pcode.lowerBound
...
instructions.removeSubrange(lowerBoundI..<upperBoundI)
```
- Never removes the spliced addresses from `instructionMap` → every map entry at/after the splice
  is off by the removed count → `instruction(at:)` and `instructions(in:)` return **wrong
  instructions** after any patch.
- `default: 0` means a patch address that isn't an instruction boundary deletes from index 0
  (possibly the first instruction of the whole cache).
- `disassembled` (the RangeSet) is never shrunk → `disassembleIfNecessary` will not re-disassemble
  the patched range → patched bytes are never reflected anywhere.
- Crashes on empty `instructions` (`instructions[0]`).
This directly corrupts DisassemblyView/HexView/Inspector content after using
`patchBytes`/`nopInstruction`/`revertPatch`. Correctness bug, high priority.

### D12. `instructions(in:)` walks the array byte-by-byte — O(n) per call
Called from `selectedInstruction`'s `_read` (so on every body pass of any reader) and from
`disassemble(section:/function:)`. Use the index from `instructionMap` + a binary search on
addresses, or maintain prefix sizes.

### D13. `search(query:type:)` runs text filters on the main actor
`searchFunctions/Strings/Symbols` are synchronous `filter{}.lowercased().contains` over the full
collections, invoked from the async `search` which is main-actor-isolated. Large `strings` lists
(still extracted? currently `[]` in `loadFile`, but `performAnalysis` fills them) will hitch the
UI on every keystroke-search. Move to `Task.detached`/nonisolated.

### D14. `saveFile()` → `preconditionFailure("cannot save without URL")`
A menu action crashes the whole app. The `DocumentGroup` URL is not plumbed into `AppState`;
store the document URL on load (`config.document.url`) and no-op/alert when absent.

### D15. `loadProject`/`openProject`/`saveProjectAs` swallow errors
`try? await loadProject(...)`, `try? saveProject(to:)` — silent failure. At minimum set
`errorMessage`/`showError`.

### D16. `ProjectData` embeds the *entire binary* (`binaryData`) in the .dproj JSON
Every project save rewrites the whole file plus pretty-printed JSON. Consider referencing the
binary path + a hash, or at least documenting the trade-off. (Design note, not a SwiftUI issue.)

### D17. `decompileCurrentFunction` — no cancellation, stale-write guarded only by selection
Detached decompile keeps running after switching functions; result is dropped if selection moved
(OK), but the initial `decompilerOutput = "// Decompiling..."` write happens *synchronously* and
`decompilerOutput` is observed by `DecompilerView` → fine. Acceptable; a generation counter would
be cleaner.

### D18. `registerUndoRedo` pattern is correct
`registerUndo(withTarget:)` + immediate `redo()` — good. Note it depends on
`appState.undoManager` being set (see A3) — until `AetherContentView.onAppear` fires, all
undo registration is silently dropped.

### D19. `searchAll` does NOT do byte search
The `.all` case skips `searchBytes` — inconsistent with the picker's implication. Minor behavior.

### D20. `analyzeWithAI` builds prompt strings on the main actor
`instructions.prefix(200).map { String(format: ...) }` over disassembly — small, fine. But
`strings.filter { $0.address in range }` is O(all strings) per analysis — acceptable for
click-driven analysis.

---

## Aether/UI/DisassemblyView/HexView.swift

### E1. `@State var data: Data` — view-local mirror of `section.data`
`data = section.data` on section change. `Section.data` is `Data` (CoW), so the assignment is a
cheap reference copy — NOT a per-click full copy (good). The remaining smell: `HexView` keeps a
private mirror of model data in `@State` instead of reading `appState.selectedSection?.data`
directly; the mirror can silently drift (e.g. patches to the section don't update it — see D11
area), and `rowCount`/rows depend on it. Hold the `Section` reference and derive `data` in the
view.

### E2. `onChange(of: appState.selectedSection, initial: true)` — deprecated closure form
Single-parameter `onChange(of:initial:perform:)` is the pre-iOS-17 API (soft-deprecated); use
the two-parameter (or zero-parameter) form. Comparison itself is cheap: `Section` is a class
with identity-based `==`. Inside the closure it re-reads `appState.selectedSection` instead of
using the passed new value (works today; wrong habit in async closures).

### E3. `HexRow` re-reads `appState.selectedAddressRange` per row (observable dependency)
Every visible row tracks `selectedAddressRange` → any selection change invalidates all visible
rows. That's inherent to per-byte highlighting and acceptable at this scale (16–32 bytes/row),
but note: passing `selectedAddressRange` from the parent `ForEach` would make the invalidation
explicit and let you compare row-level (a row whose bytes are outside both old and new range
could skip). Current form re-renders the whole row for an out-of-range selection change.

### E4. `ForEach(0..<rowCount, id: \.self)` — dynamic range
`rowCount` depends on `data.count` and `bytesPerRow`; `ForEach` over a *variable* `Range<Int>`
with `id: \.self` is the tolerated workaround (rows are re-identified on change, which is
desired here), but it means changing bytes-per-row tears down **every** row. Fine for a bottom
panel; just be aware.

### E5. `scrollTo` is commented out with a FIXME — the feature doesn't work
`//FIXME: tries to build all views on its way, spends forever there` + empty
`withAnimation { }` left behind. The "go to address" scroll in the hex view is dead. If
`scrollTo` on a `LazyVStack` materializes rows, the fix is to scroll to the *row id* without
animation, or drop `LazyVStack` for a page-based approach. Until then, remove the dead
`withAnimation`.

### E6. `Picker("", selection: $bytesPerRow)` — empty accessibility label
Give it a real label (e.g. `Picker("Bytes per row", ...)` + `.labelsHidden()`).

### E7. Per-byte `Text(verbatim: " ")` in the ASCII column
16–32 extra `Text` views per row for spaces. In a monospaced font, append the space to each
character's `Text` (or build one `Text` per row from the ASCII string) — halves the ASCII
column's view count.

### E8. `isprint` on 0x80–0xFF renders locale-dependent "printable" junk
High bytes (common in code sections) pass `isprint` in many locales and render as arbitrary
Unicode scalars instead of `.`. Restrict to `0x20..<0x7F` for the printable check.

---

## Aether/UI/DecompilerView/DecompilerView.swift

### F1. **Stale output for the selected function** — the `.task` only runs while output is empty
```swift
} else if appState.decompilerOutput.isEmpty {
	VStack { ProgressView(); Text("Decompiling...") }
	.task { appState.decompileCurrentFunction() }
} else {
	ScrollView { SyntaxHighlightedCode(code: appState.decompilerOutput, ...) }
}
```
Select function A → output filled. Select function B → `decompilerOutput` still holds **A's
p-code**, which is non-empty → the `else` branch shows A's decompilation while the header says B.
Decompilation of B never triggers. This is exactly the skill's "model must follow an input
change" case: the decompilation is *input-dependent* (function id) but keyed on *emptiness*.
Fix: drive it with `.task(id: appState.selectedFunction?.id)` (guard nil) in the *container*,
and let the model clear/replace output.

### F2. `SyntaxHighlightedCode` tokenizes in `body` — O(lines × chars) on every body evaluation
`body` splits the whole output on `\n` and runs a hand-rolled char-by-char tokenizer for every
line, rebuilding `Set`s of keywords/types **per line per pass**. `decompilerOutput` is
observable; any change re-tokenizes everything, and the parent (A1) re-runs this view often.
Fix: tokenize once — either store `[Line: [Token]]`/`[AttributedString]` on the model when
`decompilerOutput` is produced, or in `SyntaxHighlightedCode` via `.task(id: code)` into
`@State`. `body` must stay a pure mapping.

### F3. Non-lazy `VStack` over all decompiled lines
Thousands of lines → thousands of `Text` rows in one eager `VStack`. Use `LazyVStack` (inside
the existing `ScrollView`) + `scrollTargetLayout()`, or one `Text` per line built from an
`AttributedString` (kills the inner `ForEach` of tokens entirely — see F2).

### F4. `ForEach(...enumerated(), id: \.offset)` (twice: lines and token parts)
Index identity again: when `code` changes, rows keep identity by position and SwiftUI diffs each
line's token sequence positionally. With F2's cached `AttributedString` lines this goes away;
otherwise id lines by a stable key (line hash + index is still fragile — prefer the model).

### F5. `Character.isHexDigit` force-unwrap + per-char range membership
`("a"..."f").contains(lowercased().first!)` — works, but `lowercased()` allocates a `String` per
character call inside the tokenizer hot loop. Precompute with a `Set<Character>` or
`isWholeNumber`/`isHexDigit`-style checks. (Becomes moot if F2 is fixed.)

### F6. `@AppStorage("fontSize") Double` / `fontName` — fine, but every size tick re-renders all
rows
Expected; note only. Consider `@ScaledMetric` for the font size so it participates in Dynamic
Type instead of a raw `Double` slider.

### F7. `copyToClipboard` reads `appState.decompilerOutput` (whole string) — fine.
`NSPasteboard.general` on the main actor — OK.

---

## Aether/Navigator/* (Functions, Strings, Imports, Exports, Symbols, Sections)

### G1. **`functionNavigator` / `sectionNavigator` setters ignore the new value — sidebar selection is broken**
```swift
var functionNavigator: Function? {
	get { selectedFunction }
	set {
		guard let selectedFunction else { return }        // ← reads the GETTER, not the new value
		goToAddress(selectedFunction.startAddress)
	}
}
```
A parameterless `set { }` exposes the new value only as `newValue`; the unqualified
`selectedFunction` inside resolves to the property (its getter). So:
- first tap (nothing selected yet): `guard` fails → new value dropped, nothing happens;
- later taps: navigates to the *previously* selected function, never the tapped row.
`List(filteredFunctions, selection: $appState.functionNavigator)` therefore never updates the
selection highlight, and `selectFunction(_:)` (which assigns `functionNavigator = function`)
has the same no-op/stale behavior. Same bug for `sectionNavigator` + `SectionsListView`.
Fix: make it a real binding (`set(selectedFunction) { ... }` or bind the `List` directly to
`$appState.selectedFunction` and navigate in `.onChange`/`selectFunction`).

### G2. Inline filtering in computed properties — runs on every body pass, every keystroke
All five search navigators do:
```swift
var filteredFunctions: [Function] {
	searchText.isEmpty ? appState.functions
		: appState.functions.filter { $0.name.localizedCaseInsensitiveContains(searchText) || ... }
}
```
`filtered*` is re-evaluated on **every body evaluation** of the navigator (any `appState`
property it reads changes, or the parent re-renders — see A1), not just on keystrokes.
`localizedCaseInsensitiveContains` is expensive; over large `symbols`/`strings` lists this is a
per-render O(n) scan. Move filtering to the model (or `@State` results updated via
`.task(id: searchText)` with debounce). Same code shape ×5.

### G3. `FunctionsListView` — redundant identity
`.tag(func_)` is redundant when `List(data, selection:)` data is `Identifiable` (id =
`startAddress`), and `.id(func_.startAddress)` on the row content is redundant again. Also
`List` selection type is `Function?` while rows are re-created from `filteredFunctions` — fine,
but see G1.

### G4. `FunctionRow.displayName` reads `appState.renamedFunctions[address]`
The whole dictionary is one observed property → any rename anywhere invalidates **every visible
row**. Acceptable at sidebar scale; note only.

### G5. `StringsListView` row: `Spacer()` inside a `Button` label in a `List` row
`VStack { Text; Spacer(); Text(addr) }` — the `Spacer` does nothing useful in a fixed-height
List row; drop it. Otherwise rows are fine (plain button rows are an OK pattern).

### G6. `SymbolRow` / `SectionRow` — fine
Standard labels; `SymbolRow` reads no observable state (good — rows are pure value views and
skip well). `SectionRow` likewise.

### G7. Dead code in this area
`SearchSheet` (MainView.swift) is **unreachable** — `AetherContentView` presents
`SearchView` (Components/SearchView.swift). `ThemeManager`, `Theme`, `DisassemblerFont`
(ThemeManager.swift) are never referenced; the live colors are the static `Color(hex:)`
extensions in the same file. `Extensions/SwiftUI+.swift` is an empty file (`import SwiftUI`
only). Cartograph should flag all of these — delete.

---

## Aether/UI/Components/ThemeManager.swift — color system

### H1. Hardcoded sRGB dark palette with no light-mode adaptation
Every chrome surface uses static colors (`Color.background` #1E1E2E, `Color.sidebar` #181825,
`.addressColor`, …) resolved once in sRGB. In system Light Mode the panels stay dark Catppuccin
while system-provided controls/status bars adapt — mixed, low-contrast UI. Fix: asset-catalog
colors with light/dark variants (or `Color(nsColor:)` dynamic providers) keyed by the same
semantic names, and keep `Theme`/`ThemeManager` deleted or actually wire them in.

### H2. `Color(hex:)` via `Scanner` — fine
Handles 3/6/8-digit; no issue.

---

## Aether/UI/MainWindow/StatusBarView.swift

### I1. Broad observable reads
Reads `isLoading`, `loadingMessage`, `currentFile`, `functions.count`, `strings.count`,
`symbols` (→ `currentFile`), `selectedAddress` → re-renders on each loading stage and any file
replacement. View is tiny; acceptable.

### I2. `ByteCountFormatter()` allocated per body pass
Make it `static let`.

### I3. `StatBadge` labels are only in `.help`
The "N functions/strings/symbols" labels exist only as hover help; VoiceOver reads just the
number. Add `.accessibilityLabel("\(value) \(label)")`.

---

## Aether/UI/MainWindow/MainView.swift (WelcomeView, LoadingOverlay, GoToAddressSheet)

### J1. All three are fine
`WelcomeView`/`FormatBadge`: pure value views. `LoadingOverlay`: takes plain values
(message/progress) — good minimum-dependency shape; note the `ProgressView(value:)` is non-
interactive, fine. `GoToAddressSheet`: `@FocusState` + `.defaultAction`/`.cancelAction`
shortcuts, local `@State`, small model method call — the model sheet done right. `parseAddress()`
runs in `body` (for `.disabled`) and again on submit — trivial.

---

## Aether/UI/Components/SearchView.swift (the *live* search sheet)

### K1. `SearchResultRow(result:action:)` — closure in the row value
A fresh `action` closure is created on every `SearchView.body` pass → every row compares dirty
and re-renders on each keystroke/state change. Pass data + call `appState` from the row (rows
already have `@Environment` available) or accept it (rows are small; this is a mild violation).

### K2. Search races
`performSearch()` spawns `Task { await appState.search(...) }` per submit with no handle; two
quick submits run concurrently and the slower one can overwrite newer results. Keep the task in
`@State` and cancel, or `.task(id: query)`.

### K3. Clear button mutates the model directly
`appState.searchResults = []` from the view — works, but a `clearSearch()` model method is
cleaner and symmetric with `search(query:type:)`.

---

## Aether/UI/DisassemblyView/BranchVisualization.swift (`EnhancedInstructionRow` et al.)

### L1. `appState.currentFile!` force-unwrap in every row body
`Text(appState.currentFile!.format(hex: instruction.addressRange))` — crashes if a row is
rendered while `currentFile` is nil (e.g. closing the file mid-transition, or the "No binary
loaded" state racing the LazyVStack teardown). Same in `InstructionInspector`. Guard/optional-bind
once in the parent and pass a `BinaryFile?` down.

### L2. `format(hex:)` allocates a hex string per row, per body pass
`span.indices.map { String(format: "%02X", ...) }.joined` — a fresh String for every visible
row on every render. Cache the bytes-on-one-line string on `Instruction` at disassembly time
(one allocation, reused forever) or render bytes with a fixed-width `Text` per byte.

### L3. `EnhancedOperandsView` is a near-verbatim duplicate of `OperandsView`
`parseOperands`/`classifyOperand`/`isRegister` exist in **two** files (DisassemblyView.swift and
BranchVisualization.swift), both parsing in `body` (C6) and both rebuilding the register `Set`
per call (C8). Consolidate into one view + one static register set, or better, parse operands
once when the `Instruction` is created (the disassembler already knows operand kinds —
Capstone provides them; `Instruction` even has `kind`).

### L4. Hover-driven `popover`
`BranchIndicator.onHover → showTooltip → .popover` — hover-activated popovers grab focus and
flicker when the pointer crosses rows in a list; it's also an a11y oddity (no hover on touch).
Consider a lightweight overlay/tooltip, or show the 5-instruction target preview on tap of the
indicator.

### L5. `getTargetInstructions` — O(n) `firstIndex` on demand
Only runs on hover (popover content) — acceptable; could use `appState.instructionMap` for O(1).

### L6. Row reads `appState.comments[instruction.address]`
Whole-dictionary observation → any comment edit re-renders all visible rows (same as G4).
Acceptable at this scale; note only.

### L7. `BranchInfo.id = UUID()` regenerated per `analyzeBranches` call
`BranchAnalyzer` rebuilds all `BranchInfo` (new UUIDs) on every `loadInstructions`; the
`branches.first{...}` scan (C1) plus UUID churn means branch tooltips/sheets re-identify
wholesale. Keying `BranchInfo` identity by `sourceAddress` would stabilize it.

---

## Aether/Inspector/Inspector.swift

### M1. Reads `@ObservationIgnored var pcode` — no invalidation path
`InstructionInspector` renders `appState.pcode[instruction.pcode]`, but `pcode` is
`@ObservationIgnored`, so the Inspector registers **no dependency** on it. If p-code for the
selected instruction is produced after the Inspector last re-rendered (or is rebuilt by a
patch — cf. D11), the P-code section stays empty/stale with no update. Pass the p-code slice in
as a value from a caller that *does* track a changing property, or make a narrow observable
"pcode version" counter that the inspector reads.

### M2. `appState.currentFile!` force-unwrap + per-render `format(hex:)`
Same as L1/L2.

### M3. `selectedInstruction` getter does an O(n) walk per Inspector body pass
`appState.selectedInstruction` → `instructions(in:)` (D12). Inspector body runs on every
selection change — combine with the D12 fix.

### M4. Good: `Form` + `LabeledContent` + `ContentUnavailableView`
Standard components used correctly — keep this as the pattern for the other panels.

---

## Aether/Scene/AetherToolbar.swift

### N1. `hasAIAPIKey` → Keychain lookup in toolbar `body`
`appState.hasAIAPIKey` (and `apiKey`) hit `KeychainHelper.load` on **every toolbar body
evaluation** (several call sites: menu visibility + `.disabled`). A Security framework round-trip
per render. Cache the key presence on the model; refresh when Settings writes the key.

### N2. "CFG" button runs `analyzeAll()` — wrong action
The View-group "CFG" toolbar button calls `appState.analyzeAll()` instead of toggling
`appState.showCFG` (which is what `DetailView` actually renders). The CFG panel is unreachable
from the toolbar. Behavior bug.

### N3. Shortcut scheme
"Go to" uses bare `G` (no modifier) while CFG uses `⌘G` — inverted from convention (Go-to is
usually `⌘G`/`⌘L`). Minor UX.

### N4. Otherwise clean
`@Bindable` for toggles, `ToolbarItemGroup` with labels, `.disabled(...)` gating — good.

---

## Models — notes affecting view behavior

### O1. `BinaryFile.name` is hardcoded `"Unnamed"`
StatusBar, title bars, AI prompts, and the save panel all read `file.name` → always "Unnamed".
Plumb the loaded `URL.lastPathComponent` (or `FileHandle` name) into `BinaryFile` at load time.

### O2. `Instruction` identity by address — fine, with a caveat
`id`/`==`/`hash` all use `address` only. Correct for row identity, but it means a
re-disassembled instruction with identical address but different bytes (a patch) compares
**equal** — any `onChange(of:)`/Set/Dictionary use of `Instruction` won't see the change. Pairs
with D11 (cache never invalidated) — after fixing D11, consider including a byte hash or a
generation counter in `==` if any consumer needs it.

### O3. `Function` is an `@Observable` class with identity `==`/`hash` by `startAddress`
Good for `List` selection and reference sharing; note rows read `function.isLeaf`/`name`
(per-property tracking — fine). `BasicBlock` similarly.

### O4. `UUID()` ids on `CrossReference`/`StringReference`/`SearchResult`
Custom `==`/`hash` ignore the `id` (address-based) — consistent, so `List` identity is stable
per analysis pass. `SearchResult` ids churn on every search (results replaced wholesale) —
acceptable.

---

# Priority summary

## P0 — functional/correctness (the UI does the wrong thing)
| # | Where | Problem |
|---|-------|---------|
| G1 | `AppState.functionNavigator`/`sectionNavigator` | Setter ignores `newValue` → sidebar function/section selection never works; `selectFunction` no-op/stale |
| F1 | `DecompilerView` | Decompile keyed on empty output → switching functions shows the *previous* function's decompilation, never re-runs |
| D11 | `AppState.clearDisassemblyCache` | Never fixes `instructionMap`/`disassembled`; `default: 0`; crashes on empty cache → patches corrupt/never refresh disassembly |
| L1/M2 | `EnhancedInstructionRow`, `InstructionInspector` | `appState.currentFile!` force-unwraps → crash risk on close/transition |
| N2 | `AetherToolbar` | "CFG" button runs `analyzeAll()`; CFG panel unreachable from toolbar |
| B2 | `RenameSheet` | "Reset" calls `onSave("")` — persists an empty rename |
| O1 | `BinaryFile.name` | Always "Unnamed" everywhere |
| D14 | `AppState.saveFile()` | `preconditionFailure` from a menu action → app crash |

## P1 — performance anti-patterns (the expensive ones)
1. **A1/D1** god model + root view reading ~25 properties → `AetherContentView.body` re-runs on
   nearly every state change; splits `NavigationSplitView`/sidebar/detail re-evaluation. Split
   `AppState` into sub-models and narrow each view's reads.
2. **C1** `branches.first{...}` per row per render (O(n²)); pass a `[UInt64: BranchInfo]`.
3. **C2/C3** whole collections (`allInstructions`, `branches`, `instructions`) passed into rows
   and headers — defeats row skipping; pass minimum data.
4. **C6/L3** operand string parsing + register-`Set` rebuild in `body`, duplicated in two files;
   parse once at disassembly time (Capstone already classifies operands).
5. **F2/F3/F4** decompiler tokenizer runs in `body` per line per pass; eager `VStack`;
   index-identity `ForEach` ×2. Tokenize once into `[AttributedString]` + `LazyVStack`.
6. **G2** inline `filtered*` computed properties in 5 navigators (per-render, per-keystroke).
7. **C5** `loadInstructions` — uncancelled `Task`s, double load on first appear;
   `.task(id:)` with a composite (file, function, section) id.
8. **N1** Keychain lookup in toolbar `body` (multiple call sites per render).
9. **L2** per-row `format(hex:)` String allocation per render; cache on `Instruction`.
10. **D12/M3** `instructions(in:)` O(n) byte walk per call (selection, inspector).

## P2 — hygiene / robustness / a11y
- H1: no light-mode color adaptation (static dark palette).
- G7: dead code — `SearchSheet`, `ThemeManager`/`Theme`/`DisassemblerFont`,
  empty `Extensions/SwiftUI+.swift`.
- E5: hex `scrollTo` dead (FIXME) + empty `withAnimation`; the go-to-address feature doesn't work.
- E2: deprecated single-parameter `onChange` forms (HexView; check others).
- E6: `Picker("")` empty a11y label (HexView); I3: `StatBadge` labels not exposed to VoiceOver.
- E8: `isprint` locale-dependent rendering of high bytes in the ASCII column.
- A4: `if/else` panel toggles in `DetailView` break structural identity (state loss on toggle);
  consider `.opacity`/`AnyLayout` for the frequently toggled decompiler panel.
- A3/D18: `undoManager` set in `onAppear` — until then, undo registrations are silently dropped.
- K1/K2: closure in `SearchResultRow`; uncancelled racing search tasks.
- L4: hover-driven popover UX; L7: `BranchInfo` UUID identity churn.
- C8/F5: per-call `Set`/allocation in hot paths (register set, `lowercased()` per char).
- M1: Inspector's p-code reads a non-observable array → no invalidation.
- O2: `Instruction` `==` by address masks patched-byte changes (revisit after D11 fix).

## Suggested first fixes (small, high value)
1. G1 — make the navigator setters real bindings (2-line fix, un-breaks the sidebar).
2. F1 — `.task(id: selectedFunction?.id)` in `DecompilerView`.
3. D11 — fix `clearDisassemblyCache` (remove map keys, shrink `disassembled`, bound-check).
4. B2 — make "Reset" a cancel.
5. L1/M2 — replace `currentFile!` with a guard.
6. N1 — cache `hasAIAPIKey`.
7. N2 — point the CFG button at `showCFG`.
Then the P1 structural work (split `AppState`, cache per-row data, tokenize decompiler output
off-`body`).
