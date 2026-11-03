# CLI.md — `aether` feature opportunities found in `.qwen/tmp` and `/private/tmp`

Scratch space holds the analysis scripts used while fixing the Mach-O loader and
writing `ProcedureDetector`. Most are throwaway re-implementations of things the
CLI should do natively: they take a raw binary path, hand-parse the header, and
print what `aether` cannot print today.

Living list. Each entry names its scratch evidence, the proposed CLI surface, and
the cost in AetherKit terms.

## Verified CLI surface today (HEAD `b0554cd` + untracked work)

`aether-cli/Sources/Aether.swift` registers `program`, `section`, `segment`,
`string`, `procedure`, `new`, `import`. `procedure` also carries the untracked
`detect` subcommand (`aether-cli/Sources/Procedure.swift`).

Generic plumbing (`Sources/Fetch<T>.swift`, `Count<T>.swift`): `--project`,
`--limit`, `--offset`, plus a per-model `FetchOptions`. Only `BinaryModel`,
`SegmentModel`, `SectionModel`, `ProcedureModel` conform to `FetchableModel`.

The schema (`AetherKit/Sources/AetherKit/Schema/`) already exposes what the CLI
does not surface: `SymbolModel` (kind/type/binding, `isImport`/`isExport`,
`stringValue`), `AnnotationModel`, `BookmarkModel`, `CrossReferenceModel`,
`BlockModel`, `ProcedureModel.{isThunk,isLeaf,callees,callers,blocks,demangled}`.

Helpers already `public` and directly reusable: `BinaryModel.read(at:count:)`,
`readString(at:)`, `data(in:)`, `format(hex:)`, `section(containing:)`,
`SegmentModel.protectionString`, `SectionModel.{isExecutable,isZeroFill,containsCode}`,
`SymbolModel.isStringPredicate`, `SymbolModel.displayName`.

---

## Tier 1 — cheap, high value

### 1. `aether inspect <binary>` — parse a Mach-O without a document

**Evidence.** Every probe in the scratch set re-derives the layout from a raw path
instead of using the CLI: `.qwen/tmp/prologue_scan.swift`,
`.qwen/tmp/symtab_probe.swift`, `.qwen/tmp/sectdump.swift`, `.qwen/tmp/symdump.swift`,
`.qwen/tmp/nlist_hist.swift`, `/private/tmp/prologues.py`.

`.qwen/tmp/proctest.swift` already demonstrates the target shape: build a `BinaryModel`,
wrap it in `ModelContainer(Schema.project)`, call `MachOLoader.machO(for:)`, and print
segment/section/symbol/procedure counts.

**Feature.** Parse in memory — no `new`, no `--project`, no store on disk — and
print header fields, format/endian/architecture, `entryPoint`, `baseAddress`,
segments with protection, sections with flags/offset/size, and symbol-table counts
by kind. The README pitch (inspect a document on a machine that cannot run the app)
extends naturally to inspect a binary on any machine.

**Cost.** Low. `machO(for:)` is `static`, `nonisolated`, `throws`, and takes a
detached `BinaryModel`; `proctest.swift` proves the in-memory container path works
from a package consumer. Pair with entry 7 (`--json`) for diffable output.

### 2. `aether symbol …` — the whole symbol table is unqueryable

**Evidence.** `aether-cli/Sources/String.swift` line 5 says it outright: strings are
fetched via an in-memory filter because the generic `FetchCommand` cannot express it.
There is no `symbol` group at all, so the app Symbol/Import/Export navigators have
no CLI counterpart, and the workaround is raw `sqlite3` against `StoreContent` —
see `/private/tmp/aether_procs.json`. `.qwen/tmp/nlist_hist.swift` and
`symtab_probe.swift` build exactly the n_type/binding histograms these filters should
express.

**Feature.** `FetchCommand<SymbolModel>` / `CountCommand<SymbolModel>` with
`--name <substr>`, `--kind function|data|section`, `--type <SymbolType>`,
`--binding global|local|external|undefined`, `--imported`, `--exported`,
`--defined` (address != 0), `--section <name>`. `describe()` prints name,
address, size, kind, type, binding.

**Cost.** Low. `SymbolModel.isStringPredicate` in `Schema+.swift` already shows the
`#Predicate` shape over a stored enum field, which is what `rawKind` /
`rawType` / `rawBinding` are — so these filters belong in a `FetchDescriptor`
predicate, not in memory.

**Caveat.** `#Unique<SymbolModel>([.binary, .address, .identifier])` keys on
`identifier`, not `name`; `name` only tracks `identifier` after `refresh()` runs.

### 3. `aether bytes` — read file bytes at a virtual address

**Evidence.** `.qwen/tmp/around.swift` dumps 16-byte rows around an address by hand
because the CLI cannot; `strings_mirror.swift` and `symtab_probe.swift` hand-roll
`u32`/`cstr` readers for the same reason. Task 9 (hex view) was app-side only, so
the CLI has no byte view at all.

**Feature.** `aether bytes --address <hex> --length <n> [--program <name>]` using
`BinaryModel.read(at:count:)` + `BinaryModel.format(hex:)`; `--string` to call
`readString(at:)`; label the containing section via `section(containing:)`.
Reject addresses below `baseAddress` explicitly — `read(at:)` returns `nil` there,
so say so instead of printing nothing.

**Cost.** Trivial; the helpers are already public in `Schema+.swift`.

### 4. `aether find` — byte patterns and references to an address

**Evidence.** `.qwen/tmp/hunt.swift` searches the symtab region for the little-endian
encoding of a target address to find who points at it; `layout.swift` sweeps the
nlist region for plausible address u64s. `CrossReferenceModel` exists in the schema
(`fromAddress`, `toAddress`, `type: XRefType`) but no CLI command ever reads or writes
it.

**Feature.** `--bytes <hex>` / `--text <s>` over `BinaryModel.data`, reporting file
offsets **and** virtual addresses (offset + `baseAddress`); `--pointer-to <address>`
for candidate references — the primitive xref pass; `--xref <address>` to dump stored
`CrossReferenceModel` rows.

**Cost.** Medium. Scanning is trivial, but `CrossReferenceModel` stored properties are
declared without `public` in `Schema.swift`, so `fromAddress`/`toAddress`/`type` are
internal and invisible to `aether-cli`; reading stored xrefs needs an AetherKit
visibility change. Porting the analyzer that populates xrefs is a separate project.

### 5. `aether procedure detect --explain` — per-pattern census

**Evidence.** `mask_check.py`, `census2.py`…`census9.py` and `sectlist.py` exist purely
to measure each detector pattern on its own: per-pattern match counts, true/false
positives against objdump labels, per-section hit counts, and imm7/imm9/imm12
extraction sanity (mismatches: 0 of N). `ProcedureDetectionReport`
(`AetherKit/Sources/AetherKit/Analysis/ProcedureDetector.swift`) returns only the
aggregates `codeSections`/`entryPoints`/`synthesized`/`created`, so a regression in
one pattern is invisible in CLI output.

**Feature.** Per-pattern counts keyed by the detector own names (`framePair`,
`linkStore`, `stackAdjust`, `bti`, `pacibsp`, `stubThunk`), a per-section breakdown
under `--explain`, and `--pattern <name>` to run one pattern. The scratch scripts
symmetric-diff and mismatches-0 assertions belong in
`AetherKit/Tests/AetherTests/ProcedureDetectorTests.swift`, not `.qwen/tmp`.

**Cost.** Medium — thread a per-pattern counter through
`note(_:stackSize:isStub:)` and widen the report struct; no schema change.

### 6. `--dry-run` for `procedure detect`

**Evidence.** `DetectCommand` always `context.save()`s; the comparison captures in
`/private/tmp/aether_procs.json`, `aether_procs.txt` and `objdump_labels.txt` exist
because there is no way to see what a pass would create. Note the asymmetry:
`MachOLoader.machO(for:)` resets all four child relationships before re-parsing, while
`ProcedureDetector.detect` is append-only-and-idempotent — so measuring a fresh pass
currently requires a re-import.

**Feature.** `--dry-run` prints the report without saving; verify the inserted rows
really do not land when `save()` is skipped.

### 7. `--json` / machine-readable output on fetch, count and the reports

**Evidence.** `/private/tmp/aether_procs.json` — one row per procedure keyed by the
store own columns (`ZNAME`, `ZADDRESS`, `ZSTACKSIZE`, `ZSIZE`) — plus `aether_procs.txt`
and `objdump_labels.txt` address lists: the detector work was validated with `sqlite3
-json` because the tool has no structured output.

**Feature.** `--json` with stable lower-case keys (never `Z*` columns, never a
`PersistentIdentifier(…)` repr) on every fetch/count and on the `import` /
`procedure detect` reports. `describe()` needs a structured sibling, e.g.
`fields() -> [(String, String)]`, or a per-model `Codable` view.

**Cost.** Low-medium; touches the `FetchableModel` protocol and each `describe()`.

### 8. `string` parity with the scanner and `strings(1)`

**Evidence.** `.qwen/tmp/strings_mirror.swift` mirrors
`MachOLoader.scanStrings(in:)` exactly — region preference `__cstring` else the whole
`__TEXT` segment, printable `0x20…0x7E`, `minLen = 4`,
`vaddr = region.addr + offset`; `strings_scan_check.swift` diffs those hits against BSD
`strings(1)` output by value and file offset.

**Feature.** `--contains <text>` (substring over `stringValue`), `--min-length <n>`,
`--section <name>`, and a `--raw` mode that re-scans `BinaryModel.data` with the
scanner rules — the stored-rows-vs-fresh-scan drift check is exactly what a scripted
user wants after an app edit.

**Cost.** Low for `--contains` (combine `isStringPredicate` with a contains predicate).
`--raw` is low too, but re-point it at the current scanner: the ASCII pass the mirror
script copies is gone. The live path is `MachOLoader.symbolize(in:)`
(`Load/MachOLoader.swift:347`, declared in a `public nonisolated extension`, so
`aether-cli` can already call it), which types each row from the section's Mach-O
flags — `S_CSTRING_LITERALS` → `.ascii` (min 4 bytes) / `.utf16` (min 2 chars),
pointer sections → `.ptr` per 8 bytes, `S_4BYTE_LITERALS` / `S_INIT_FUNC_OFFSETS` →
`.u32`, `S_8BYTE_LITERALS` → `.u64`, `S_16BYTE_LITERALS` → `.u128`, everything else
one `.unknown` row; rows overlapping a named symbol are skipped. `scanStrings` now
survives only as a doc-comment mention at line 325. So `--raw` means diffing
`symbolize(in:)` output against the stored rows — and on a fresh `thin_test` import
the store holds 16 rows beyond the 26 symtab entries, exactly one of them
`SymbolType.ascii`, which is why `aether string count` answers `1`.

---

## Tier 2 — cheap, smaller payoff

### 9. Attribute columns and filters on `section` / `segment` fetch

**Evidence.** `sectdump.swift`, `sectprobe.swift`, `sectlist.py` and
`/private/tmp/prologues.py` all print `addr size offset flags` (and segment
`fileoff`/`filesize`/`maxprot`/`initprot`) because `SectionModel.describe()` emits
only `fullName`. The fields already exist on the models, as does
`SegmentModel.protectionString`.

**Feature.** `--verbose` on both groups; `--executable` / `--zerofill` filters via
`SectionModel.isExecutable` / `isZeroFill` / `containsCode` (that is what decides
detector coverage); `--ordinal` to print the 1-based section ordinal, because
`n_sect` is an ordinal over load-command order and that mapping drove the symtab bugs.

### 10. `aether annotation` and `aether bookmark` command groups

**Evidence.** `AnnotationModel` and `BookmarkModel` are both in
`Array<any PersistentModel.Type>.project` with `public` stored properties
(`kind`/`address`/`text`; `name`/`address`/`summary`/`created`) and no CLI surface.
PLAN.md records the app-side comment/bookmark dictionaries still being migrated to
these models, so a scripted write path is the natural counterpart.

**Feature.** `fetch`/`count` for both, plus `annotation add --address --text
[--trailing]` and `bookmark add --name --address`. Neither model has a
`binary`-scoped `#Unique`, so repeated adds duplicate rows — decide on
`--if-absent` (or dedupe) up front.

### 11. `--demangle`

**Evidence.** `SymbolModel.displayName` calls `demangleSwift` / `demangleCPP`, both
stubs that `return nil`. The names in `/private/tmp/aether_procs.json`
(`__ZN63_$LT$reqwest…`, `__ZN11miniz_oxide…`) are unreadable in a terminal. On this
machine `/usr/bin/c++filt` exists and `swift demangle --help` works, so a subprocess
demangler is cheap.

**Feature.** `--demangle` calling `swift demangle` / `c++filt` with a raw-name fallback;
`ProcedureModel.demangled` is the stored destination, so `--set-demangled` is the
natural write companion.

### 12. `--project` validation / `aether doctor`

**Evidence.** README documents the quirk: a nonexistent `--project` silently creates an
empty store and reports `Showing 0 models:` with exit 0. Fixtures
`.qwen/tmp/nope.aetherproj` and `.qwen/tmp/clidocs/ErrDoc.aetherproj` exist to exercise
error paths, and `AetherOptions.modelContainer` uses `try!` — a corrupt or schema-incompatible
store traps instead of erroring.

**Feature.** Make a missing document an error (behind a flag if the default must stay),
replace `try!` with a thrown error so the CLI exits non-zero, and add
`aether doctor --project`: store path, per-model row counts,
`format`/`endian`/`architecture`, and whether every `SymbolModel` lies inside a section.

---

## Tier 3 — real work, keep separate

### 13. `aether disassemble` — blocked on packaging, not on code

**Evidence.** The disassembly ground truth the detector work was measured against is
external: `/private/tmp/probe_dis.txt` and `.qwen/tmp/rustc_dis.txt` (68 MB) are
`objdump -d` output; `/private/tmp/objdump_labels.txt` is its label list. `aether` has
no disassembly path at all.

**Cost.** The Capstone driver (`Aether/Core/Disassembler/DisassemblerEngine.swift`) lives
in the app target, and `AetherKit/Package.swift` depends only on `Zip` — no
`CapstoneKit`. Mirroring the engine into AetherKit means a new package dependency for
the CLI: a packaging decision, not a CLI ticket.

---

## More gaps — measured against the scratch stores rather than the scripts

### 14. `aether program fetch --verbose` — the header fields are already stored

**Evidence.** `BinaryModel` (`Schema.swift:21`) keeps `format`, `endian`,
`architecture`, `is64`, `fileURL`, `entryPoint`, `stackSize`, `baseAddress` and the
`data` blob, all `public`, yet `ProgramCommand` prints only the name and a
`PersistentIdentifier(…)` repr. The scratch stores carry the values the CLI never
shows: `ZBASEADDRESS` 4294967296 in every document, `ZENTRYPOINT` 42949687 for
`probe_bin`, 429498791 for `rustc`, 42949707 for `python3`; the corpus is
`Mach-O`/`little`/`ARM64` except `x86-proj` and `x86s-proj` (`x86_64`).

**Feature.** `--verbose` columns for `program`: architecture, 64-bit, endian,
format, byte count, base address, entry point, stack size and source URL. That
makes tier 1 composable — `aether bytes --at $(aether program fetch
--entrypoint --bare) --count 32` — and lets a script tell arm64 from x86-64
without opening the file itself, which is what picks the detector pattern set.

### 15. `aether remove` and `import --replace`

**Evidence.** 13 scratch documents sit over 6 binaries: `probe`, `probe2`,
`probe3`, `probe-proj` all wrap `/private/tmp/probe_bin`; `rustc`, `rustc2`,
`rustc3`, `rustc-clean`, `rustc-probe` all wrap `/usr/local/bin/rustc`. One new
document per detector iteration, because there is no way to take rows back out.
Every child relationship on `BinaryModel` (`Schema.swift:36-54`) is
`deleteRule: .cascade`, so deletion today means `rm -rf` of the store.

**Feature.** `aether remove --program <name>` printing the cascade counts first
(segments / sections / symbols / procedures it will drop) and `--dry-run`, plus
`import --replace` to re-parse into an existing document. Without these, scripted
corpus work can only grow the store set.

### 16. `aether analyze` — re-run a pass without re-parsing

**Evidence.** The detection pass is welded into the loader at
`Load/MachOLoader.swift:174` (`let report = ProcedureDetector().detect(in: model)`)
inside `machO(for:)`, so re-analysing a stored document is impossible; the
five `rustc` documents are the fossil record of that, with counts drifting
15795/5981 → 10712/7547 → 10712/7546 → 14881/11716 for one identical input.
Re-running is already safe: `ProcedureDetector.detect` is append-only and
`ProcedureModel` carries `#Unique<ProcedureModel>([.symbol])`.

**Feature.** `aether analyze --pass <name>` over the stored document, with
`--list-passes`. Scope is AetherKit-side passes only (`Analysis/`
sources today — `ProcedureDetector.swift`); the ~20 app analysers under `Aether/Core/Analysis/` are
out of scope until they move. Note the side effect to surface in the report: detection inserts
its own `SymbolModel` rows, so a fresh `thin_test` import lands 42 symbol rows from
a run that narrates 33 — the census a script sees depends on which passes have
run, which argues for pass-aware counts in every report.

### 17. `aether doctor` — prove a store matches what import claimed

**Evidence.** Re-importing the same `.qwen/tmp/thin_test` with the local build
prints `Parsed 5 segments, 11 sections, 33 symbols (7 generated)` and
`Detected 14 procedures`; the store then holds 1/5/11/42/14 rows. The older
`clidocs/ThinTest.aetherproj` holds 26 symbols with `ZRAWTYPE` = 0 on every row
(all `SymbolType.unknown`) and 0 procedures, so `aether string count` prints a
clean `0` for a document that predates typed symbolization and detection.
Opening that store also emits `CoreData: error: Persistent History (1) has to be
truncated due to the following entities being removed: (StringModel)` plus three
warnings on stderr, and the CLI still exits 0.

**Feature.** `aether doctor --project`: store URL, per-model row counts,
`rawKind`/`rawType` histograms, section/symbol containment, stored entry point,
and a `--strict` non-zero exit when the store predates the current model list.
Cheap version: treat any CoreData migration warning as `schema: stale` and say
so instead of reporting zeros that look like an empty binary.

**Cost.** Low — the queries are the ones already documented in this file's
sqlite snippets; the hard part is agreeing on the per-model row-count list.

One extra check worth wiring in: compare the stored blob against the file
`fileURL` points at — `thin_test` is 51480 bytes on disk while both the fresh and
the older document store 51481. Whether that is Core Data blob framing or the loader
is unverified; `doctor` is the right place to surface the difference.

### 18. `--program <name>` scoping on every query group

**Evidence.** The model list makes `program` plural (`BinaryModel` is one row per
imported binary) and tier 1's `bytes`/`find` need one program's address space,
yet no group takes a program selector; today the only isolation is one binary per
document, which is exactly the habit the 13-document corpus came from.

**Feature.** `--program <name|index>` on `section`, `segment`, `string`,
`procedure`, `bytes` and `find`, defaulting to the single program and erroring when a document
holds several. `#Predicate` over a relationship may not translate to SQLite —
fall back to walking `BinaryModel.sections`/`symbols` in memory, which is what
`String.swift` already does for the string filter.

### 19. `import --no-analyze` — and a parse path that does not print

**Evidence.** Entry 1's `aether inspect` is only cheap if parsing has no side
effects. `machO(for:)` runs detection, `context.save()`s through the caller, and
itself writes to the terminal (`print(proceduresLine)` at
`Load/MachOLoader.swift:179`), so a read-only look at a binary currently implies
analysis, a mutation and uncontrolled stdout from a library function.

**Feature.** `import --no-analyze` (structure only) and a `--quiet` that captures
loader output; move the loader's `print` behind the CLI so `AetherKit` stays a
library. This is also what makes `--dry-run` (entry 6) and `analyze` (entry 16)
composable instead of three different side-effect levels.

### 20. `aether-cli/README.md` is stale against the shipped command tree

**Evidence.** `aether --help` lists seven groups (`program`, `section`,
`segment`, `string`, `procedure`, `new`, `import`); the README table documents
six and never mentions `procedure`. Its import transcript shows `Parsing 26
symbols` / `Parsed 26 symbols in 1 ms` / `35 symbols (9 generated)` while the
current build prints `Parsed 26 symtab entries -> 26 symbols` / `33 symbols (7
generated)` followed by `Detected 14 procedures in 2 ms`. The sample also embeds
a raw `PersistentIdentifier(… <x-coredata://…/BinaryModel/p1>)` line, i.e. the
repr entry 7 proposes to remove.

**Feature.** Not a code feature: regenerate the transcript from a real run
(the staleness trap note in README already says the installed binary lags the
sources), add the `procedure` rows including `procedure detect`, and re-check
after any change to `describe()`.

---

## Not features — but they should stop living in `.qwen/tmp`

- Layout probes `.qwen/tmp/sizes.swift`, `maskcheck.swift`, `nlist_bc.swift`,
`/private/tmp/nlist_check.c`: assert SDK struct sizes/constants, a role now split between
`AetherKit/Tests/CoreAetherTests/NListTypeTests.swift` and the detector comments. Pick one
home.
- Assembled-instruction fixtures `.qwen/tmp/{br,sig,sig2,strimm,strimm2,strimm3,vectors,
linkstore,offs,enc_probe}.s` (and their `.o`): the `clang -c` evidence behind every mask
in `ProcedureDetector`.
Their decoded values are already transcribed into the detector comments; the
`mask_check.py` symmetric-diff assertions should become `AetherTests` cases.
- Corpus binaries `/private/tmp/probe_bin`, `probe_x86`, `probe_x86_stripped`,
`.qwen/tmp/thin_test`: commit the sources (`.qwen/tmp/thin_test.swift`,
`/private/tmp/probe.c`) as test fixtures; binaries do not belong in the repo.
- `.qwen/tmp/underflow_check.swift`: documents a non-bug (Int arithmetic, no trap).
Historical.
- `/private/tmp/j2r*`, `/private/tmp/dumps`, `.qwen/tmp/s-*`, `__pycache__`,
`clidocs/*.aetherproj`: unrelated or regenerable scratch.
