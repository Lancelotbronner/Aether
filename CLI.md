# Aether CLI — feature backlog

Scratch space holds the analysis scripts used while fixing the Mach-O loader and writing `ProcedureDetector`. Most are throwaway re-implementations of things the CLI should do natively: they take a raw binary path, hand-parse the header, and print what `aether` cannot print today.
Living list. Each entry names its scratch evidence, the proposed CLI surface, the cost in AetherKit terms, and — where the proposal has since landed — a status line.

## Verified CLI surface today (HEAD `ab44278`)

`aether --help` registers seven model groups — `program`, `section`, `segment`, `symbol`, `procedure`, `annotation`, `bookmark` — plus `new` and `import`.
Every group carries `fetch` / `count` / `delete`, and `procedure` additionally carries `detect`; `fetch` is no longer the group default, since no group sets `defaultSubcommand` — `aether symbol --project D` reports Unknown option --project, so the subcommand has to be spelled out.
The former `string` group is gone: `String.swift` was deleted and strings are plain `SymbolModel` rows under `symbol`.
`Sources/Fetch<T>.swift` is now the whole generic machinery: a `FetchableModel` protocol with `plural`, `describe()`, an associated `FetchOptions` defaulting to `EmptyOptions` (`Sources/Utilities.swift`), `static var subcommands` so a model can hang its own subcommands under `fetch`/`count`/`delete`, and `static func apply(_:to:)` to decorate the `FetchDescriptor` with a predicate and `sortBy`.
`FetchCommand`, `CountCommand` and the new `DeleteCommand` (`Sources/Delete<T>.swift`) are all generic over it.
All seven models in `Array<any PersistentModel.Type>.project` now conform; `CrossReferenceModel` and `BlockModel` are deliberately off the CLI, which also keeps their `internal` stored properties from needing an AetherKit visibility change.
`AetherOptions` (`Sources/Aether.swift`) carries `--project` plus `--dry-run`; `import`, `delete` and `procedure detect` all skip `context.save()` when dry.
Every `describe()` is now one `key=value` line — greppable, and exactly the shape entry 7 wants to JSON-ify:
- `program`: name, format, architecture, endian, `64-bit`/`32-bit`, byte count, `base=` `entry=` `stack=` `file=`, then all seven child counts (`segments=` `sections=` `symbols=` `procedures=` `references=` `annotations=` `bookmarks=`).
- `segment`: `name @addr size= file=<off>+<len> prot=rwx maxprot= initprot= sections= program=`.
- `section`: `__SEG,__name @addr size= offset= align= flags= executable= zerofill= code= segment= program=`.
- `symbol`: `name @addr size= kind= type= binding= import= export= identifier= value= program=`.
- `procedure`: `name @addr size= frame= thunk= leaf= demangled= blocks= callers= callees=` plus inline `arguments=[name: type reg|sp+n]` and `locals=[name: type sp+n:size]`.
- `annotation`: `text @addr kind= program=`; `bookmark`: `name @addr created= summary= program=`.
Hex is upper-case through one `hex(_:)` helper over `some BinaryInteger`; `persistentModelID` is deliberately not printed in any `describe()`.
Helpers still `public` and directly reusable: `BinaryModel.read(at:count:)`, `readString(at:)`, `data(in:)`, `format(hex:)`, `section(containing:)`, `SegmentModel.protectionString`, `SectionModel.{isExecutable,isZeroFill,containsCode}`, `SymbolModel.isStringPredicate`, `SymbolModel.displayName`.

### Still open after these changes

`inspect` / `bytes` / `find` (entries 1, 3, 4), `--explain` (5), `--json` (7), every model-specific filter except `procedure --name` (2, 8, 9), `annotation add` / `bookmark add` (10), `--demangle` (11), `doctor` (12, 17), `disassemble` (13), `import --replace` (15), `analyze --pass` / `--list-passes` (16), `--program` scoping (18), `import --no-analyze` / `--quiet` (19).
Entry 20 is no longer a nice-to-have: the README now documents a command tree that does not exist.

## Tier 1 — cheap, high value

### 1. `aether inspect <binary>` — parse a Mach-O without a document

**Evidence.** Every probe in the scratch set re-derives the layout from a raw path instead of using the CLI: `.qwen/tmp/prologue_scan.swift`, `.qwen/tmp/symtab_probe.swift`, `.qwen/tmp/sectdump.swift`, `.qwen/tmp/symdump.swift`, `.qwen/tmp/nlist_hist.swift`, `/private/tmp/prologues.py`.
**Status.** Still open, and slightly harder than when written.
`.qwen/tmp/proctest.swift` already demonstrates the target shape: build a `BinaryModel`, wrap it in `ModelContainer(Schema.project)`, call `MachOLoader.machO(for:)`, and print segment/section/symbol/procedure counts.
**Feature.** Parse in memory — no `new`, no `--project`, no store on disk — and print header fields, format/endian/architecture, `entryPoint`, `baseAddress`, segments with protection, sections with flags/offset/size, and symbol-table counts by kind. The README pitch (inspect a document on a machine that cannot run the app) extends naturally to inspect a binary on any machine.
**Cost.** Low but now ordered: `machO(for:)` is `static`, `nonisolated`, `throws` and takes a detached `BinaryModel`, yet it also prints (`Load/MachOLoader.swift:161`, `:178`) and runs detection (`:174`), so a read-only `inspect` wants entry 19's `--quiet` / `--no-analyze` first.

### 2. `aether symbol …` — the whole symbol table is unqueryable

**Evidence.** The deleted `Sources/String.swift` said it outright: strings were fetched by an in-memory filter because the generic `FetchCommand` could not express it. There is no `symbol` group at all in the shipped CLI of that era, so the app Symbol/Import/Export navigators had no CLI counterpart and the workaround was raw `sqlite3` against `StoreContent` — see `/private/tmp/aether_procs.json`. `.qwen/tmp/nlist_hist.swift` and `symtab_probe.swift` build exactly the n_type/binding histograms these filters should express.
**Status.** Half shipped. `symbol fetch` / `symbol count` / `symbol delete` exist, `fetch` is the group default, and `describe()` prints name, address, size, kind, type, binding, import/export, identifier and stored value. Real row from `/private/tmp/probe.aetherproj`: `__mh_execute_header @100000000 size=0 kind=function type=function binding=global import=false export=true identifier=__mh_execute_header value= program=probe_bin`.
**Still missing.** Every filter. `SymbolModel` declares no `FetchOptions`, so `symbol fetch` takes only `--limit` / `--offset`: no `--name <substr>`, `--kind function|data|section`, `--type <SymbolType>`, `--binding global|local|external|undefined`, `--imported`, `--exported`, `--defined`, `--section <name>`. The histograms above are still `sqlite3` work.
**Cost.** Low, and the predicate shape is now proven in-tree rather than guessed: `Procedure.swift` runs `#Predicate<ProcedureModel> { $0.symbol.name.localizedStandardContains(name) }` over a relationship keypath, and `procedure fetch --project /private/tmp/probe.aetherproj --name sub` returns the four `sub_*` rows — so relationship keypaths do translate, which also answers entry 18's doubt.
**Caveat.** `#Unique<SymbolModel>([\.binary, \.address, \.identifier])` keys on `identifier`, not `name`; `name` only tracks `identifier` after `refresh()` runs.

### 3. `aether bytes` — read file bytes at a virtual address

**Evidence.** `.qwen/tmp/around.swift` dumps 16-byte rows around an address by hand because the CLI cannot; `strings_mirror.swift` and `symtab_probe.swift` hand-roll `u32`/`cstr` readers for the same reason. The app-side hex view is not reachable from a terminal.
**Status.** Still open.
**Feature.** `aether bytes --address <hex> --length <n> [--program <name>]` using `BinaryModel.read(at:count:)` + `BinaryModel.format(hex:)`; `--string` to call `readString(at:)`; label the containing section via `section(containing:)`. Reject addresses below `baseAddress` explicitly — `read(at:)` returns `nil` there, so say so instead of printing nothing.
**Cost.** Trivial; `read(at:count:)`, `readString(at:maxLength:)`, `format(hex:)`, `data(in:)` and `section(containing:)` are all public in `Schema+.swift`. One thing to note: `BinaryModel.hex(bytes:)` (the `Span<UInt8>` byte formatter) was just deleted from that file, and `format(hex:)` takes a `Range<UInt64>` through `Data` — if the byte view wants a streaming formatter, that helper comes back.

### 4. `aether find` — byte patterns and references to an address

**Evidence.** `.qwen/tmp/hunt.swift` searches the symtab region for the little-endian encoding of a target address to find who points at it; `layout.swift` sweeps the nlist region for plausible address u64s. `CrossReferenceModel` exists in the schema (`fromAddress`, `toAddress`, `type: XRefType`) but no CLI command ever reads or writes it.
**Status.** Still open, and the scope call is now explicit: `CrossReferenceModel` (and `BlockModel`) were left out of the command tree, so their stored properties are still `internal` in `Schema.swift` and invisible to `aether-cli`.
**Feature.** `--bytes <hex>` / `--text <s>` over `BinaryModel.data`, reporting file offsets **and** virtual addresses (offset + `baseAddress`); `--pointer-to <address>` for candidate references — the primitive xref pass; `--xref <address>` to dump stored `CrossReferenceModel` rows.
**Cost.** Medium. Scanning is trivial, but reading stored xrefs needs the AetherKit visibility change that was deliberately skipped; porting the analyzer that populates xrefs is a separate project.

### 5. `aether procedure detect --explain` — per-pattern census

**Evidence.** `mask_check.py`, `census2.py`…`census9.py` and `sectlist.py` exist purely to measure each detector pattern on its own: per-pattern match counts, true/false positives against objdump labels, per-section hit counts, and imm7/imm9/imm12 extraction sanity (mismatches: 0 of N).
**Status.** `detect` itself improved — it now runs over every binary in the document and prints `ProcedureDetectionReport.summary` plus the store total (`probe_bin: ProcedureDetector: 2 code sections, 7 entry points, 1 synthesized symbols, 1 procedures, 7 total procedures`) — but the report still exposes only the four aggregates (`codeSections`, `entryPoints`, `synthesized`, `created`), so a regression in one pattern stays invisible.
**Feature.** Per-pattern counts keyed by the detector own names (`framePair`, `linkStore`, `stackAdjust`, `bti`, `pacibsp`, `stubThunk`), a per-section breakdown under `--explain`, and `--pattern <name>` to run one pattern. The scratch scripts symmetric-diff and mismatches-0 assertions belong in `AetherKit/Tests/AetherTests/ProcedureDetectorTests.swift`, not `.qwen/tmp`.
**Cost.** Medium — thread a per-pattern counter through `note(_:stackSize:isStub:)` and widen the report struct; no schema change.

### 6. `--dry-run` for `procedure detect`

**Evidence.** `DetectCommand` always `context.save()`d; the comparison captures in `/private/tmp/aether_procs.json`, `aether_procs.txt` and `objdump_labels.txt` exist because there is no way to see what a pass would create. Note the asymmetry that drove it: `MachOLoader.machO(for:)` resets all four child relationships before re-parsing, while `ProcedureDetector.detect` is append-only-and-idempotent — so measuring a fresh pass currently required a re-import.
**Status.** Shipped, with a papergun. `--dry-run` moved onto `AetherOptions`, so every command takes it, and `import` / `delete` / `procedure detect` all guard `save()`. It works: after `procedure detect --project /private/tmp/probe.aetherproj --dry-run true` reported 7 total procedures, the store still holds 6 `ZPROCEDUREMODEL` rows.
Because it is declared `@Option var dryRun = false` rather than `@Flag` / `@Option(name: …, .flag)`, the spelling is `--dry-run true`; `--dry-run` alone is `Error: Missing value for '--dry-run <dry-run>'`. Worth normalising the moment someone types it wrong.

### 7. `--json` / machine-readable output on fetch, count and the reports

**Evidence.** `/private/tmp/aether_procs.json` — one row per procedure keyed by the store own columns (`ZNAME`, `ZADDRESS`, `ZSTACKSIZE`, `ZSIZE`) — plus `aether_procs.txt` and `objdump_labels.txt` address lists: the detector work was validated with `sqlite3 -json` because the tool has no structured output.
**Status.** Still open, and more urgent now: the `key=value` shape every `describe()` uses just moved the problem. Values are unquoted and unescaped, so a `stringValue` containing a newline breaks the one-row-per-line invariant in the middle of a field — `str_100000620 @100000620 size=4 kind=data type=ascii binding=local import=false export=false identifier=str_100000620 value=%ld` then a stray ` program=probe_bin` on the next line.
**Feature.** `--json` with stable lower-case keys (never `Z*` columns, never a `PersistentIdentifier(…)` repr) on every fetch/count and on the `import` / `procedure detect` reports. `describe()` needs a structured sibling, e.g. `fields() -> [(String, String)]`, or a per-model `Codable` view; until then, escaping (`\n` inside quoted values) is the minimum for anything a script reads.
**Cost.** Low-medium; touches the `FetchableModel` protocol and each `describe()`.

### 8. `symbol` parity with the scanner and `strings(1)`

**Evidence.** `.qwen/tmp/strings_mirror.swift` mirrors `MachOLoader.scanStrings(in:)` exactly — region preference `__cstring` else the whole `__TEXT` segment, printable `0x20…0x7E`, `minLen = 4`, `vaddr = region.addr + offset`; `strings_scan_check.swift` diffs those hits against BSD `strings(1)` output by value and file offset.
**Status.** The `string` group was deleted, so this work now belongs on `symbol` and is still entirely missing: no `--contains <text>`, `--min-length <n>`, `--section <name>`, `--raw`. `SymbolModel.isStringPredicate` is public and unexposed, which is precisely the filter `--contains` needs.
**Feature.** `--contains` (substring over `stringValue`), `--min-length <n>`, `--section <name>`, and a `--raw` mode that re-scans `BinaryModel.data` with the scanner rules — the stored-rows-vs-fresh-scan drift check is exactly what a scripted user wants after an app edit.
**Cost.** Low for `--contains`; combine `isStringPredicate` with a contains predicate in the descriptor.
`--raw` is low too, but re-point it at the current scanner: the ASCII pass the mirror script copies is gone. The live path is `MachOLoader.symbolize(in:)` (`Load/MachOLoader.swift:347`, declared in a `public nonisolated extension`, so `aether-cli` can already call it), which types each row from the section's Mach-O flags — `S_CSTRING_LITERALS` → `.ascii` (min 4 bytes) / `.utf16` (min 2 chars), pointer sections → `.ptr` per 8 bytes, `S_4BYTE_LITERALS` / `S_INIT_FUNC_OFFSETS` → `.u32`, `S_8BYTE_LITERALS` → `.u64`, `S_16BYTE_LITERALS` → `.u128`, everything else one `.unknown` row; rows overlapping a named symbol are skipped.
`scanStrings` survives only as a doc-comment mention at line 325, so `--raw` means diffing `symbolize(in:)` output against the stored rows — and on a fresh `thin_test` import the store holds 16 rows beyond the 26 symtab entries, exactly one of them `SymbolType.ascii`. The old `aether string count` answered `1`; today the equivalent query has no filter to express it.

## Tier 2 — cheap, smaller payoff

### 9. Attribute columns and filters on `section` / `segment` fetch

**Evidence.** `sectdump.swift`, `sectprobe.swift`, `sectlist.py` and `/private/tmp/prologues.py` all print `addr size offset flags` (and segment `fileoff`/`filesize`/`maxprot`/`initprot`) because `SectionModel.describe()` used to emit only `fullName`. The fields already exist on the models, as does `SegmentModel.protectionString`.
**Status.** Columns shipped — both groups now print everything, so `--verbose` is moot: `__TEXT,__stubs @100000A60 size=108 offset=A60 align=2 flags=80000408 executable=true zerofill=false code=true segment=__TEXT program=thin_test` and `__TEXT @100000000 size=16384 file=0+4000 prot=r-x maxprot=5 initprot=5 sections=7 program=thin_test`. `__DATA,__common @100008008 … offset=0 … zerofill=true` is now visible without `sectprobe`.
**Still missing.** The filters: `--executable` / `--zerofill` / `--code` (via `SectionModel.isExecutable` / `isZeroFill` / `containsCode`, which is what decides detector coverage) and `--ordinal` for the 1-based section ordinal, because `n_sect` is an ordinal over load-command order and that mapping drove the symtab bugs.

### 10. `aether annotation` and `aether bookmark` command groups

**Evidence.** `AnnotationModel` and `BookmarkModel` are both in `Array<any PersistentModel.Type>.project` with `public` stored properties (`kind`/`address`/`text`; `name`/`address`/`summary`/`created`) and no CLI surface. PLAN.md records the app-side comment/bookmark dictionaries still being migrated to these models, so a scripted write path is the natural counterpart.
**Status.** Read side shipped — both groups exist with `fetch` / `count` / `delete`, sorted by address — but they are unexercised at runtime: no store in the scratch corpus holds a single annotation or bookmark row, so their `describe()` output has never been seen.
**Still missing.** The write side: `annotation add --address --text [--trailing]` and `bookmark add --name --address`. Neither model has a `binary`-scoped `#Unique`, so repeated adds duplicate rows — decide on `--if-absent` (or dedupe) up front.

### 11. `--demangle`

**Evidence.** `SymbolModel.displayName` calls `demangleSwift` / `demangleCPP`, both stubs that `return nil`. The names in `/private/tmp/aether_procs.json` (`__ZN63_$LT$reqwest…`, `__ZN11miniz_oxide…`) are unreadable in a terminal. On this machine `/usr/bin/c++filt` exists and `swift demangle --help` works, so a subprocess demangler is cheap.
**Status.** Still open, and now measurably so: `procedure fetch` prints `demangled=` empty for every row of the rustc documents, while the stored `demangled` column stays blank.
**Feature.** `--demangle` calling `swift demangle` / `c++filt` with a raw-name fallback; `ProcedureModel.demangled` is the stored destination, so `--set-demangled` is the natural write companion.

### 12. `--project` validation / `aether doctor`

**Evidence.** README documents the quirk: a nonexistent `--project` silently creates an empty store and reports `Showing 0 models:` with exit 0. Fixtures `.qwen/tmp/nope.aetherproj` and `.qwen/tmp/clidocs/ErrDoc.aetherproj` exist to exercise error paths, and `AetherOptions.modelContainer` uses `try!` — a corrupt or schema-incompatible store traps instead of erroring.
**Status.** Still open: `modelContainer` is still a lazy `try! ModelContainer(...)`, so a bad store aborts the process rather than exiting non-zero with a message.
**Feature.** Make a missing document an error (behind a flag if the default must stay), replace `try!` with a thrown error so the CLI exits non-zero, and add `aether doctor --project`: store path, per-model row counts, `format`/`endian`/`architecture`, and whether every `SymbolModel` lies inside a section.

## Tier 3 — real work, keep separate

### 13. `aether disassemble` — blocked on packaging, not on code

**Evidence.** The disassembly ground truth the detector work was measured against is external: `/private/tmp/probe_dis.txt` and `.qwen/tmp/rustc_dis.txt` (68 MB) are `objdump -d` output; `/private/tmp/objdump_labels.txt` is its label list. `aether` has no disassembly path at all.
**Status.** Unchanged.
**Cost.** The Capstone driver (`Aether/Core/Disassembler/DisassemblerEngine.swift`) lives in the app target, and `AetherKit/Package.swift` depends only on `Zip` — no `CapstoneKit`. Mirroring the engine into AetherKit means a new package dependency for the CLI: a packaging decision, not a CLI ticket.

## More gaps — measured against the scratch stores rather than the scripts

### 14. `program` header fields — already stored, now printed

**Evidence.** `BinaryModel` (`Schema.swift:21`) keeps `format`, `endian`, `architecture`, `is64`, `fileURL`, `entryPoint`, `stackSize`, `baseAddress` and the `data` blob, all `public`, yet `ProgramCommand` printed only the name and a `PersistentIdentifier(…)` repr. The scratch stores carry values the CLI never showed: `ZBASEADDRESS` 4294967296 in every document, `ZENTRYPOINT` 42949687 for `probe_bin`, 429498791 for `rustc`, 42949707 for `python3`; the corpus is `Mach-O`/`little`/`ARM64` except `x86-proj` and `x86s-proj` (`x86_64`).
**Status.** Shipped, without the flag. `program fetch` now prints `thin_test Mach-O ARM64 little 64-bit 51480 bytes base=100000000 entry=1000006E8 stack=0 file=/Users/lancelot/Developer/Hacking/Aether/.qwen/tmp/thin_test segments=5 sections=11 symbols=26 procedures=0 references=0 annotations=0 bookmarks=0`, so `--verbose` was never needed and the `PersistentIdentifier` repr is gone from that line.
**Still missing.** Machine-extractable single values: tier 1's composable `aether bytes --at $(aether program fetch --entrypoint --bare)` still cannot work, because there is no `--bare` / field selector — that is entry 7's `--json` in disguise.
`import` still ends with `Successfully imported as \(binary.persistentModelID).`, so the repr the CLI just stopped printing is printed by the command that creates the row.

### 15. `aether remove` and `import --replace`

**Evidence.** Scratch documents sit over very few binaries: `probe`, `probe2`, `probe3`, `probe-proj` all wrap `/private/tmp/probe_bin`, and `rustc`, `rustc2`, `rustc3`, `rustc-clean`, `rustc-probe` all wrap `/usr/local/bin/rustc`. There are 15 stores in total, 13 of them real over just 6 distinct binaries, plus two error fixtures (`/Users/lancelot/Developer/Hacking/Aether/.qwen/tmp/nope.aetherproj`, `.qwen/tmp/clidocs/ErrDoc.aetherproj`). One new document per detector iteration, because there was no way to take rows back out. One new document per detector iteration, because there was no way to take rows back out. Every child relationship on `BinaryModel` (`Schema.swift:36-54`) is `deleteRule: .cascade`, so deletion meant `rm -rf` of the store.
**Status.** Half shipped. `delete` exists on all seven groups and is cascade-aware in the right way: it clears `propertiesToFetch` / `relationshipKeyPathsForPrefetching` before `modelContext.delete(model)`, honours `--dry-run true`, and reports `Deleted N <plural>`.
**Still missing.** `import --replace` to re-parse into an existing document, and the census before deletion — `delete` prints the count after the fact, not the segments/sections/symbols/procedures a `program delete` will drop through the cascade. Without `--replace`, scripted corpus work can still only grow the store set.

### 16. `aether analyze` — re-run a pass without re-parsing

**Evidence.** The detection pass is welded into the loader at `Load/MachOLoader.swift:174` (`let report = ProcedureDetector().detect(in: model)`) inside `machO(for:)`, so re-analysing a stored document was impossible; the five `rustc` documents are the fossil record of that, with counts drifting 15795/5981 → 10712/7547 → 10712/7546 → 14881/11716 for one identical input. Re-running is already safe: `ProcedureDetector.detect` is append-only and `ProcedureModel` carries `#Unique<ProcedureModel>([\.symbol])`.
**Status.** Half shipped. `procedure detect` is now a standalone pass over **every** `BinaryModel` in the document — no re-import needed — and prints the report per binary (`probe_bin: ProcedureDetector: 2 code sections, 7 entry points, 1 synthesized symbols, 1 procedures, 7 total procedures`). It also respects `--dry-run true`, so a pass can be measured before it lands.
**Still missing.** `--list-passes` and the general `analyze --pass <name>`: detection is the only pass reachable from the CLI, `machO(for:)` still calls it inline, and the report still says nothing about the `SymbolModel` rows detection inserts — a fresh `thin_test` import lands 42 symbol rows from a run that narrates 33, so the census a script sees depends on which passes have run. Pass-aware counts in every report is the fix.

### 17. `aether doctor` — prove a store matches what import claimed

**Evidence.** Re-importing the same `.qwen/tmp/thin_test` with the local build prints `Parsed 5 segments, 11 sections, 33 symbols (7 generated)` and `Detected 14 procedures`; the store then holds 1/5/11/42/14 rows. The older `clidocs/ThinTest.aetherproj` holds 26 symbols with `ZRAWTYPE` = 0 on every row (all `SymbolType.unknown`) and 0 procedures, so the count command prints a clean `0` for a document that predates typed symbolization and detection.
Opening that store also emits `CoreData: error: Persistent History (1) has to be truncated due to the following entities being removed: (StringModel)` plus three warnings on stderr, and the CLI still exits 0.
**Status.** Still open; two details to correct. The zero-procedure count is now read with `symbol count` / `procedure count` rather than the deleted `string count`, and `symbol fetch` prints those rows with `type=unknown` and `kind=unknown`, which makes the stale store look valid rather than empty. The byte-count worry from the earlier draft is resolved: `program fetch` prints `51480 bytes` for the 51480-byte `.qwen/tmp/thin_test`, while `length(ZDATA)` on the `@Attribute(.externalStorage)` column reports 51481 — so `doctor` must compare `data.count` against `fileURL`, never the SQLite blob.
**Feature.** `aether doctor --project`: store URL, per-model row counts, `rawKind`/`rawType` histograms, section/symbol containment, stored entry point. Cheap version: treat any CoreData migration warning as `schema: stale` and say so instead of reporting zeros that look like an empty binary.
**Cost.** Low — the queries are the ones already documented in this file's sqlite snippets; the hard part is agreeing on the per-model row-count list.
Add a `--strict` non-zero exit when the store predates the current model list.

### 18. `--program <name>` scoping on every query group

**Evidence.** The model list makes `program` plural (`BinaryModel` is one row per imported binary) and tier 1's `bytes`/`find` need one program's address space, yet no group takes a program selector; the only isolation was one binary per document, which is exactly the habit the 15-document corpus came from.
**Status.** Still open, with a cheap mitigation already in place: every `describe()` ends with `program=<binary.name>`, so rows from a multi-binary document are at least attributable after the fact.
**Feature.** `--program <name|index>` on `section`, `segment`, `symbol`, `procedure`, `annotation`, `bookmark`, `bytes` and `find`, defaulting to the single program and erroring when a document holds several.
The old doubt is answered: `#Predicate` over a relationship keypath does translate — `procedure --name` runs `$0.symbol.name.localizedStandardContains(name)` and returns the right rows — so try the descriptor before walking parents in memory. The `String.swift` in-memory fallback that used to be the precedent is gone.

### 19. `import --no-analyze` — and a parse path that does not print

**Evidence.** Entry 1's `aether inspect` is only cheap if parsing has no side effects. `machO(for:)` runs detection and itself writes to the terminal, so a read-only look at a binary implied analysis, a mutation and uncontrolled stdout from a library function.
**Status.** Partly fixed. `ImportCommand` is now load-first-save-second — `try await MachOLoader.load(binary)` before any `save()`, with the comment explaining that a non-Mach-O/fat/32-bit file throws before anything persists — and it honours `--dry-run true`.
Still open: the loader prints from library code (`print(log)` at `Load/MachOLoader.swift:161`, `print(proceduresLine)` at `:178`) and still calls `ProcedureDetector().detect(in:)` inline at `:174`, so there is no structure-only parse.
**Feature.** `import --no-analyze` (structure only) and a `--quiet` that captures loader output; move the loader's `print` behind the CLI so `AetherKit` stays a library. This is also what makes `--dry-run` (entry 6) and `analyze` (entry 16) composable instead of three different side-effect levels.

### 20. `aether-cli/README.md` is stale against the shipped command tree

**Status.** Worse than when written: now actively wrong, in places. The command table still advertises `aether string [fetch]` (line 45) and `aether string count` (line 46), which no longer exist; the intro (line 3) still says queries cover "programs, segments, sections, strings"; the `program [fetch]` row still says the row prints "name + persistent ID", which `describe()` no longer does; and there are no rows at all for `symbol`, `annotation`, `bookmark`, any `delete`, `procedure detect`, or `--dry-run`.
The import transcript (lines 79-81) still shows `Parsing 26 symbols` / `Parsed 26 symbols in 1 ms` / `Parsed 5 segments, 11 sections, 35 symbols (9 generated)` with no `Detected N procedures` line, and the sample transcript around line 125 still runs the deleted `aether string` commands.
The sentence at line 31 is wrong too: the README says that in each model group `fetch` is the default subcommand, so `aether segment --project D` equals `aether segment fetch --project D` — no group sets `defaultSubcommand` any more, so a bare group invocation errors on `--project`.
It is half migrated: the schema notes at lines 170-171 already describe `MachOLoader.symbolize(in:)`, typed data rows and `stringValue` round-tripping. Only the command surface lags.
**Feature.** Not a code feature: regenerate the transcript from a real run (the staleness trap note at line 29 already warns that the installed binary lags the sources), add the `procedure` / `symbol` / `annotation` / `bookmark` / `delete` rows and `--dry-run`, and re-check after any change to `describe()`.

---

## Not features — but they should stop living in `.qwen/tmp`

- Layout probes `.qwen/tmp/sizes.swift`, `maskcheck.swift`, `nlist_bc.swift`, `/private/tmp/nlist_check.c`: they assert SDK struct sizes and constants, a role now split between `AetherKit/Tests/CoreAetherTests/NListTypeTests.swift` and the detector comments. Pick one home.
- Assembled-instruction fixtures `.qwen/tmp/{br,sig,sig2,strimm,strimm2,strimm3,vectors,linkstore,offs,enc_probe}.s` (and their `.o`): the `clang -c` evidence behind every mask in `ProcedureDetector`. Their decoded values are already transcribed into the detector comments; the `mask_check.py` symmetric-diff assertions should become `AetherTests` cases.
- Corpus binaries `/private/tmp/probe_bin`, `probe_x86`, `probe_x86_stripped`, `.qwen/tmp/thin_test`: commit the sources (`.qwen/tmp/thin_test.swift`, `/private/tmp/probe.c`) as test fixtures; binaries do not belong in the repo.
- The 12 `/private/tmp/*.aetherproj` stores (`probe*`, `rustc*`, `x86*`, `py-proj`) are the working corpus behind entries 15-17: regenerate them with `aether new` + `aether import` from the committed sources rather than checking them in.
- `.qwen/tmp/underflow_check.swift`: documents a non-bug (Int arithmetic, no trap). Historical.
- `.qwen/tmp/clidocs/{ThinTest,ErrDoc}.aetherproj`, `/private/tmp/j2r*`, `/private/tmp/dumps`, `.qwen/tmp/s-*`, `__pycache__`: error fixtures or regenerable scratch.
