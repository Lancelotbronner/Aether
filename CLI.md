# Aether CLI — feature backlog

Scratch space holds the analysis scripts used while fixing the Mach-O loader and writing `ProcedureDetector`.
Most are throwaway re-implementations of things the CLI should do natively: they take a raw binary path, hand-parse the header, and print what `aether` cannot print today.
Living list. Each entry names its scratch evidence, the proposed CLI surface, and the cost in AetherKit terms, plus a status line where the proposal has partially landed.
Implemented entries are deleted rather than left behind, so the numbering has permanent gaps; entry numbers never shift, which keeps cross-references such as "entry 19" valid across edits.

## Verified CLI surface today (HEAD `0abcc98`)

`aether --help` registers seven model groups — `program`, `section`, `segment`, `symbol`, `procedure`, `annotation`, `bookmark` — plus `import`; `new` is gone because the project argument is created on demand.
Every group carries `fetch` / `count` / `delete`; every group except `program` also carries `insert`, and `procedure` additionally carries `detect`.
No group sets `defaultSubcommand`, so the subcommand has to be spelled out. The project is a positional `<project>` argument, and because option groups come first in the parse order it is always the first positional — `aether symbol fetch D`, `aether symbol insert D bin name address`.
`Sources/Fetch<T>.swift` is the read-side machinery: a `FetchableModel` protocol with `plural`, `describe()`, an associated `FetchOptions` defaulting to `EmptyOptions` (`Sources/Utilities.swift`), `static var subcommands`, and `static func apply(_:to:)` to decorate the `FetchDescriptor` with a predicate and `sortBy`.
`CountCommand` and `DeleteCommand` take the same `Model.FetchOptions`, so every filter below is also a filter on `count` and on `delete`.
`Sources/Insert<T>.swift` is the write side: an `InsertableModel` protocol with `singular`, `describe()` and `init(options:using modelContext:) async throws`; `InsertCommand` builds the model, inserts it, skips `save()` under `--dry-run`, and prints `Inserted <describe()>`.
`Sources/Utilities.swift` holds `EmptyOptions`, the `hex(_:)' helper over `some BinaryInteger`, the `InsertError` enum (`unknownBinary` / `unknownSegment` / `unknownSymbol` / `duplicate`) and `requireBinary(named:in:)`, which resolves the program an insert was told to operate on.
`Sources/AetherKit+.swift` exists only to add `@retroactive ExpressibleByArgument` for `AnnotationKind`, `SymbolKind`, `SymbolType`, `SymbolBinding`, `BinaryFormat`, `Endianness` and `Architecture`; without it none of those enums parse as a CLI value.
`AetherOptions` (`Sources/Aether.swift`) carries a required positional `<project>` plus a bare `@Flag --dry-run`; `import`, `delete`, `insert` and `procedure detect` all guard `save()`.
The project URL is opened by a lazy `try! ModelContainer`, which creates the `.aetherproj` directory (and missing parents) when it does not exist — the behaviour `new` used to perform by hand.
The schema just changed under the CLI: `BinaryFormat`, `Endianness` and `Architecture` are now `Int`-backed enums, and `SymbolKind` / `SymbolType` / `SymbolBinding` gained `CaseIterable, Sendable`.
Every `describe()` is one `key=value` line — greppable, and exactly the shape entry 7 wants to JSON-ify:
- `program`: `thin_test machO arm64 little 64-bit 51480 bytes base=100000000 entry=1000006E8 stack=0 file=<path> segments=5 sections=11 symbols=42 procedures=14 references=0 annotations=0 bookmarks=0` — the three header enums print as case names, not numbers.
- `segment`: `MYSEG @1000FE000 size=4096 file=0+1000 prot=rw- maxprot=7 initprot=3 sections=1 program=thin_test`.
- `section`: `MYSEG,MYSEC @1000FE000 size=32 offset=A align=4 flags=1 executable=false zerofill=true code=false segment=MYSEG program=thin_test`.
- `symbol`: `my_sym @100001634 size=1 kind=function type=u64 binding=global import=false export=false identifier=my_sym value= program=thin_test`.
- `procedure`: `name @addr size= frame= thunk= leaf= demangled= blocks= callers= callees=` plus inline `arguments=[name: type reg|sp+n]` and `locals=[name: type sp+n:size]`.
- `annotation`: `entry point @1000006E8 kind=trailing program=thin_test`; `bookmark`: `main @1000006E8 created=2026-11-03 20:59:55 +0000 summary=program entry program=thin_test`.
Hex is upper-case through one `hex(_:) helper`; `persistentModelID` is deliberately not printed in any `describe()`, but `import` still ends with `Successfully imported as PersistentIdentifier(…)`.
Every group now sorts: children by address (`procedure` by `symbol.address`), `program` by name.
`fetch` pages with `--limit` / `--offset` and prints `Showing N (lo-hi) of M plural:`, where `M` is a second `fetchCount` taken before the page is applied; `count` has no page options at all, so it is always the whole census.
`import` takes `--no-analyze` (skip the procedure-detection pass) and `--quiet` (drop the loader's narration). The library side moved with it: `MachOLoader.machO(for:analyze:)` and `load(_:analyze:)` return `MachOLoadReport(log:procedures:)` instead of printing, so only the CLI decides what reaches stdout; the app's `try await MachOLoader.load(binary)` call site discards the report and compiles unchanged.
Helpers still `public` and directly reusable: `BinaryModel.read(at:count:)`, `readString(at:)`, `data(in:)`, `format(hex:)`, `section(containing:)`, `SegmentModel.protectionString`, `SectionModel.{isExecutable,isZeroFill,containsCode}`, `SymbolModel.isStringPredicate`, `SymbolModel.displayName`.

### Filters on the wire today

`program`: `--name` (contains), `--format`, `--architecture`, `--endian`.
`segment`: `--binary`, `--name`, `--address`, `--protection` (exact `initProtection`).
`section`: `--binary`, `--segment`, `--name`, `--address`, `--flags` (exact).
`symbol`: `--binary`, `--name`, `--address`, `--kind`, `--type`, `--binding`, `--value` (contains over `stringValue`), `@Flag --imported`, `@Flag --exported`.
`procedure`: `--name` and `--address` through the `symbol` relationship, `--binary`, `@Flag --thunk`, `@Flag --leaf`.
`annotation`: `--text`, `--binary`, `--address`, `--kind`; `bookmark`: `--binary`, `--name`, `--address`, `--summary`.
`--binary` is the answer to the old cross-program scoping request, on all six child groups; it is optional everywhere, so a document holding several programs answers with rows from all of them and nothing errors.
Inserts take the same vocabulary positionally: `symbol insert <binary> <name> <address>`, `section insert <binary> <segment> <name> <address>`, `procedure insert <binary> <symbol>`, `annotation insert <binary> <address> <text>`, `bookmark insert <binary> <name> <address>`, `segment insert <binary> <name> <address>`.
`procedure insert` resolves its symbol by name **or** identifier, and `section insert` / `segment insert` resolve their parent before writing, so a typo exits with `unknownSegment` / `unknownSymbol` / `unknownBinary` instead of attaching a row to the wrong parent.
Duplicate guards exist only where the schema has a `#Unique` key: `segment` [`binary`,`address`], `section` [`binary`,`address`], `symbol` [`binary`,`address`,`identifier`], `procedure` [`symbol`].
`annotation insert` and `bookmark insert` have no guard, because neither model declares a unique key, so re-inserting the same row duplicates it.
`program` has no `insert` deliberately: `import` is the only creator of `BinaryModel` rows.

### Gotchas verified at runtime

The one working SwiftData filter shape unwraps the optional **outside** the predicate: `let text = options.text.flatMap { filter in #Predicate<AnnotationModel> { $0.text.localizedStandardContains(filter) } } ?? .true`, and the parts are then composed with `descriptor.predicate = #Predicate<M> { a.evaluate($0) && b.evaluate($0) }`.
The tempting variant that keeps the `flatMap` inside the macro compiles and then aborts the process — `CoreData: error: … can't use NULL on left hand side`, `*** Terminating app due to uncaught exception 'NSInvalidArgumentException'`, `Abort trap: 6` — for every `fetch`, `count` and `delete` in every group.
`&` is rejected by the macro (`The '&' operator is not supported in this predicate`), so `--flags` and `--protection` are exact-equality filters and no bitmask filter is expressible at all.
Only stored fields may appear in a predicate: `SymbolModel.kind` / `.type` / `.binding` are computed over `rawKind` / `rawType` / `rawBinding`, which is what the filters compare, and `SectionModel.isExecutable` / `isZeroFill` / `containsCode` are computed too — which is why those three print but cannot be filtered.
Relationship keypaths do translate: `$0.binary.name`, `$0.segment.name`, `$0.symbol.name`, `$0.symbol.address`, and `SortDescriptor(\ProcedureModel.symbol.address)` works.
Numeric arguments are decimal-only while `describe()` prints upper-case hex: `--address 4296007680` selects the row printed as `@1000FE000`.
Int-raw enums take their numeric raw value as a CLI argument, so `--format 1` selects Mach-O, `--architecture 3` selects ARM64 and `--endian 0` selects little; the help strings spell the numbering out because the raw-name spelling is rejected.
Under `--dry-run` the mutating commands still print `Inserted …` and `Deleted N <plural>` while persisting nothing, which matches how `import` and `procedure detect` already behaved; the tense of those messages is the papergun, not the behaviour.
Because `count` and `delete` share the filter group, an unfiltered `symbol delete D` wipes every symbol row in the document, and `program delete` cascades to segments, sections, symbols, procedures, annotations and bookmarks while printing only the program count.
A document written by the pre-conversion build no longer opens at all: `addPersistentStoreWithType:… returned error NSCocoaErrorDomain (134140)` with `reason=Can't find or automatically infer mapping model for migration` and `entity=BinaryModel, property=endian.endian, reason=Source and destination attribute types are incompatible`, then `Trace/BPT trap: 5` (exit 133) out of `try! ModelContainer` in `AetherOptions.modelContainer`.
That trap is entry 12's complaint reproduced with a cause, and it means the scratch corpus of older `.aetherproj` stores is dead to the current build rather than merely stale.

### Still open after these changes

`inspect` / `bytes` / `find` (1, 3, 4), `--explain` (5), `--json` and any field selector (7), `symbol --min-length` / `--section` / `--raw` (8), `--demangle` (11), store validation (12, 17), `disassemble` (13), `import --replace` and the pre-delete census (15), `analyze --pass` / `--list-passes` (16), `doctor` (17), README regeneration (20), `addr` (21), `snapshot` / `changes` (22), the default fetch page cap (23), `graph` (24), `hash` (25), `decompile` (26), `grep` / `index` (27).
Entry 20 is no longer a nice-to-have: the README documents a command tree that does not exist, now including six `insert` subcommands it has never heard of.

## Tier 1 — cheap, high value

### 1. `aether inspect <binary>` — parse a Mach-O without a document

**Evidence.** Every probe in the scratch set re-derives the layout from a raw path instead of using the CLI: `.qwen/tmp/prologue_scan.swift`, `.qwen/tmp/symtab_probe.swift`, `.qwen/tmp/sectdump.swift`, `.qwen/tmp/symdump.swift`, `.qwen/tmp/nlist_hist.swift`, `/private/tmp/prologues.py`.
The shape is not hypothetical: the Homebrew tool `borer` (0.2.12) on this machine takes a raw path on every command — `borer info <binary>` is "summary: format, arch, sections, symbols", with no document and no project anywhere in its CLI.
**Status.** Still open, and slightly harder than when written.
`.qwen/tmp/proctest.swift` already demonstrates the target shape: build a `BinaryModel`, wrap it in `ModelContainer(Schema.project)`, call `MachOLoader.machO(for:)`, and print segment/section/symbol/procedure counts.
**Feature.** Parse in memory — no project, no store on disk — and print header fields, format/endian/architecture, `entryPoint`, `baseAddress`, segments with protection, sections with flags/offset/size, and symbol-table counts by kind.
The README pitch (inspect a document on a machine that cannot run the app) extends naturally to inspect a binary on any machine.
**Cost.** Low but now ordered: `machO(for:)` is `static`, `nonisolated`, `throws` and takes a detached `BinaryModel`, yet it also prints (`Load/MachOLoader.swift:161`, `:178`) and runs detection (`:174`), so a read-only `inspect` wants entry 19's `--quiet` / `--no-analyze` first.

### 3. `aether bytes` — read file bytes at a virtual address

**Evidence.** `.qwen/tmp/around.swift` dumps 16-byte rows around an address by hand because the CLI cannot; `strings_mirror.swift` and `symtab_probe.swift` hand-roll `u32`/`cstr` readers for the same reason. The app-side hex view is not reachable from a terminal.
**Status.** Still open.
**Feature.** `aether bytes --address <n> --length <n> [--binary <name>]` using `BinaryModel.read(at:count:)` + `format(hex:)`; `--string` to call `readString(at:)`; label the containing section via `section(containing:)`.
Reject addresses below `baseAddress` explicitly — `read(at:)` returns `nil` there, so say so instead of printing nothing.
**Cost.** Trivial; `read(at:count:)`, `readString(at:maxLength:)`, `format(hex:)`, `data(in:)` and `section(containing:)` are all public in `Schema+.swift`.
Scoping is already solved for it: `--binary` exists on every child group, so `bytes` just copies that option.
One thing to note: the `Span` plumbing is already public in `Schema+.swift` — `bytes(at:)` (`:37`), `span(at:)` (`:42`), `bytes(in:)` (`:49`), `span(in:)` (`:57`) — and `format(hex:)` (`:80`) now formats through `span(in:)` rather than `Data`. What is still missing is a byte formatter over a `Span<UInt8>`: the old `BinaryModel.hex(bytes:)` is gone, so the hex view has to be written.
**Flag naming.** borer splits this into two commands with caps printed in the help: `hexdump <binary> <address|name> [length]` — "bytes at a virtual address or name, or at `off:<n>` in the file (default 64, max 4096)" — and `read <binary> <address|name> [kind] [count]` — "typed values (`u8`..`u64`, `f32`, `f64`, `ptr`, `cstr`, `wstr`; default 1, max 256); `off:<n>` reads by file offset". So the spellings to copy are an `--as u64|f32|cstr` and an `off:` argument prefix, and Aether already has the typed half: `load<T: BitwiseCopyable>(_:at:)` (`Schema+.swift:23`), `ascii(at:maxLength:)` (`:28`) and `unicode(at:)` (`:32`) are public. Only the hex row formatter is new work.

### 4. `aether find` — byte patterns and references to an address

**Evidence.** `.qwen/tmp/hunt.swift` searches the symtab region for the little-endian encoding of a target address to find who points at it; `layout.swift` sweeps the nlist region for plausible address u64s.
`CrossReferenceModel` exists in the schema (`fromAddress`, `toAddress`, `type: XRefType`) but no CLI command ever reads or writes it.
**Status.** Still open, and the scope call is now explicit: `CrossReferenceModel` (and `BlockModel`) were left out of the command tree, so their stored properties are still `internal` in `Schema.swift` and invisible to `aether-cli`.
Re-checked for entry 24's cost, and the two models differ: all four of `CrossReferenceModel`'s stored properties are internal, while `BlockModel.startAddress` / `endAddress` / `type` / `successors` / `predecessors` are already `public` — what is internal there is only `BlockModel.procedure`, its `init` and `size`.
**Feature.** `--bytes <hex>` / `--text <s>` over `BinaryModel.data`, reporting file offsets **and** virtual addresses (offset + `baseAddress`); `--pointer-to <n>` for candidate references — the primitive xref pass; `--xref <n>` to dump stored `CrossReferenceModel` rows.
**Cost.** Medium. Scanning is trivial, but reading stored xrefs needs the AetherKit visibility change that was deliberately skipped; porting the analyzer that populates xrefs is a separate project.
**Pattern syntax and two extra directions.** `search <binary> <pattern> [text] [offset]` in borer takes "AOB hex with `??` wildcards, or a substring; 500 a page", so `--bytes DE??00` should be expressible rather than exact-equality only — and `??` is also the *output* format of `sig <binary> <address|name>`, "the shortest byte signature matching the code once, its moving bytes wildcarded: pattern, code and mask", which is how a library-function pattern set would be handed to `--bytes`.
On the reference side, `findstr <binary> <filter>` ("functions referencing a matching string") is `--pointer-to` pointed at a string row, and `fieldrefs <binary> <offset> [filter]` ("every instruction touching `[reg+offset]`") is the same xref one level deeper, over offsets rather than absolute addresses.

### 5. `aether procedure detect --explain` — per-pattern census

**Evidence.** `mask_check.py`, `census2.py`…`census9.py` and `sectlist.py` exist purely to measure each detector pattern on its own: per-pattern match counts, true/false positives against objdump labels, per-section hit counts, and imm7/imm9/imm12 extraction sanity (mismatches: 0 of N).
**Status.** `--explain` is still absent, and the reason it is still hard is now measurable: `ProcedureDetectionReport` exposes only the four aggregates (`codeSections`, `entryPoints`, `synthesized`, `created` — `Analysis/ProcedureDetector.swift:22-31`), and `note(_:stackSize:isStub:)` (`:108`) is never told which pattern fired, so a regression in one pattern stays invisible.
**Feature.** Per-pattern counts keyed by the detector's own names (`framePair`, `linkStore`, `stackAdjust`, `bti`, `pacibsp`, `stubThunk`), a per-section breakdown under `--explain`, and `--pattern <name>` to run one pattern.
The scratch scripts' symmetric-diff and mismatches-0 assertions belong in `AetherKit/Tests/AetherTests/ProcedureDetectorTests.swift`, not `.qwen/tmp`.
**Cost.** Medium — thread a per-pattern counter through `note(_:stackSize:isStub:)` and widen the report struct; no schema change.
**Naming to borrow.** borer's `why <binary> <address|name>` — "what is at an address, and where each fact came from" — is the per-address half of `--explain`: the census answers how often each pattern fired, `why` answers which pattern made *this* row. `procedure detect --explain --address <n>` is the same question and is the half a regression test needs.

### 7. `--json` / machine-readable output on fetch, count and the reports

**Evidence.** `/private/tmp/aether_procs.json` — one row per procedure keyed by the store's own columns (`ZNAME`, `ZADDRESS`, `ZSTACKSIZE`, `ZSIZE`) — plus `aether_procs.txt` and `objdump_labels.txt` address lists: the detector work was validated with `sqlite3 -json` because the tool has no structured output.
**Status.** Still open, and more urgent now: the `key=value` shape every `describe()` uses just moved the problem. Values are unquoted and unescaped, so a `stringValue` containing a newline breaks the one-row-per-line invariant in the middle of a field — `str_100000620 @100000620 size=4 kind=data type=ascii binding=local … value=%ld` then a stray ` program=probe_bin` on the next line.
Single values are still not machine-extractable: `aether program fetch --entrypoint --bare` cannot work without a field selector, and `import` still ends with `Successfully imported as \(binary.persistentModelID).` — the repr the row view stopped printing is printed by the command that creates the row.
**Feature.** `--json` with stable lower-case keys (never `Z*` columns, never a `PersistentIdentifier(…)` repr) on every `fetch`/`count` and on the `import` / `insert` / `procedure detect` reports.
`describe()` needs a structured sibling, e.g. `fields() -> [(String, String)]`, or a per-model `Codable` view; until then, escaping (`\n` inside quoted values) is the minimum for anything a script reads.
**Cost.** Low-medium; touches the `FetchableModel` protocol and each `describe()`.
Two consumers show what the shape buys. borer prints `borer tools` "as JSON", and `borer names <binary> <ida|ghidra|binja|x64dbg> [out]` emits "borer's names and comments as an IDAPython, Ghidra or Binary Ninja script or an x64dbg database" — egress formats are the cheap half of a structured row, and `aether` has no path at all for getting stored `AnnotationModel` / `BookmarkModel` text out of a document.

### 8. `symbol` parity with the scanner and `strings(1)`

**Evidence.** `.qwen/tmp/strings_mirror.swift` re-implements the string scan by hand — region preference `__cstring` else the whole `__TEXT` segment, printable `0x20…0x7E`, `minLen = 4`, `vaddr = region.addr + offset` — and `strings_scan_check.swift` diffs those hits against BSD `strings(1)` output by value and file offset. That drift check is what `--raw` is supposed to make native.
**Feature.** Three filters still missing: `--min-length <n>` over `size`, `--section <name>` (sections have their own group, symbols do not scope to one), and `--raw`, which re-scans `BinaryModel.data` with the current rules and reports the stored-rows-vs-fresh-scan drift a scripted user wants after an app edit.
`--raw` has to re-point at the current scanner: the ASCII pass the mirror script copies is gone. The live path is `MachOLoader.symbolize(in:)` (`Load/MachOLoader.swift:347`, declared in a `public nonisolated extension`, so `aether-cli` can already call it), which types each row from the section's Mach-O flags — `S_CSTRING_LITERALS` → `.ascii` (min 4 bytes) / `.utf16` (min 2 chars), pointer sections → `.ptr` per 8 bytes, `S_4BYTE_LITERALS` / `S_INIT_FUNC_OFFSETS` → `.u32`, `S_8BYTE_LITERALS` → `.u64`, `S_16BYTE_LITERALS` → `.u128`, everything else one `.unknown` row; rows overlapping a named symbol are skipped.
`scanStrings` survives only as a doc-comment mention at line 325, so `--raw` means diffing `symbolize(in:)` output against the stored rows — and on a fresh `thin_test` import the store holds 42 symbol rows from a run that narrates 33, i.e. 16 rows beyond the 26 symtab entries.
**Flag naming.** borer keeps the filter on the scan itself: `strings <binary> [filter] [offset] [limit]` — "printable strings (100 a page, max 500)". So `--min-length` belongs to `--raw`'s fresh scan as much as to the stored rows, otherwise the two halves of the drift report are filtered differently.
**Caveat.** `SymbolModel.isStringPredicate` (`Schema+.swift:193`) is public and still unexposed, which is precisely the filter `--min-length` wants to combine with.
`#Unique<SymbolModel>([\.binary, \.address, \.identifier])` keys on `identifier`, not `name`; `name` only tracks `identifier` after `refresh()` runs, so `symbol insert` defaults `--identifier` to the name and the guard compares the resolved identifier.

### 21. `aether addr` — one place in every notation

**Evidence.** borer has a dedicated command for this: `addr <binary> <va|rva:<n>|off:<n>>` — "one place as virtual address, relative address, file offset, section and function" — and every address-taking command (`hexdump`, `read`, `disasm`, `xrefs`, `why`) accepts `<address|name>`, so a symbol name, `0x`-hex and decimal are the same argument.
Aether's gotchas section records the cost of not having it: `--address 4296007680` is what selects the row printed `@1000FE000`, and no command says which section or function that address falls in.
**Feature.** `aether addr <binary> <va | off:<n> | 0x… | name>` printing one line: virtual address, file offset, containing segment and section, owning symbol and procedure. Then accept `<address|name>` everywhere an address is taken — `symbol fetch --address`, `annotation insert`, `procedure fetch --address`, entry 3's `bytes`, entry 13's `disassemble` — and accept `0x` and the `@…` spelling `describe()` prints, which retires the decimal-only papergun instead of documenting it again.
**Cost.** Low. Parsing sits in `aether-cli/Sources/Utilities.swift` beside the `hex(_:)` helper; the conversions are already public in `Schema+.swift` — `section(containing:)` (`:88`), `segment(containing:)` (`:93`), `ProcedureModel.contains(address:)` (`:203`) — and name→address is a `requireBinary(named:in:)`-shaped single-row fetch over `SymbolModel.name` / `identifier`.
No predicate is involved, so none of the `#Predicate` constraints apply: this is argument resolution, not a filter.

### 22. `aether snapshot` / `aether changes` — pin the counts a detector run owes

**Evidence.** borer carries three tools for the same idea: `snapshot <binary> <out>` writes "the program's commands, packet layouts, attributes, message routes and ids by stable name to a file"; `changes <binary> <snapshot>` reports "what changed since a snapshot: commands, layouts, attributes, routes and ids added, removed or changed"; and `anchors <binary> <manifest>` re-derives "every pinned fact in a manifest (field, vconst, function, encode, decode lines)" and reports "held, moved, changed or gone; fails unless all held".
`fingerprint <binary> [out]` writes a sidecar `diff <binary> <other>` reads, so two builds are compared without re-parsing both into two documents.
This is the missing harness for this repo's own evidence: entry 16's drift (15795/5981 → 10712/7547 → 10712/7546 → 14881/11716 for one identical input) and entry 5's per-pattern census are both things a pinned manifest would have caught.
**Feature.** `aether snapshot --project D --out <file>` writing stable-name rows (section names + flags, symbol `identifier` + address, procedure name + address + `stackSize`); `aether changes --project D <file>` diffing a store against it with `added / removed / moved / renamed` and a non-zero exit on any change under `--fail-changed`.
`moved` matters: procedure identity is `symbol`, and `#Unique<ProcedureModel>([\.symbol])` means renumbering an address is a remove+add unless the diff matches on name.
**Cost.** Low-medium, and it stands on entry 7 rather than on new queries: the row shape it needs is `describe()`'s structured sibling `fields()`, and the fetches are the ones `aether-cli/Sources/Fetch<T>.swift` already builds.
What has to widen is `ProcedureDetectionReport` (`AetherKit/Sources/AetherKit/Analysis/ProcedureDetector.swift:22-31`) so a snapshot records which pass produced the rows — the same pass identity entry 16 wants. No schema change; no predicate (the diff walks whole tables, which sidesteps the stored-fields-only rule).

## Tier 2 — cheap, smaller payoff

### 11. `--demangle`

**Evidence.** `SymbolModel.displayName` calls `demangleSwift` / `demangleCPP`, both stubs that `return nil`. The names in `/private/tmp/aether_procs.json` (`__ZN63_\$LT\$reqwest…`, `__ZN11miniz_oxide…`) are unreadable in a terminal. On this machine `/usr/bin/c++filt` exists and `swift demangle --help` works, so a subprocess demangler is cheap.
**Status.** `procedure fetch` prints `demangled=` empty for every row of the rustc documents, while the stored `demangled` column stays blank.
**Feature.** `--demangle` calling `swift demangle` / `c++filt` with a raw-name fallback; `--set-demangled` on an existing row is the only write side still open.

### 12. Project opening errors / `aether doctor`

**Evidence.** The README documents the quirk: a nonexistent project silently created an empty store and reported `Showing 0 models:` with exit 0. Fixtures `.qwen/tmp/nope.aetherproj` and `.qwen/tmp/clidocs/ErrDoc.aetherproj` exist to exercise error paths.
**Status.** The "silently creates" half is now the design, not a quirk: `<project>` is a required positional argument and the model container creates the `.aetherproj` directory (missing parents included) on demand, which is why `new` was deleted. `Showing 0 … of 0` with exit 0 is still what a typo'd path prints.
**Feature.** Keep the create-on-demand default, add `--existing` (or an equivalent guard) for scripts that must not silently branch on a typo; replace `try!` in `AetherOptions.modelContainer` with a thrown error so the CLI exits non-zero, and add `aether doctor <project>`: store path, per-model row counts, `format`/`endian`/`architecture`, and whether every `SymbolModel` lies inside a section.

### 23. `aether fetch` — cap the default page

**Evidence.** Every borer list command prints its page and its cap: `functions <binary> [filter] [offset] [limit]` "(100 a page, max 300)", `symbols` "(50 a page, max 1000)", `strings` "(100 a page, max 500)", `grep` "(100 a page, max 500)", `map` "(max 5000)", and the server answers `# showing N of M` so a page never reads as the whole answer.
**Status.** The totals half landed: `fetch` prints `Showing N (lo-hi) of M plural:` from a `fetchCount` taken before the page is applied, and the `count` mirror decision was settled by removing the page options from `CountCommand` entirely — `aether procedure count` is always the whole census.
**Feature.** Still open: cap the page when `--limit` was omitted — `aether procedure fetch` on the rustc document currently writes 15795 lines into a terminal — with `--all` to opt out.
**Cost.** Low, and now only the default: `FetchOptions` in `aether-cli/Sources/Fetch<T>.swift` already carries `--limit`/`--offset` into `descriptor.fetchLimit` / `fetchOffset`; the remaining work is a default limit plus an `--all` that clears it.
No predicate is touched, so none of the `#Predicate` constraints apply.

### 24. `aether graph` — block CFG and callgraph per procedure

**Evidence.** borer prints both as one-shot text: `cfg <binary> <address|name>` — "function control-flow graph (mermaid)" — and `callgraph <binary> <address|name> [callers|callees]` — "callgraph (mermaid, max 30); `callers` walks what reaches it".
`procedure describe()` already advertises the data with `blocks= callers= callees=`, which print empty for every row today: the rows exist in the store and the CLI has no way to show them.
**Feature.** `aether graph <procedure|address> --format mermaid|dot [--callers <n>]` over a procedure's blocks and its call edges, and `--list-blocks` for plain rows (`startAddress`, `endAddress`, `type`), so the same output feeds `dot`/`mermaid-cli` instead of the app's canvas.
**Cost.** Medium, and cheaper than entry 4's xrefs: `BlockModel.startAddress` / `endAddress` / `type` / `successors` / `predecessors` are already `public` in `Schema.swift`, and the walk starts at `ProcedureModel.blocks` (public, `deleteRule: .cascade`), so nothing has to be added to `Array<any PersistentModel.Type>.project` (`Schema.swift:4`) — no migration, which is what entry 12/17 keep tripping over.
Two real gaps. `BlockModel.procedure` / `init` are internal, so block rows must be reached through their procedure rather than fetched; and `ControlFlowStructurer` is internal throughout (`nonisolated final class` at `Analysis/ControlFlowStructurer.swift:19`, `func structure(procedure:instructions:)` at `:153`, `struct CFGBlock` at `:8`), so this command can print the stored CFG but not the recovered if/while/switch shape until that visibility changes.
`BasicBlockType` is `String`-backed (`Schema/Arch.swift:149`: entry/normal/exit/conditional/loop), so `--type Loop` needs another `@retroactive ExpressibleByArgument` in `aether-cli/Sources/AetherKit+.swift` — and unlike the `Int`-backed enums it will parse by raw name, not by number.
Filtering blocks by type is a post-query decision, not a predicate: `BlockModel` is not a fetchable group, and `type` is a stored field only on a model no descriptor is built for.

### 25. `aether hash` — digests that collapse the scratch corpus to one column

**Evidence.** borer's `hashes <binary>` prints "md5, sha256, imphash, authentihash and tlsh: what malware feeds are searched by", and `fingerprint <binary> [out]` writes "function fingerprints; with out, write the sidecar `borer://diff` reads" — identity by digest rather than by re-parse.
Entry 15's evidence is exactly this problem: 15 stores, 13 of them real, over just 6 distinct binaries, discovered by reading the file names.
**Feature.** `aether hash [--binary <name>]` printing md5 + sha256 over `BinaryModel.data`, a header-stripped digest (bytes of the sections only, so a rebuild that moves only the header still matches), and a section-set digest; `program describe()` grows `sha256=` so `program fetch` across stores becomes a dedupe list.
**Cost.** The hashing itself is a `BinaryModel` helper in `AetherKit/Sources/AetherKit/Schema/Schema+.swift` over `data` / `span(in:)` — cheap.
The caution is what the package does *not* have: AetherKit's `Analysis/EntropyAnalyzer.swift`, `IoCExtractor.swift` and `PackerDetector.swift` declare public result structs (`EntropyResult`, `SectionEntropy`, `EntropyBlock`, `IoCReport`, `PackerResult`) and no computation at all, so there is no analyzer to call and no existing digest to reuse; `ProcedureDetector` is the only AetherKit analysis with real code.
Report through entry 7's `fields()`. No predicate involved — the digests are computed values, which is precisely the kind of thing `#Predicate` cannot express, so a `--same-as <digest>` filter across documents has to be a scan in `aether-cli`, not a filter.

## Tier 3 — real work, keep separate

### 13. `aether disassemble` — no command, no packaging blocker

**Evidence.** The disassembly ground truth the detector work was measured against is external: `/private/tmp/probe_dis.txt` and `.qwen/tmp/rustc_dis.txt` (68 MB) are `objdump -d` output; `/private/tmp/objdump_labels.txt` is its label list. `aether --help` still lists no `disassemble` command — only the seven model groups, `new` and `import`.
**Cost.** No longer a packaging decision: `AetherKit/Package.swift:16` now pulls `github.com/Lancelotbronner/capstone` (branch `next`) and links `CapstoneKit` into the AetherKit target, and the engine itself has already moved into the package — `AetherKit/Sources/AetherKit/Disassembler/DisassemblerEngine.swift:65` is a `public actor` exposing `disassemble(data:address:architecture:) -> DisassemblyResult` (`:71`), reachable from `aether-cli` with no new dependency. What remains is the command surface: choose a region (a section, a symbol range, or `--address` + `--length`) and print `DisassemblyResult.instructions` / `.pcode`.
**Caveat.** The engine builds its per-architecture disassembler with `try!` (`DisassemblerEngine.swift:78`), so an unmapped `Architecture` traps instead of throwing — a CLI command has to pre-check `architecture.capstoneArch`.
**Region and cap to copy.** borer's `disasm <binary> <address|name> [count]` counts instructions, not bytes — "(default 32, max 256)" — and `disasmfn <binary> <address|name>` walks "a whole function, block by block". So the region selector wants `--count` plus a procedure-name form (entry 21's `<address|name>`), and the cap belongs in the printed output, not only the help.

### 26. `aether decompile` — pseudo-C per procedure, `skeleton` first

**Evidence.** borer's whole pitch is a terminal: `decompile <binary> <address|name> [skeleton|full] [offset] [limit]` — "structured pseudo-C (skeleton: flow and calls only); 300 lines a page, a limit past the last line for all" — which is how a 15795-procedure binary is readable at all: `skeleton` costs one structuring pass per function and answers "what does this call and where does it go" without printing the body.
**Feature.** `aether decompile <procedure|address> [--skeleton] [--offset <n>] [--limit <n>]`, printing `Decompiler`'s text for one procedure; `--skeleton` = control flow plus call sites only, and paging consistent with entry 23 so a 3000-line function does not flood a script.
**Cost.** Lower than expected: the decompiler is already in the package — `AetherKit/Sources/AetherKit/Decompiler/Decompiler.swift:93` is `public func decompile(procedure: ProcedureModel, instructions: ArraySlice<DisassembledInstruction>, binary: BinaryModel) -> String` on a `public nonisolated final class Decompiler`, reachable from `aether-cli` with no new dependency.
What is missing is feeding it: `DisassemblerEngine.disassemble(data:address:architecture:) -> DisassemblyResult` for the procedure's address range, sliced to `ArraySlice<DisassembledInstruction>`, and `ProcedureModel` rows — so entry 16's `analyze --pass` is the prerequisite for re-checking one function after an edit, and entry 13's `try!`-trap caveat applies verbatim.
Still Tier 3 on merit: nothing in this repo has measured `Decompiler`'s output on the rustc corpus, and it keeps its own `ControlFlowStructurer` privately, so a `--skeleton` flag means teaching `Decompiler` to stop after structuring rather than picking a cheaper path.

### 27. `aether grep` — render the program once, then search it

**Evidence.** borer pairs the two halves deliberately: `index <binary>` — "decompile every function once into the cache that grep reads" — then `grep <binary> <text> [filter] [offset] [limit]` — "pseudo-C lines containing the text program-wide, or matching it when written `re:<expression>` (`(?i)` inside ignores case); filter names the function (100 a page, max 500)". The cache is what makes the second question cheap.
The scratch set needed it: `objdump_labels.txt`, `aether_procs.txt` and the 68 MB `rustc_dis.txt` greps were the tool for finding which procedures reference a constant or a string.
**Feature.** `aether grep <text> [--procedure <name>] [--regex re:<expr>] [--lines <n>]` over every procedure's rendered disassembly / p-code, printing `<address> <procedure> <line>`; `aether index` as the pass that builds the cache, and `--procedure` as the filter borer's "filter names the function" implies.
**Cost.** High, and it is entry 13 + entry 26 first: rendering over all `ProcedureModel` rows means one `DisassemblerEngine` call per procedure, and that engine is an `actor`, so the pass is sequential — 15795 procedures on the rustc document.
`#Predicate` cannot express any of it: nothing in `Schema.swift` stores rendered text, computed properties may not appear in a predicate at all, and even the `--procedure` narrowing has to unwrap outside the macro the way the gotchas section documents.
A cache therefore means either a new stored column on `ProcedureModel` (a schema change, and with it the migration hazard entries 12/17 keep hitting) or an on-disk sidecar outside the store like borer's index — the second avoids the migration risk and is the reason not to reach for a model first.

## More gaps — measured against the scratch stores rather than the scripts

### 15. `import --replace` and the pre-delete cascade census

**Evidence.** Scratch documents sit over very few binaries: `probe`, `probe2`, `probe3`, `probe-proj` all wrap `/private/tmp/probe_bin`, and `rustc`, `rustc2`, `rustc3`, `rustc-clean`, `rustc-probe` all wrap `/usr/local/bin/rustc`. There are 15 stores in total, 13 of them real over just 6 distinct binaries, plus two error fixtures — one new document per detector iteration was the only way to re-parse.
Every child relationship on `BinaryModel` (`Schema.swift:36-54`) is `deleteRule: .cascade`.
**Feature.** `import --replace` to re-parse into an existing document — `Import.swift` always builds a fresh `BinaryModel` and inserts it, so there is no way to re-run a parse in place.
The census is also still missing: `DeleteCommand` counts what it removed after the fact, so `program delete` does not say which segments/sections/symbols/procedures/annotations/bookmarks the cascade drops — and with filters available that under-reporting now covers partial deletes too.

### 16. `aether analyze` — re-run a pass without re-parsing

**Evidence.** The detection pass is welded into the loader at `Load/MachOLoader.swift:174` (`let report = ProcedureDetector().detect(in: model)`) inside `machO(for:)`, so re-analysing a stored document once meant re-importing it; the five `rustc` documents are the fossil record of that, with counts drifting 15795/5981 → 10712/7547 → 10712/7546 → 14881/11716 for one identical input.
**Feature.** `--list-passes` and the general `analyze --pass <name>`: detection is the only pass reachable from the CLI and `machO(for:)` still calls it inline, so a second pass has no name to ask for.
The report still says nothing about the `SymbolModel` rows the passes insert — a fresh `thin_test` import lands 42 symbol rows from a run that narrates 33 — so the census a script sees depends on which passes have run. Pass-aware counts in every report is the fix.
**Caveat.** Re-running is safe: `ProcedureDetector.detect` is append-only and `ProcedureModel` carries `#Unique<ProcedureModel>([\.symbol])` (`Schema.swift:190`).
**Naming and a report shape to copy.** borer's `index <binary>` ("decompile every function once into the cache that grep reads") is exactly what `--pass <name>` needs: a named, re-runnable, idempotent pass with a sidecar artefact rather than a loader side effect.
Its `triage <binary>` — "one call: what it is, what it hides, where to read" — is the aggregate every pass should leave behind: one block naming the format, the protection facts, the counts by model and the addresses worth reading first, so entry 1's `inspect` and entry 16's `analyze` print the same report.

### 17. `aether doctor` — prove a store matches what import claimed

**Evidence.** Re-importing the same `.qwen/tmp/thin_test` with the local build prints `Parsed 5 segments, 11 sections, 33 symbols (7 generated)` and `Detected 14 procedures`; the store then holds 1/5/11/42/14 rows.
The older `clidocs/ThinTest.aetherproj` holds 26 symbols with `ZRAWTYPE` = 0 on every row (all `SymbolType.unknown`) and 0 procedures, so `count` prints a clean `0` for a document that predates typed symbolization and detection.
**Status.** Still open, and the migration hazard is now worse than stale rows: any store written before `BinaryFormat` / `Endianness` / `Architecture` became `Int`-backed refuses to open (`NSCocoaErrorDomain (134140)`, `entity=BinaryModel, property=endian.endian, reason=Source and destination attribute types are incompatible`) and the CLI traps out of `try!` with exit 133.
The byte-count worry from the earlier draft is resolved: `program fetch` prints `51480 bytes` for the 51480-byte `.qwen/tmp/thin_test`, while `length(ZDATA)` on the `@Attribute(.externalStorage)` column reports 51481 — so `doctor` must compare `data.count` against `fileURL`, never the SQLite blob.
**Feature.** `aether doctor --project`: store URL, per-model row counts, `rawKind`/`rawType` histograms, section/symbol containment, stored entry point. Cheap version: treat any CoreData migration warning as `schema: stale` and say so instead of reporting zeros that look like an empty binary. Add `--strict`, exiting non-zero when the store predates the current model list.
**Cost.** Low — the queries are the ones already documented in this file's sqlite snippets; the hard part is agreeing on the per-model row-count list.
**First line to add.** borer's `doctor [offline]` prints "the local setup, one line each: version and commit, toolchain, symbol cache and server (`offline` skips the server), index cache, `.mcp.json`" — it names the build before it diagnoses anything.
`aether` registers no `version` in `Sources/Aether.swift`'s `CommandConfiguration`, so `aether --version` does not exist and `doctor` cannot say which build wrote the store it is complaining about; that is precisely the schema-generation mismatch this entry documents, and the fix is a version stamp in the report (and, later, in the document itself) rather than a smarter query.

### 20. `aether-cli/README.md` is stale against the shipped command tree

**Status.** Worse than when written: now actively wrong, in places. The command table still advertises `aether string [fetch]` (line 45) and `aether string count` (line 46), which no longer exist; the intro (line 3) still says queries cover "programs, segments, sections, strings"; the `program [fetch]` row still says the row prints "name + persistent ID", which `describe()` no longer does; and there are no rows for `symbol`, `annotation`, `bookmark`, any `delete`, `procedure detect`, `--dry-run`, or the six `insert` subcommands.
The import transcript (lines 79-81) still shows `Parsing 26 symbols` / `Parsed 26 symbols in 1 ms` / `Parsed 5 segments, 11 sections, 35 symbols (9 generated)` with no `Detected N procedures` line, and the sample transcript around line 125 still runs the deleted `aether string` commands.
The sentence at line 33 is wrong too: the README says that in each model group `fetch` is the default subcommand, so `aether segment --project D` equals `aether segment fetch --project D` — no group sets `defaultSubcommand` any more, so a bare group invocation errors on `--project`.
Every filter and every enum-valued option is undocumented as well, including the numbering the options now require (`--format 1`, `--architecture 3`, `--kind 1`).
**Feature.** Not a code feature: regenerate the transcript from a real run (the staleness trap note at line 29 already warns that the installed binary lags the sources), add the `procedure` / `symbol` / `annotation` / `bookmark` / `insert` / `delete` rows and `--dry-run`, and re-check after any change to `describe()`.

---

## Not features — but they should stop living in `.qwen/tmp`

- Layout probes `.qwen/tmp/sizes.swift`, `maskcheck.swift`, `nlist_bc.swift`, `/private/tmp/nlist_check.c`: they assert SDK struct sizes and constants, a role now split between `AetherKit/Tests/CoreAetherTests/NListTypeTests.swift` and the detector comments. Pick one home.
- Assembled-instruction fixtures `.qwen/tmp/{br,sig,sig2,strimm,strimm2,strimm3,vectors,linkstore,offs,enc_probe}.s` (and their `.o`): the `clang -c` evidence behind every mask in `ProcedureDetector`. Their decoded values are already transcribed into the detector comments; the `mask_check.py` symmetric-diff assertions should become `AetherTests` cases.
- Corpus binaries `/private/tmp/probe_bin`, `probe_x86`, `probe_x86_stripped`, `.qwen/tmp/thin_test`: commit the sources (`.qwen/tmp/thin_test.swift`, `/private/tmp/probe.c`) as test fixtures; binaries do not belong in the repo.
- The 12 `/private/tmp/*.aetherproj` stores (`probe*`, `rustc*`, `x86*`, `py-proj`) are the working corpus behind entries 15-17: regenerate them with `aether import` from the committed sources rather than checking them in. They are worse than stale now — every one written before the `Int`-backed enum conversion refuses to open and traps (see the gotchas), so carry none of them over.
- `.qwen/tmp/underflow_check.swift`: documents a non-bug (Int arithmetic, no trap). Historical.
- `.qwen/tmp/clidocs/{ThinTest,ErrDoc}.aetherproj`, `/private/tmp/j2r*`, `/private/tmp/dumps`, `.qwen/tmp/s-*`, `__pycache__`: error fixtures or regenerable scratch.
