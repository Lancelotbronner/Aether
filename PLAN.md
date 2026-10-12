# Plan: Migrate the main App UI to SwiftData models

Living document — update the checkboxes as phases land. Baseline: branch
`experiment/swift-data` @ `591c157` ("Converted document to SwiftData, load
Mach-O binaries into document").

Scope: sidebar (ProgramNavigator + the five list navigators), DisassemblyView,
HexView, DecompilerView — i.e. everything the user drives day-to-day. The
AI/malware/Frida sheet zoo, emulators, and analyzers are *consumers* that get
adapters, not rewrites, in this plan.

---

## 1. Current state

### 1.1 Document infrastructure (done)

- `AetherScene` uses the `_SwiftData_SwiftUI` bridge:
  `DocumentGroup(editing modelTypes: [any PersistentModel.Type], contentType:, editor:, prepareDocument:)`.
  `.project` for `editing:` resolves to the `Array<any PersistentModel.Type>.project`
  extension in `Schema.swift`; the second `.project` is `UTType.project`
  (`.package`-conforming, declared in `AetherScene.swift`).
- Consequences that the rest of the plan relies on:
	- Each open document is a package folder with **its own `ModelContainer`**.
	- `AetherRootView`'s `@Environment(\.modelContext)` is **document-scoped**;
	  every `@Query` below is automatically scoped to that document. No manual
	  container plumbing in views.
	- Autosave is built in. `saveProject`/`loadProject`/`ProjectData`/`Project`/
	  `ProjectManager` are superseded (delete in Phase 6, verify dead first).
	- `prepareDocument:` is currently empty — fine; a new document is an empty
	  container. `NewDocumentAction(contentType:prepareDocument:)` is the
	  customization point if we ever want to seed one.
- `AetherRootView` owns `@State private var session = AppState()` per window —
  this object is the future **Session** (see §2).

### 1.2 Schema (`Aether/Schema/Schema.swift`)

| Model | Purpose | Notes |
| --- | --- | --- |
| `BinaryModel` | one program | `embedded: Data` (`@Attribute(.externalStorage)`) holds the file bytes; `fileURL` records the source; `entryPoint`, `baseAddress`, arch/format/endian |
| `SegmentModel` | segment | `#Unique([\.binary, \.address])` |
| `SectionModel` | section | has `contains(address:)`, `containsCode`, `fullName` |
| `SymbolModel` | symbol | `isImport`/`isExport` computed from `binding` + `address` |
| `ProcedureModel` | function | `callers`/`callees` relationships, `BlockModel` for CFG |
| `BlockModel` | basic block | CFG edges |
| `StringModel` | string ref | `@Transient cached: String?` — value is lazy, "not loaded" until populated |
| `CrossReferenceModel` | xref | from/to/type |
| `AnnotationModel` | comment | `kind` (inline/trailing), `address`, `text` |
| `BookmarkModel` | bookmark | name/address/summary/created |

### 1.3 What `AppState` still owns (today)

| Property | Verdict |
| --- | --- |
| `currentFile: BinaryFile?` | Replace with `currentBinary: BinaryModel?` |
| `functions/strings/imports/exports: [OldModel]` | Delete — `@Query` on the models |
| `symbolsByAddress/symbolsByName/functionsByAddress` | Keep as `@ObservationIgnored` session caches, rebuilt from queries |
| `selectedAddressRange`, `selectedAddress`, `selectedInstruction` | Keep (session); retype function/section below |
| `selectedFunction: Function?`, `selectedSection: _Section?` | Retype to `ProcedureModel?` / `SectionModel?` |
| `functionNavigator` / `sectionNavigator` setters | **Delete** — this is the G1 bug (setter ignores `newValue`, so sidebar selection never registers). Direct `List(selection:)` binding replaces them |
| `instructions/instructionMap/pcode/disassembled` (disassembly cache) | Keep in session (transient); retype inputs to models; fix D11 |
| `decompilerOutput: String` | Replace with per-procedure state (Phase 5, fixes F1) |
| `renamedFunctions/renamedSymbols: [UInt64: String]` | Move to `renamedName` fields on the models (Phase 0) |
| `comments/bookmarks: [UInt64: …]` | Use `AnnotationModel`/`BookmarkModel` (already in schema) |
| `patches`, `patcher`, `hasUnsavedChanges` | Hold — patching rework is separate; §9 |
| `isLoading/loadingProgress/loadingMessage` | Keep (session), drive them from import/parse tasks |
| AI/malware/Frida/search/chat state | Keep (session); retype `BinaryFile` parameters via adapter (§3.5) |
| `loadFile(data:)`, `openFile`, `closeFile` | Delete after retype (Phase 6) |
| `undoManager` | Keep, but wire to the document context (§3.6) |

### 1.4 Gaps in `MachOLoader.machO(for:)` (the model-based loader)

1. **Section address bug**: `section.address = UInt64(item.offset)` uses the
   *file offset*, not the VM address. The old `parseSection64` used `sect.addr`.
   Fix: `section.address = item.addr`, `section.offset = item.offset`.
2. **No symbol parsing**: the `LC_SYMTAB` case is commented out. Port
   `parseSymtab`/`processSymbol` to emit `SymbolModel` (and
   `ProcedureModel` for function symbols, mirroring the old
   `loadFile` heuristic `type == .function && address != 0` →
   `endAddress = address + max(size, 256)`).
3. **No guard against re-parsing**: context-menu "Load..." on an already-parsed
   binary duplicates segments/sections. Guard on `model.segments.isEmpty`.
4. **Fat binaries**: `load(_:)` has the fat branch commented out; 32-bit
   `fatalError`s. Document as unsupported for now.
5. **`embedded` must be set before `load(_:)`** — true for the Import command
   (sets `embedded` from the picked file); keep that ordering and assert it.

---

## 2. Target architecture

```
Document (package folder)
└── ModelContainer (per document, owned by SwiftUI)
    ├── BinaryModel ⇄ SegmentModel ⇄ SectionModel     ← persistent facts
    ├── SymbolModel, ProcedureModel ⇄ BlockModel
    ├── StringModel, CrossReferenceModel
    └── AnnotationModel, BookmarkModel                 ← user annotations

AetherRootView (@State per window)
└── AppState = the "Session"
    ├── selection:   currentBinary, selectedFunction, selectedSection,
    │                selectedAddressRange                ← model references
    ├── transient:   disassembly cache, decompilation states, search results
    ├── ui flags:    showHexView, sidebarSelection, sheet booleans
    └── services:    disassembler engine, decompiler, AI client, …
```

Rules:

1. **Persistent facts live in SwiftData; nothing else does.** The session may
   *reference* models, never duplicate their data.
2. **Selection is a model reference on the session.** `List(selection:)` binds
   straight to it (SwiftData models are `Hashable` via `persistentModelID`).
   The broken computed-property "navigator" indirection goes away.
3. **Views read models, session reads happen in the smallest subview** that
   renders them. Rows take model references or plain values (`isSelected: Bool`,
   `commentText: String?`) as stored properties — a body re-runs only when the
   value it reads changes, not when some unrelated session property does.
4. **Bytes are read from the binary on demand** (`BinaryModel.data(in:)`),
   never copied into models. `HexView` may hold a transient `Data` slice for
   the visible section.

---

## 3. Phase 0 — Foundations

### 3.1 Schema additions

```swift
// In SymbolModel and ProcedureModel — replaces renamedSymbols/renamedFunctions dicts
var renamedName: String?

// Computed display name becomes:
var displayName: String {
	renamedName ?? <existing logic>
}
```

Comments already have `AnnotationModel`; bookmarks `BookmarkModel`. No new
models needed for the four view families.

### 3.2 Binary byte access

`BinaryModel` needs the same ranged read the old `BinaryFile` had:

```swift
extension BinaryModel {
	/// File bytes for a virtual address range (same convention as the old
	/// BinaryFile.data(in:) — file offset = address - baseAddress).
	func data(in range: Range<UInt64>) -> Data? {
		let lower = Int(range.lowerBound - baseAddress)
		let upper = lower + range.count
		guard lower >= 0, upper <= embedded.count else { return nil }
		return embedded[lower..<upper]
	}
}
```

Caveat: touching `embedded` materializes the **entire** external-storage file
as a `Data` in RAM. Fine for Phase 1; if that bites, Phase 6b adds a
security-scoped bookmark (`var bookmark: Data?` on `BinaryModel`, written in
the Import command next to `fileURL`) and reads via
`Data(contentsOf: url, options: .mappedIfSafe)` — that restores the
memory-mapping behavior of commit `96eaa52`.

### 3.3 Fix `MachOLoader.machO(for:)`

Apply the §1.4 fixes: `item.addr` vs `item.offset`, port `LC_SYMTAB`,
re-parse guard. Sketch of the symbol port (the rest is mechanical):

```swift
case LC_SYMTAB:
	let symtab = bytes.unsafeLoad(as: symtab_command.self)
	// embedded is a single file, so stroff/symoff are already absolute file offsets
	for sym in /* nlist_64 span over bytes at symtab.symoff, count symtab.nsyms */ {
		let modelSymbol = SymbolModel(in: model)
		modelSymbol.name = /* as processSymbol */
		modelSymbol.address = sym.n_value
		modelSymbol.type = /* as processSymbol */
		modelSymbol.binding = /* as processSymbol */
		model.symbols.append(modelSymbol)
		if modelSymbol.type == .function, sym.n_value != 0 {
			let proc = ProcedureModel(in: model)
			proc.name = modelSymbol.name
			proc.startAddress = sym.n_value
			proc.endAddress = sym.n_value + 256 // refined later by FunctionAnalyzer
			model.procedures.append(proc)
		}
	}
```

(Keep the existing `processSymbol` classification logic; it maps
`nlist_64` → `SymbolType`/`SymbolBinding` unchanged.)

### 3.4 Retype session selection

```swift
@Observable
final class AppState {
	// Selection — model references, not old class models
	var currentBinary: BinaryModel?
	var selectedFunction: ProcedureModel?
	var selectedSection: SectionModel?
	var selectedAddressRange: Range<UInt64> = 0..<0

	// Lookup caches (rebuilt when queries change; @ObservationIgnored, as today)
	@ObservationIgnored var proceduresByAddress: [UInt64: ProcedureModel] = [:]
	@ObservationIgnored var symbolsByAddress: [UInt64: SymbolModel] = [:]
	@ObservationIgnored var symbolsByName: [String: SymbolModel] = [:]
	...
}
```

`goToAddress`/`select` keep their shape, reading models:

```swift
func goToAddress(_ address: UInt64) {
	guard let binary = currentBinary else { return }
	if let section = selectedSection, section.contains(address: address) {} else {
		selectedSection = binary.sections.first { $0.contains(address: address) }
	}
	if let function = selectedFunction, function.contains(address: address) {} else {
		selectedFunction = binary.procedures.first { $0.contains(address: address) }
	}
	selectedAddressRange = address..<(address + 1)
}
```

(Linear scans are fine while function counts are modest; if not, add
`proceduresByAddress` lookups — the cache is already planned.)

Also: the `functionNavigator`/`sectionNavigator` computed properties and the
old `selectFunction(_:)`/`selectSection(_:)` wrappers are deleted — the
`List(selection:)` bindings in §4/§5 replace them (fixes G1).

### 3.5 Adapter so analyzers keep compiling

`Decompiler`, `FunctionAnalyzer`, `StringAnalyzer`, `XRefAnalyzer`,
`MalwareAnalyzer` et al. take the old `BinaryFile`. Don't rewrite them now —
build one:

```swift
extension BinaryFile {
	/// Analysis facade reconstructed from a SwiftData model.
	convenience init(model: BinaryModel) {
		let sections = model.sections.map { s in
			_Section(name: s.name, segmentName: s.segmentName, address: s.address,
				size: s.size, offset: s.offset, alignment: s.alignment, flags: s.flags,
				data: model.data(in: s.addressRange) ?? Data())
		}
		// segments/symbols likewise from the models
		self.init(format: model.format, architecture: model.architecture,
			endianness: model.endian, is64Bit: model.is64,
			fileSize: model.embedded.count, entryPoint: model.entryPoint,
			baseAddress: model.baseAddress,
			sections: sections, segments: segments, symbols: symbols,
			data: model.embedded)
	}
}
```

Session code paths that need the old API (`decompileCurrentFunction`,
`analyzeAll`, …) do `guard let binary = currentBinary, let file = ...` via this
adapter until the analyzers themselves are migrated (out of scope here).
Note the adapter copies `embedded` — for the heavy analyzers that's acceptable
since they already needed the full file.

### 3.6 Undo

Session `registerUndoRedo` currently uses an environment `UndoManager` captured
in `AetherContentView.onAppear`. With SwiftData, model mutations (rename,
comment, bookmark) go through `modelContext`, so document-level undo can use
`modelContext.undoManager` (SwiftData supports undo when a context has an
undo manager; the DocumentGroup wires one per document). Migrate the
annotation mutations to the model context first; keep the manual
`registerUndoRedo` only for session-only state.

### 3.7 Bootstrap

Replace the commented `session.bootstrap(context:)` in `AetherRootView.task`:

```swift
.task {
	await session.bootstrap()
}
// in AppState
func bootstrap() async {
	guard currentBinary == nil, let first = try? modelContext... // see below
}
```

Simplest v1: `AetherRootView` queries `BinaryModel` (or the session reads via
a `FetchDescriptor` in `.task`); if exactly one binary exists and it's
unparsed, run `MachOLoader.load(_:)`; set `currentBinary`; select its first
code section. Multi-binary default selection is an open question (§10).

---

## 4. Phase 1 — ProgramNavigator selection

The navigator shows binary → segment → section. Two things are selectable:
a **binary** (sets `currentBinary`, kicks parsing) and a **section** (sets
`selectedSection` + jumps). Use an enum selection tag so one
`List(selection:)` covers both:

```swift
enum NavigatorSelection: Hashable {
	case binary(BinaryModel)
	case section(SectionModel)
}
```

```swift
struct ProgramNavigator: View {
	@Environment(\.modelContext) private var modelContext
	@Environment(AppState.self) private var appState
	@Query(sort: \BinaryModel.name) private var binaries: [BinaryModel]
	@State private var expanded: Set<PersistentIdentifier> = []

	var body: some View {
		@Bindable var appState = appState
		List(selection: $appState.programSelection) {
			ForEach(binaries) { binary in
				DisclosureGroup(isExpanded: binding(for: binary.persistentModelID)) {
					ForEach(binary.segments) { segment in
						// segment label row (not selectable) + its sections
						ForEach(segment.sections) { section in
							SectionLabel(model: section)
								.tag(NavigatorSelection.section(section))
						}
					}
				} label: {
					BinaryLabel(model: binary)
						.tag(NavigatorSelection.binary(binary))
				}
			}
		}
		.onChange(of: appState.programSelection) { _, selection in
			switch selection {
			case .binary(let binary):
				appState.currentBinary = binary
				Task { try? MachOLoader.load(binary) } // guarded against re-parse
			case .section(let section):
				appState.currentBinary = section.binary
				appState.selectedSection = section
				appState.goToAddress(section.address)
			case nil:
				break
			}
		}
	}
}
```

Notes:

- `programSelection: NavigatorSelection?` lives on the session (it's shared
  with the other tabs: selecting a function in the Functions tab should
  update/clear it if you want cross-tab coherence; otherwise keep it
  `@State` here and propagate effects only).
- Keep the context menu (Load…/Delete). "Delete" already cascades via the
  schema relationships; also clear session selection if the deleted model is
  selected (`onChange` of `binaries` or a `NSManagedObjectContextDidDelete`-free
  check: just re-verify in `bootstrap`-style passes — SwiftData models report
  `isDeleted`).
- `DisclosureGroup` inside a selectable `List` works; row `.tag` makes child
  rows selectable. If the disclosure chevron fights with row selection on
  macOS, the fallback is `OutlineGroup` with the same tags.

Acceptance: clicking a section row selects it (visible in the list), sets the
hex/disassembly target; clicking a binary parses it (if needed) and marks it
current; switching binaries clears function/section selection
(`onChange(of: appState.currentBinary)` → nil them out).

---

## 5. Phase 2 — The other sidebar tabs

All five follow one pattern: **a parent view owns the search text; a child
view builds the `@Query` with a `#Predicate` in its `init`** (a query cannot
be rebuilt from a changing `@State` after the fact, and filtering/sorting in
`body` is the anti-pattern the SwiftUI audit flagged). Selection binds
straight to the session.

### 5.1 Functions

```swift
struct FunctionsTab: View {
	@Environment(AppState.self) private var appState
	@State private var search = ""

	var body: some View {
		@Bindable var appState = appState
		VStack(alignment: .leading) {
			TextField("Search", text: $search, prompt: Text("Filter"))
			FunctionList(search: search, selection: $appState.selectedFunction)
		}
	}
}

private struct FunctionList: View {
	@Query private var procedures: [ProcedureModel]
	@Binding var selection: ProcedureModel?

	init(search: String, selection: Binding<ProcedureModel?>) {
		_selection = selection
		if search.isEmpty {
			_procedures = Query(sort: \ProcedureModel.startAddress)
		} else {
			_procedures = Query(
				filter: #Predicate<ProcedureModel> {
					$0.name.localizedStandardContains(search)
				},
				sort: \ProcedureModel.startAddress
			)
		}
	}

	var body: some View {
		List(procedures, selection: $selection) { procedure in
			FunctionRow(model: procedure)
				.listRowSeparator(.hidden)
		}
	}
}
```

`FunctionRow` changes:

- takes `let model: ProcedureModel` (class reference — cheap, identity-stable);
- display name: `model.displayName` (which now folds in `renamedName`);
- "Rename…" sheet saves by `model.renamedName = name` (autosaved by SwiftData,
  undoable via the document context) instead of `appState.renameFunction`;
- "Go to address" → `appState.goToAddress(model.startAddress)`;
- selection tap already flows through the `List` binding — the row does not
  need `.tag` or `isSelected` (List renders selection state itself). The old
  `isSelected: appState.selectedFunction == func_` prop is deleted.

### 5.2 Strings

Same shape. `StringModel` has no in-model value column (only
`@Transient cached`), so either:

- **(recommended)** populate `cached` at load time (`StringModel` init already
  accepts `cached:`) and display `model.value`; or
- read the value lazily in the row via `model.binary.data(in:)` + the
  encoding — only when the row appears.

Selection: strings aren't a "selection object" for the detail views, so keep
the current UX — row tap calls `appState.goToAddress(model.address)`. No
`List(selection:)` needed (or use one purely for highlighting).

### 5.3 Imports / Exports / Symbols

One shared `SymbolList` with a predicate parameter:

```swift
init(binary: BinaryModel?, isImport: Bool?, isExport: Bool?, search: String)
```

Predicate caveat: `#Predicate` is unreliable on Codable-enum properties
(`binding`). Stick to scalar fields:

- Imports: `$0.address == 0` (per `SymbolModel.isImport` that's the external
  no-address set) — optionally `&& $0.binding == ...` only if the stored type
  cooperates in testing;
- Exports: `$0.address != 0 && $0.name != ""` refined to the global set if the
  enum predicate works, else filter in the child `init` after a
  `FetchDescriptor` (symbol counts per binary are usually manageable;
  100k+ symbols → measure before optimizing).
- Symbols tab: no filter, `Query(sort: \SymbolModel.address)`.

Rows: `SymbolRow` takes `let model: SymbolModel`, tap → `goToAddress`.

### 5.4 Delete the now-dead session arrays

`functions`, `strings`, `imports`, `exports`, `xrefs` (+ the lookup-cache
refill in `loadFile`) go away once every reader is converted. `StatusBarView`
is one reader (counts) — convert it to a small subview with `@Query` counts
(`FetchDescriptor` + `fetchCount`) or pass counts in from a `@Query` parent.

---

## 6. Phase 3 — DisassemblyView (+ Inspector, rows)

### 6.1 Load path

`loadInstructions()` retypes to the models:

```swift
.onChange(of: appState.selectedFunction) { _, function in
	guard let function else { return }
	load { await appState.disassemble(procedure: function) }
}
.onChange(of: appState.selectedSection) { _, section in
	guard let section, section.containsCode else { return }
	load { await appState.disassemble(section: section) }
}

private func load(_ fetch: @escaping () async -> ArraySlice<Instruction>) {
	isLoading = true
	Task {
		let result = await fetch()
		guard !Task.isCancelled else { return }
		instructions = result.prefix(maxInstructions)
		branches = BranchAnalyzer.analyzeBranches(instructions: instructions)
		isLoading = false
	}
}
```

Session `disassembleIfNecessary` keeps its `RangeSet`/`instructionMap`
machinery but:

- takes `ProcedureModel`/`SectionModel` parameters and pulls bytes via
  `binary.data(in: range)`;
- is keyed per binary — clearing `currentBinary` clears the cache (extend the
  `closeFile`-style reset, or give the cache a `binaryID: PersistentIdentifier?`
  guard that invalidates on mismatch);
- **fix D11** (`clearDisassemblyCache`): after `instructions.removeSubrange`,
  `instructionMap` still holds old absolute indices. Rebuild the map for the
  affected suffix (or the whole map — it's O(n) over cached instructions,
  fine) and re-anchor `pcode` offsets. Until that lands, don't call it from
  patching code paths.

### 6.2 Rows take values, not AppState

`EnhancedInstructionRow` today reads `appState.currentFile!` (force-unwrap —
crash if no binary) and `appState.comments[...]` per row. Change the row to:

```swift
struct EnhancedInstructionRow: View {
	let instruction: Instruction
	let bytesText: String        // precomputed: binary.format(hex: insn.addressRange)
	let isSelected: Bool
	let branchInfo: BranchInfo?
	let commentText: String?     // from AnnotationModel, not a session dict
	...
}
```

`DisassemblyView` precomputes `bytesText` per row at load time (it has the
binary's `Data` anyway) and resolves comments by fetching the document's
`AnnotationModel`s once (a `@Query` in the view, mapped to
`[UInt64: String]` in a child subview's `body` — the *row* still only sees a
plain `String?`). Tap → `appState.select(insn.addressRange)` (unchanged).
Context-menu "Go to target"/copy unchanged (session call).

`Inspector` (reads `selectedInstruction`, `currentFile!.format(hex:)`,
`pcode`) gets the same treatment: derive `selectedInstruction` as today, pass
bytes as a value. It's driven by the same selection, so no new plumbing.

### 6.3 Scroll-to-selection

Keep the existing `onChange(of: appState.selectedAddress)` +
`proxy.scrollTo` (it works). Don't mix in the HexView FIXME — different view.

---

## 7. Phase 4 — HexView

### 7.1 Data source

`SectionModel` has no bytes; the section's data is a slice of the binary.
Replace `onChange(of: selectedSection) { data = section.data }` with a
load task over the model:

```swift
@State private var store: HexStore?

.task(id: appState.selectedSection?.persistentModelID) {
	guard let section = appState.selectedSection,
	      let data = section.binary.data(in: section.addressRange) else {
		store = nil
		return
	}
	store = HexStore(baseAddress: section.address, data: data)
}
```

```swift
struct HexStore {
	let baseAddress: UInt64
	let data: Data
}
```

This is a deliberate transient copy of *one section* (same as today's
`section.data`); the binary itself stays in `embedded`/mmap territory.

### 7.2 Row-level selection (the real perf win)

Today every `HexRow` reads `appState.selectedAddressRange` → every visible
row's body re-runs on every selection change. Split the read to the row with
a plain value:

- `HexView.body` computes `selectedRange: Range<UInt64>?` once;
- each row gets `let isSelected: Bool` (and optionally
  `highlightOffsets: Range<Int>?` if you want per-byte tint) — a stored
  `Bool` only changes on the ≤2 rows the selection crosses, so only those
  bodies re-run;
- the row's tap still calls `appState.goToAddress(byteAddress)`.

Don't split the *model* for this — the lever is which body reads what.

### 7.3 Keep / defer

- `bytesPerRow` stays local `@State` (or `@AppStorage` if it should persist —
  trivial).
- The `scrollTo` FIXME (building all rows on the way) stays deferred;
  options if revisited: cap the visible window, or `scrollPosition(id:)` with
  a bounded LazyVStack. Not a blocker for the migration.

---

## 8. Phase 5 — DecompilerView (fixes F1)

The single global `decompilerOutput: String` is why the panel shows the
*previous* function's output. Key decompilation state by procedure:

```swift
struct Decompilation {
	enum Phase {
		case running
		case done(String)
		case failed(String)
	}
	let procedureID: PersistentIdentifier
	var phase: Phase
}

// on AppState (session)
var decompilations: [PersistentIdentifier: Decompilation] = [:]
var currentDecompilation: String {
	guard let id = selectedFunction?.persistentModelID else { return "" }
	return decompilations[id]?.phase.extracted() ?? ""
}
```

View:

```swift
struct DecompilerView: View {
	@Environment(AppState.self) private var appState

	var body: some View {
		DecompilerPanel(
			functionID: appState.selectedFunction?.persistentModelID,
			decompilation: appState.selectedFunction.flatMap {
				appState.decompilations[$0.persistentModelID]
			}
		)
		.task(id: appState.selectedFunction?.persistentModelID) {
			guard let function = appState.selectedFunction else {
				appState.decompilations = [:] // or prune on binary change
				return
			}
			await appState.decompile(function)
		}
	}
}

private struct DecompilerPanel: View {
	let functionID: PersistentIdentifier?
	let decompilation: Decompilation?
	...
	// switches on decompilation?.phase:
	//   nil → "No function selected" / "Decompiling…" placeholder
	//   .running → ProgressView
	//   .done(let code) → ScrollView { SyntaxHighlightedCode(code: ...) }
	//   .failed(let message) → ContentUnavailableView
}
```

Why this shape:

- `.task(id:)` cancels the in-flight decompilation when the selection changes
  (pair with `Task.checkCancellation()` in the decompile pipeline) — no more
  racing write into a shared string (the old
  `if self.selectedFunction?.startAddress == function.startAddress` guard went
  away).
- Each function's output is keyed, so switching back and forth is a cache hit;
  prune the dict on binary change to bound memory.
- `currentDecompilation` keeps the AI features (chat context, rename, Frida
  gen) compiling with one line of session API; they continue to read "the
  output for the selected function".

`appState.decompile(_ procedure: ProcedureModel) async` reuses
`disassemble(procedure:)` for instructions and the `Decompiler` via the
`BinaryFile` adapter (§3.5). Java path (`decompileJavaMethod`) needs the
`JARLoader.JavaClass` list — today sourced from `binary.javaClasses`; with the
adapter that stays available on the facade (or on the session while the JAR
loader is reworked — out of scope).

---

## 9. Phase 6 — Cleanup & deletions

Verify each item is unreferenced (build is the oracle) before deleting:

1. `AppState`: `currentFile`, `loadFile(data:)`, `openFile`, `closeFile`
   (replace with a `resetSelection()` used when the current binary is deleted),
   `functions/strings/imports/exports/xrefs` arrays, `renamedFunctions/
   renamedSymbols/comments/bookmarks` dicts, `saveProject/loadProject/
   openProject/saveProjectAs`, `ProjectData`/`PatchData` structs.
2. `Aether/Models/Project.swift` — `Project`/`ProjectManager`/`Bookmark`
   (believed dead since 2026-10-11; confirm with a build after the above).
3. `MachOLoader`: the old `loadMachO`/`parseSegment32/64`/`parseSection32/64`/
   `parseSymtab`/`loadFatBinary`/`BinaryFile`-returning `load(data:)` — delete
   once `BinaryLoader`'s `canLoad`/dispatch is updated to the model-based
   entry (or keep `BinaryLoader` as the format-dispatcher that routes to
   `machO(for:)` etc.).
4. Old model classes (`Function`, `Segment`, `_Section`, `Symbol` struct,
   `StringReference`, `CrossReference`, `BasicBlock`) — only deletable once
   the analyzers stop using `BinaryFile`; until then the adapter (§3.5) keeps
   them alive *by reference only*.
5. `AetherCommands`: `currentFile` → `currentBinary` in every `.disabled(...)`
   and save/export path; "Close" (`appState.closeFile`) → reset selection.
6. `AetherToolbar`: same retypes (it reads `selectedFunction`, `functions`,
   `decompilerOutput`, `currentFile`).
7. `hasUnsavedChanges`/patching: with document autosave, patching `embedded`
   *is* the save. Recommendation: patching applies to `BinaryModel.embedded`
   (copy-on-write the `Data`) and drops `BinaryPatcher.save(to:)`; the
   `Patch` list can become a `PatchModel` or stay session-transient with
   "revert" re-reading `fileURL` (open question — §10).
8. `Info.plist`: the exported `UTType` (`com.lancelotbronner.aetherproj`)
   must list the package's contents if the OS should peek inside (optional;
   the container works without it).

---

## 10. Open questions / risks

- **Multi-binary default**: with N binaries in a document, what is
  `currentBinary` on open? Options: last-opened (persist a
  `DocumentSettings` model), first in `name` order, or none (welcome pane).
  Suggest: none → welcome pane, until the user picks one.
- **Codable-enum predicates** (`SymbolModel.binding` in `#Predicate`):
  test early; fallback is scalar-only predicates + child-init filtering.
- **`StringModel.cached` population**: strings must be filled at load or the
  Strings tab shows "not loaded". Decide: fill in the loader (Mach-O has no
  string table — needs the `StringAnalyzer` scan, i.e. "Analyze All") or lazy
  per-row read. Suggest lazy read for the tab, eager fill after analysis.
- **Undo semantics** of model mutations under DocumentGroup autosave —
  verify `modelContext.undoManager` is non-nil in the document window before
  retiring the manual `registerUndoRedo` paths.
- **Memory**: `embedded` materialization vs mmap bookmark (Phase 6b, §3.2).
- **`#Unique([\.binary, \.address])` on symbols**: symbols can legitimately
  share an address (local + global at same site, zero-size data). Verify the
  constraint doesn't reject real binaries during import; if it does, drop the
  unique on `SymbolModel`.

---

## 11. Verification (per phase)

Build after each phase:

```sh
xcodebuild -project Aether.xcodeproj -scheme Aether -destination 'platform=macOS' build
```

Manual smoke (keep a sample Mach-O handy, e.g. a Homebrew binary or
`/bin/ls`):

1. New document → import binary (⇧⌘O) → row appears in Programs tab, parsed
   (segments/sections expandable, no duplication on re-Load).
2. Click a section row → DisassemblyView shows instructions for it; HexView
   shows its bytes; status bar shows the address; Functions tab selection
   follows (a function containing the address highlights).
3. Click a function row → disassembly reloads; DecompilerView shows *that*
   function's output (switch functions twice quickly — no stale output,
   no "Decompiling…" stuck state).
4. Click bytes in HexView → selection moves in disassembly + inspector;
   only touched hex rows visibly re-render (watch with Instruments
   SwiftUI template if in doubt).
5. Rename a function in the context menu → persists across document
   close/reopen; ⌘Z reverts it.
6. Close document, reopen → everything above reproduces from the package
   alone (delete nothing from the package folder first — that's the point).
