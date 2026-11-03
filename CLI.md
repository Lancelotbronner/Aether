# Aether CLI — feature backlog

Scratch space holds the analysis scripts used while fixing the Mach-O loader and writing `ProcedureDetector`.
Most are throwaway re-implementations of things the CLI should do natively: they take a raw binary path, hand-parse the header, and print what `aether` cannot print today.
Living list. Each entry names its scratch evidence, the proposed CLI surface, and the cost in AetherKit terms, plus a status line where the proposal has partially landed.
Implemented entries are deleted rather than left behind, so the numbering has permanent gaps; entry numbers never shift, which keeps cross-references such as "entry 19" valid across edits.

## Verified CLI surface today (HEAD `87ba326` plus uncommitted filters and inserts)

`aether --help` registers seven model groups — `program`, `section`, `segment`, `symbol`, `procedure`, `annotation`, `bookmark` — plus `new` and `import`.
Every group carries `fetch` / `count` / `delete`; every group except `program` also carries `insert`, and `procedure` additionally carries `detect`.
No group sets `defaultSubcommand`, so the subcommand has to be spelled out — `aether symbol --project D` reports `Unknown option --project`.
`Sources/Fetch<T>.swift` is the read-side machinery: a `FetchableModel` protocol with `plural`, `describe()`, an associated `FetchOptions` defaulting to `EmptyOptions` (`Sources/Utilities.swift`), `static var subcommands`, and `static func apply(_:to:)` to decorate the `FetchDescriptor` with a predicate and `sortBy`.
`CountCommand` and `DeleteCommand` take the same `Model.FetchOptions`, so every filter below is also a filter on `count` and on `delete`.
`Sources/Insert<T>.swift` is the write side: an `InsertableModel` protocol with `singular`, `describe()` and `init(options:using modelContext:) async throws`; `InsertCommand` builds the model, inserts it, skips `save()` under `--dry-run`, and prints `Inserted <describe()>`.
`Sources/Utilities.swift` holds `EmptyOptions`, the `hex(_:)' helper over `some BinaryInteger`, the `InsertError` enum (`unknownBinary` / `unknownSegment` / `unknownSymbol` / `duplicate`) and `requireBinary(named:in:)`, which resolves the program an insert was told to operate on.
`Sources/AetherKit+.swift` exists only to add `@retroactive ExpressibleByArgument` for `AnnotationKind`, `SymbolKind`, `SymbolType`, `SymbolBinding`, `BinaryFormat`, `Endianness` and `Architecture`; without it none of those enums parse as a CLI value.
`AetherOptions` (`Sources/Aether.swift`) carries `--project` plus a bare `@Flag --dry-run`; `import`, `delete`, `insert` and `procedure detect` all guard `save()`.
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
Because `count` and `delete` share the filter group, an unfiltered `symbol delete --project D` wipes every symbol row in the document, and `program delete` cascades to segments, sections, symbols, procedures, annotations and bookmarks while printing only the program count.
A document written by the pre-conversion build no longer opens at all: `addPersistentStoreWithType:… returned error NSCocoaErrorDomain (134140)` with `reason=Can't find or automatically infer mapping model for migration` and `entity=BinaryModel, property=endian.endian, reason=Source and destination attribute types are incompatible`, then `Trace/BPT trap: 5` (exit 133) out of `try! ModelContainer` in `AetherOptions.modelContainer`.
That trap is entry 12's complaint reproduced with a cause, and it means the scratch corpus of older `.aetherproj` stores is dead to the current build rather than merely stale.

### Still open after these changes

`inspect` / `bytes` / `find` (1, 3, 4), `--explain` (5), `--json` and any field selector (7), `symbol --min-length` / `--section` / `--raw` (8), `--demangle` (11), store validation (12, 17), `disassemble` (13), `import --replace` and the pre-delete census (15), `analyze --pass` / `--list-passes` (16), `doctor` (17), `import --no-analyze` / `--quiet` (19), README regeneration (20).
Entry 20 is no longer a nice-to-have: the README documents a command tree that does not exist, now including six `insert` subcommands it has never heard of.

## Tier 1 — cheap, high value

### 1. `aether inspect <binary>` — parse a Mach-O without a document

**Evidence.** Every probe in the scratch set re-derives the layout from a raw path instead of using the CLI: `.qwen/tmp/prologue_scan.swift`, `.qwen/tmp/symtab_probe.swift`, `.qwen/tmp/sectdump.swift`, `.qwen/tmp/symdump.swift`, `.qwen/tmp/nlist_hist.swift`, `/private/tmp/prologues.py`.
**Status.** Still open, and slightly harder than when written.
`.qwen/tmp/proctest.swift` already demonstrates the target shape: build a `BinaryModel`, wrap it in `ModelContainer(Schema.project)`, call `MachOLoader.machO(for:)`, and print segment/section/symbol/procedure counts.
**Feature.** Parse in memory — no `new`, no `--project`, no store on disk — and print header fields, format/endian/architecture, `entryPoint`, `baseAddress`, segments with protection, sections with flags/offset/size, and symbol-table counts by kind.
The README pitch (inspect a document on a machine that cannot run the app) extends naturally to inspect a binary on any machine.
**Cost.** Low but now ordered: `machO(for:)` is `static`, `nonisolated`, `throws` and takes a detached `BinaryModel`, yet it also prints (`Load/MachOLoader.swift:161`, `:178`) and runs detection (`:174`), so a read-only `inspect` wants entry 19's `--quiet` / `--no-analyze` first.

### 3. `aether bytes` — read file bytes at a virtual address

**Evidence.** `.qwen/tmp/around.swift` dumps 16-byte rows around an address by hand because the CLI cannot; `strings_mirror.swift` and `symtab_probe.swift` hand-roll `u32`/`cstr` readers for the same reason. The app-side hex view is not reachable from a terminal.
**Status.** Still open.
**Feature.** `aether bytes --address <n> --length <n> [--binary <name>]` using `BinaryModel.read(at:count:)` + `format(hex:)`; `--string` to call `readString(at:)`; label the containing section via `section(containing:)`.
Reject addresses below `baseAddress` explicitly — `read(at:)` returns `nil` there, so say so instead of printing nothing.
**Cost.** Trivial; `read(at:count:)`, `readString(at:maxLength:)`, `format(hex:)`, `data(in:)` and `section(containing:)` are all public in `Schema+.swift`.
Scoping is already solved for it: `--binary` exists on every child group, so `bytes` just copies that option.
One thing to note: `BinaryModel.hex(bytes:)` (the `Span<UInt8>` byte formatter) was deleted from that file, and `format(hex:)` takes a `Range<UInt64>` through `Data` — if the byte view wants a streaming formatter, that helper comes back.

### 4. `aether find` — byte patterns and references to an address

**Evidence.** `.qwen/tmp/hunt.swift` searches the symtab region for the little-endian encoding of a target address to find who points at it; `layout.swift` sweeps the nlist region for plausible address u64s.
`CrossReferenceModel` exists in the schema (`fromAddress`, `toAddress`, `type: XRefType`) but no CLI command ever reads or writes it.
**Status.** Still open, and the scope call is now explicit: `CrossReferenceModel` (and `BlockModel`) were left out of the command tree, so their stored properties are still `internal` in `Schema.swift` and invisible to `aether-cli`.
**Feature.** `--bytes <hex>` / `--text <s>` over `BinaryModel.data`, reporting file offsets **and** virtual addresses (offset + `baseAddress`); `--pointer-to <n>` for candidate references — the primitive xref pass; `--xref <n>` to dump stored `CrossReferenceModel` rows.
**Cost.** Medium. Scanning is trivial, but reading stored xrefs needs the AetherKit visibility change that was deliberately skipped; porting the analyzer that populates xrefs is a separate project.

### 5. `aether procedure detect --explain` — per-pattern census

**Evidence.** `mask_check.py`, `census2.py`…`census9.py` and `sectlist.py` exist purely to measure each detector pattern on its own: per-pattern match counts, true/false positives against objdump labels, per-section hit counts, and imm7/imm9/imm12 extraction sanity (mismatches: 0 of N).
**Status.** `detect` itself improved — it now runs over every binary in the document and prints `ProcedureDetectionReport.summary` plus the store total (`thin_test: ProcedureDetector: 2 code sections, 7 entry points, 1 synthesized symbols, 1 procedures, 14 total procedures`) — but the report still exposes only the four aggregates (`codeSections`, `entryPoints`, `synthesized`, `created`), so a regression in one pattern stays invisible.
**Feature.** Per-pattern counts keyed by the detector's own names (`framePair`, `linkStore`, `stackAdjust`, `bti`, `pacibsp`, `stubThunk`), a per-section breakdown under `--explain`, and `--pattern <name>` to run one pattern.
The scratch scripts' symmetric-diff and mismatches-0 assertions belong in `AetherKit/Tests/AetherTests/ProcedureDetectorTests.swift`, not `.qwen/tmp`.
**Cost.** Medium — thread a per-pattern counter through `note(_:stackSize:isStub:)` and widen the report struct; no schema change.

### 7. `--json` / machine-readable output on fetch, count and the reports

**Evidence.** `/private/tmp/aether_procs.json` — one row per procedure keyed by the store's own columns (`ZNAME`, `ZADDRESS`, `ZSTACKSIZE`, `ZSIZE`) — plus `aether_procs.txt` and `objdump_labels.txt` address lists: the detector work was validated with `sqlite3 -json` because the tool has no structured output.
**Status.** Still open, and more urgent now: the `key=value` shape every `describe()` uses just moved the problem. Values are unquoted and unescaped, so a `stringValue` containing a newline breaks the one-row-per-line invariant in the middle of a field — `str_100000620 @100000620 size=4 kind=data type=ascii binding=local … value=%ld` then a stray ` program=probe_bin` on the next line.
Single values are still not machine-extractable: `aether program fetch --entrypoint --bare` cannot work without a field selector, and `import` still ends with `Successfully imported as \(binary.persistentModelID).` — the repr the row view stopped printing is printed by the command that creates the row.
**Feature.** `--json` with stable lower-case keys (never `Z*` columns, never a `PersistentIdentifier(…)` repr) on every `fetch`/`count` and on the `import` / `insert` / `procedure detect` reports.
`describe()` needs a structured sibling, e.g. `fields() -> [(String, String)]`, or a per-model `Codable` view; until then, escaping (`\n` inside quoted values) is the minimum for anything a script reads.
**Cost.** Low-medium; touches the `FetchableModel` protocol and each `describe()`.

### 8. `symbol` parity with the scanner and `strings(1)`

**Evidence.** `.qwen/tmp/strings_mirror.swift` mirrors `MachOLoader.scanStrings(in:)` exactly — region preference `__cstring` else the whole `__TEXT` segment, printable `0x20…0x7E`, `minLen = 4`, `vaddr = region.addr + offset`; `strings_scan_check.swift` diffs those hits against BSD `strings(1)` output by value and file offset.
**Status.** Mostly shipped. The `string` group is gone and `symbol` carries the filters the scanner work wanted: `--value` is the substring filter over `stringValue`, and `--kind` / `--type` / `--binding` / `--imported` / `--exported` mean the nlist and binding histograms are now one `symbol count` each rather than `sqlite3` work.
**Still missing.** `--min-length <n>` over `size`, `--section <name>` (sections have their own group, symbols do not scope to one), and `--raw`.
**Feature.** `--raw` re-scans `BinaryModel.data` with the scanner rules; the stored-rows-vs-fresh-scan drift check is exactly what a scripted user wants after an app edit.
Re-point it at the current scanner: the ASCII pass the mirror script copies is gone. The live path is `MachOLoader.symbolize(in:)` (`Load/MachOLoader.swift:347`, declared in a `public nonisolated extension`, so `aether-cli` can already call it), which types each row from the section's Mach-O flags — `S_CSTRING_LITERALS` → `.ascii` (min 4 bytes) / `.utf16` (min 2 chars), pointer sections → `.ptr` per 8 bytes, `S_4BYTE_LITERALS` / `S_INIT_FUNC_OFFSETS` → `.u32`, `S_8BYTE_LITERALS` → `.u64`, `S_16BYTE_LITERALS` → `.u128`, everything else one `.unknown` row; rows overlapping a named symbol are skipped.
`scanStrings` survives only as a doc-comment mention at line 325, so `--raw` means diffing `symbolize(in:)` output against the stored rows — and on a fresh `thin_test` import the store holds 42 symbol rows from a run that narrates 33, i.e. 16 rows beyond the 26 symtab entries.
`SymbolModel.isStringPredicate` is public and still unexposed, which is precisely the filter `--min-length` wants to combine with.
**Caveat.** `#Unique<SymbolModel>([\.binary, \.address, \.identifier])` keys on `identifier`, not `name`; `name` only tracks `identifier` after `refresh()` runs, so `symbol insert` defaults `--identifier` to the name and the guard compares the resolved identifier.

## Tier 2 — cheap, smaller payoff

### 11. `--demangle`

**Evidence.** `SymbolModel.displayName` calls `demangleSwift` / `demangleCPP`, both stubs that `return nil`. The names in `/private/tmp/aether_procs.json` (`__ZN63_\$LT\$reqwest…`, `__ZN11miniz_oxide…`) are unreadable in a terminal. On this machine `/usr/bin/c++filt` exists and `swift demangle --help` works, so a subprocess demangler is cheap.
**Status.** Still open, and now measurably so: `procedure fetch` prints `demangled=` empty for every row of the rustc documents, while the stored `demangled` column stays blank.
The write half moved: `procedure insert --demangled <String>` stores the field for a new row, so `--set-demangled` on an existing row is the only write side still missing.
**Feature.** `--demangle` calling `swift demangle` / `c++filt` with a raw-name fallback.

### 12. `--project` validation / `aether doctor`

**Evidence.** The README documents the quirk: a nonexistent `--project` silently creates an empty store and reports `Showing 0 models:` with exit 0. Fixtures `.qwen/tmp/nope.aetherproj` and `.qwen/tmp/clidocs/ErrDoc.aetherproj` exist to exercise error paths.
**Status.** Still open, and now with a reproducible trigger: `modelContainer` is a lazy `try! ModelContainer(…)`, so opening a store whose columns disagree with the current schema prints the Core Data migration failure and traps (`Trace/BPT trap: 5`, exit 133) instead of exiting non-zero with a message.
**Feature.** Make a missing document an error (behind a flag if the default must stay), replace `try!` with a thrown error so the CLI exits non-zero, and add `aether doctor --project`: store path, per-model row counts, `format`/`endian`/`architecture`, and whether every `SymbolModel` lies inside a section.

## Tier 3 — real work, keep separate

### 13. `aether disassemble` — blocked on packaging, not on code

**Evidence.** The disassembly ground truth the detector work was measured against is external: `/private/tmp/probe_dis.txt` and `.qwen/tmp/rustc_dis.txt` (68 MB) are `objdump -d` output; `/private/tmp/objdump_labels.txt` is its label list. `aether` has no disassembly path at all.
**Status.** Unchanged.
**Cost.** The Capstone driver (`Aether/Core/Disassembler/DisassemblerEngine.swift`) lives in the app target, and `AetherKit/Package.swift` depends only on `Zip` — no `CapstoneKit`. Mirroring the engine into AetherKit means a new package dependency for the CLI: a packaging decision, not a CLI ticket.

## More gaps — measured against the scratch stores rather than the scripts

### 15. `import --replace` and the pre-delete cascade census

**Evidence.** Scratch documents sit over very few binaries: `probe`, `probe2`, `probe3`, `probe-proj` all wrap `/private/tmp/probe_bin`, and `rustc`, `rustc2`, `rustc3`, `rustc-clean`, `rustc-probe` all wrap `/usr/local/bin/rustc`. There are 15 stores in total, 13 of them real over just 6 distinct binaries, plus two error fixtures.
Every child relationship on `BinaryModel` (`Schema.swift:36-54`) is `deleteRule: .cascade`, so taking rows back out used to mean `rm -rf` of the store.
**Status.** Mostly shipped, in a way the entry did not anticipate: `delete` exists on all seven groups, is cascade-aware in the right way (it clears `propertiesToFetch` / `relationshipKeyPathsForPrefetching` before `modelContext.delete(model)`), honours `--dry-run`, reports `Deleted N <plural>`, and now takes the group's filters — so a scripted corpus can drop one section or one symbol instead of a whole program.
**Still missing.** `import --replace` to re-parse into an existing document, which is what made one new document per detector iteration necessary.
The census is also still missing: `delete` counts what it removed after the fact, so `program delete` does not say which segments/sections/symbols/procedures the cascade drops — and with filters available that under-reporting now covers partial deletes too.

### 16. `aether analyze` — re-run a pass without re-parsing

**Evidence.** The detection pass is welded into the loader at `Load/MachOLoader.swift:174` (`let report = ProcedureDetector().detect(in: model)`) inside `machO(for:)`, so re-analysing a stored document was impossible; the five `rustc` documents are the fossil record of that, with counts drifting 15795/5981 → 10712/7547 → 10712/7546 → 14881/11716 for one identical input.
Re-running is already safe: `ProcedureDetector.detect` is append-only and `ProcedureModel` carries `#Unique<ProcedureModel>([\.symbol])`.
**Status.** Half shipped. `procedure detect` is now a standalone pass over **every** `BinaryModel` in the document — no re-import needed — prints the report per binary, and respects `--dry-run`, so a pass can be measured before it lands.
**Still missing.** `--list-passes` and the general `analyze --pass <name>`: detection is the only pass reachable from the CLI, `machO(for:)` still calls it inline, and the report still says nothing about the `SymbolModel` rows detection inserts — a fresh `thin_test` import lands 42 symbol rows from a run that narrates 33, so the census a script sees depends on which passes have run. Pass-aware counts in every report is the fix.

### 17. `aether doctor` — prove a store matches what import claimed

**Evidence.** Re-importing the same `.qwen/tmp/thin_test` with the local build prints `Parsed 5 segments, 11 sections, 33 symbols (7 generated)` and `Detected 14 procedures`; the store then holds 1/5/11/42/14 rows.
The older `clidocs/ThinTest.aetherproj` holds 26 symbols with `ZRAWTYPE` = 0 on every row (all `SymbolType.unknown`) and 0 procedures, so `count` prints a clean `0` for a document that predates typed symbolization and detection.
**Status.** Still open, and the migration hazard is now worse than stale rows: any store written before `BinaryFormat` / `Endianness` / `Architecture` became `Int`-backed refuses to open (`NSCocoaErrorDomain (134140)`, `entity=BinaryModel, property=endian.endian, reason=Source and destination attribute types are incompatible`) and the CLI traps out of `try!` with exit 133.
The byte-count worry from the earlier draft is resolved: `program fetch` prints `51480 bytes` for the 51480-byte `.qwen/tmp/thin_test`, while `length(ZDATA)` on the `@Attribute(.externalStorage)` column reports 51481 — so `doctor` must compare `data.count` against `fileURL`, never the SQLite blob.
**Feature.** `aether doctor --project`: store URL, per-model row counts, `rawKind`/`rawType` histograms, section/symbol containment, stored entry point. Cheap version: treat any CoreData migration warning as `schema: stale` and say so instead of reporting zeros that look like an empty binary. Add `--strict`, exiting non-zero when the store predates the current model list.
**Cost.** Low — the queries are the ones already documented in this file's sqlite snippets; the hard part is agreeing on the per-model row-count list.

### 19. `import --no-analyze` — and a parse path that does not print

**Evidence.** Entry 1's `aether inspect` is only cheap if parsing has no side effects. `machO(for:)` runs detection and itself writes to the terminal, so a read-only look at a binary implied analysis, a mutation and uncontrolled stdout from a library function.
**Status.** Partly fixed. `ImportCommand` is now load-first-save-second — `try await MachOLoader.load(binary)` before any `save()`, with the comment explaining that a non-Mach-O/fat/32-bit file throws before anything persists — and it honours `--dry-run`, which is now a bare flag rather than `--dry-run true`.
Still open: the loader prints from library code (`print(log)` at `Load/MachOLoader.swift:161`, `print(proceduresLine)` at `:178`) and still calls `ProcedureDetector().detect(in:)` inline at `:174`, so there is no structure-only parse.
**Feature.** `import --no-analyze` (structure only) and a `--quiet` that captures loader output; move the loader's `print` behind the CLI so `AetherKit` stays a library. This is also what makes `--dry-run` and `analyze` (entry 16) composable instead of three different side-effect levels.

### 20. `aether-cli/README.md` is stale against the shipped command tree

**Status.** Worse than when written: now actively wrong, in places. The command table still advertises `aether string [fetch]` (line 45) and `aether string count` (line 46), which no longer exist; the intro (line 3) still says queries cover "programs, segments, sections, strings"; the `program [fetch]` row still says the row prints "name + persistent ID", which `describe()` no longer does; and there are no rows for `symbol`, `annotation`, `bookmark`, any `delete`, `procedure detect`, `--dry-run`, or the six `insert` subcommands.
The import transcript (lines 79-81) still shows `Parsing 26 symbols` / `Parsed 26 symbols in 1 ms` / `Parsed 5 segments, 11 sections, 35 symbols (9 generated)` with no `Detected N procedures` line, and the sample transcript around line 125 still runs the deleted `aether string` commands.
The sentence at line 31 is wrong too: the README says that in each model group `fetch` is the default subcommand, so `aether segment --project D` equals `aether segment fetch --project D` — no group sets `defaultSubcommand` any more, so a bare group invocation errors on `--project`.
Every filter and every enum-valued option is undocumented as well, including the numbering the options now require (`--format 1`, `--architecture 3`, `--kind 1`).
It is half migrated: the schema notes at lines 170-171 already describe `MachOLoader.symbolize(in:)`, typed data rows and `stringValue` round-tripping. Only the command surface lags.
**Feature.** Not a code feature: regenerate the transcript from a real run (the staleness trap note at line 29 already warns that the installed binary lags the sources), add the `procedure` / `symbol` / `annotation` / `bookmark` / `insert` / `delete` rows and `--dry-run`, and re-check after any change to `describe()`.

---

## Not features — but they should stop living in `.qwen/tmp`

- Layout probes `.qwen/tmp/sizes.swift`, `maskcheck.swift`, `nlist_bc.swift`, `/private/tmp/nlist_check.c`: they assert SDK struct sizes and constants, a role now split between `AetherKit/Tests/CoreAetherTests/NListTypeTests.swift` and the detector comments. Pick one home.
- Assembled-instruction fixtures `.qwen/tmp/{br,sig,sig2,strimm,strimm2,strimm3,vectors,linkstore,offs,enc_probe}.s` (and their `.o`): the `clang -c` evidence behind every mask in `ProcedureDetector`. Their decoded values are already transcribed into the detector comments; the `mask_check.py` symmetric-diff assertions should become `AetherTests` cases.
- Corpus binaries `/private/tmp/probe_bin`, `probe_x86`, `probe_x86_stripped`, `.qwen/tmp/thin_test`: commit the sources (`.qwen/tmp/thin_test.swift`, `/private/tmp/probe.c`) as test fixtures; binaries do not belong in the repo.
- The 12 `/private/tmp/*.aetherproj` stores (`probe*`, `rustc*`, `x86*`, `py-proj`) are the working corpus behind entries 15-17: regenerate them with `aether new` + `aether import` from the committed sources rather than checking them in. They are worse than stale now — every one written before the `Int`-backed enum conversion refuses to open and traps (see the gotchas), so carry none of them over.
- `.qwen/tmp/underflow_check.swift`: documents a non-bug (Int arithmetic, no trap). Historical.
- `.qwen/tmp/clidocs/{ThinTest,ErrDoc}.aetherproj`, `/private/tmp/j2r*`, `/private/tmp/dumps`, `.qwen/tmp/s-*`, `__pycache__`: error fixtures or regenerable scratch.
