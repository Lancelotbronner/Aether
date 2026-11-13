# aether — Aether project tool (CLI)

A terminal utility for working with **Aether project documents** (`.aetherproj`). The Aether IDE saves each document as a SwiftData store on disk; `aether` creates those documents, imports a thin 64-bit Mach-O executable into one, and then reads and edits what the document holds — **programs, segments, sections, symbols, procedures, annotations and bookmarks** — with no GUI required.

Every transcript below was captured from a live build, so the output shape can be checked against a run rather than remembered.

## Prerequisites

- **macOS 27** (the package declares `platforms: [.macOS(.v27)]`)
- **Swift 6.4 toolchain** (`swift-tools-version: 6.4`) — e.g. Xcode 26.x; captured with `Apple Swift version 6.4.2 (swiftlang-6.4.2.1.9 clang-2100.4.1.1)`, target `arm64-apple-macosx27.2.0`

The package depends on [swift-argument-parser](https://github.com/apple/swift-argument-parser) (1.8.2+) and on the sibling [`AetherKit`](../AetherKit) package (referenced by path `../AetherKit`), which provides the SwiftData schema and the model-based Mach-O loader. `AetherKit` in turn pulls in [Zip](https://github.com/tomasf/Zip), so `aether-cli/` must stay a sibling of `AetherKit/` in the repo.

## Install

```sh
cd aether-cli
swift package experimental-install
```

This builds and installs the executable to `~/.swiftpm/bin/aether` (make sure that directory is on your `PATH`).

Uninstall:

```sh
swift package experimental-uninstall aether
```

> **Staleness trap:** the installed binary is a snapshot. After editing anything under `Sources/` (or `AetherKit/`), re-run `experimental-uninstall` + `experimental-install`, or `aether --help` will keep advertising the old command tree. `aether --version` prints `1.0`, which is a fixed string and will **not** tell you whether the installed copy is current.

## The shape of every command

```
aether <group> <verb> <project> [filters] [paging]
```

- **`<project>` is a positional, not an option**, and it is the first argument of every command except `inspect` (which takes an executable path and opens no store at all). It is spelled `aether segment fetch Doc.aetherproj`, never `--project Doc.aetherproj`.
- **The path is created on demand.** A path that does not exist becomes a valid, empty store, so a typo reads as "this binary has nothing in it" rather than as an error. `--existing` is the opt-out and fails instead:
  ```
  $ aether segment fetch readme20/Typo.aetherproj --existing
  Error: No project at /Users/…/readme20/Typo.aetherproj — --existing does not create one
  ```
  (exit 1, and no store left behind.)
- **There is no default subcommand.** `aether segment Doc.aetherproj` is rejected: `Error: Unexpected argument 'Doc.aetherproj'` (exit 64).
- `--limit` (default **100**, or `--all` for every row) and `--offset` page through results; `--json` is available on every `fetch` and `count`.
- `--demangle` (on `symbol`/`procedure` rows) fills a `demangled=` sibling and prints a tally line under the paging hint:
  ```
  $ aether procedure fetch readme20/ThinTest.aetherproj --demangle --limit 3
  Showing 3 (1-3) of 14 procedures:
  … 11 more — --all for every row, --offset 3 for the next page
  demangled 2 of 3 rows
  _main @1000006E8 size=660 frame=160 thunk=false leaf=true demangled= blocks=0 callers=0 callees=0 arguments=[] locals=[] program=thin_test
  _$s9thin_test12sumOfSquaresyS2i_SitF @10000097C size=56 frame=0 thunk=false leaf=true demangled=thin_test.sumOfSquares(Swift.Int, Swift.Int) -> Swift.Int blocks=0 callers=0 callees=0 arguments=[] locals=[] program=thin_test
  ```
  A name the toolchain's demanglers do not recognise keeps an empty `demangled=`.
- **Enum-valued filters take the number the help text spells out, not the word.** `symbol fetch --kind 1` selects functions (`--kind <kind>  Filter on kind (0 unknown, 1 function, 2 data, 3 section)`); `--kind function` is exit 64 with `Error: The value 'function' is invalid for '--kind <kind>'. Please provide one of '0', '1', '2' or '3'.`
- `--dry-run` is global to every command that can write a store. On read-only commands it is accepted and does nothing.

### Commands

| Command | Purpose | Notes |
| --- | --- | --- |
| `aether import <project> <executable>` | Load a **thin 64-bit Mach-O** into a document: segments, sections, symbols, strings, procedures | `--replace` drops every existing program first; without it the import **appends a second program** |
| `aether program fetch\|count\|delete` | The `BinaryModel` rows — one per imported program | `describe` fields include sha256, base, entry point and per-kind counts |
| `aether segment fetch\|count\|delete\|insert` | Mach-O segments (`__TEXT`, `__DATA`, `__PAGEZERO`, …) | `--binary`/`--name`/`--address`/`--protection` filters |
| `aether section fetch\|count\|delete\|insert` | Sections (`__TEXT,__text`, …) | `--segment`/`--section` (bare name resolves across segments) |
| `aether symbol fetch\|count\|delete\|insert` | Symbols and strings — the single row kind for both | `--kind`/`--type`/`--binding`/`--min-length`/`--section`/`--imported`/`--exported` |
| `aether symbol raw` | Re-parse the program's file in memory and diff it against the stored rows | `missing` / `stale` / `changed` buckets, plus a `detection skipped` note |
| `aether procedure fetch\|count\|delete\|insert` | Detected functions (`ProcedureModel`) | `--name`/`--binary`/`--address` filters, `--thunk`/`--leaf` flags |
| `aether procedure detect` | Run procedure detection over every program in the store | `--dry-run` reports the totals without writing rows; there is no `--binary` or per-pattern breakdown yet |
| `aether annotation fetch\|count\|delete\|insert` | Analyst notes (`AnnotationModel`) | |
| `aether bookmark fetch\|count\|delete\|insert` | Analyst bookmarks (`BookmarkModel`) | |
| `aether inspect <executable>` | Parse a binary **in memory**: no project, no store on disk | `--analyze` runs detection, `--log` prints the loader's narration |
| `aether addr <project> <address>` | One address: which segment/section/symbol/procedure covers it | address forms: decimal, `0x…`, `@…`, `off:<file offset>`, symbol name |
| `aether bytes <project> <address>` | Hex dump at an address, or typed values under `--as` | `--length` (default 64, max 4096); `--as u8 u16 u32 u64 f32 f64 ptr cstr wstr` |
| `aether find <project>` | Search file bytes: `--bytes` (two hex digits per byte, `??` for any), `--text`, `--pointer-to` | pages separately (default 500, `--all`), offsets shown as `off:<file offset>`, `--binary` required when the store holds several |
| `aether hash <project>` | Digest a program three ways: `file`, `body`, `layout` | `--scope <one>`, `--digest-only` prints the sha256 column alone |
| `aether doctor <project>` | Report what the store actually holds, including rows no section covers | distinguishes an empty document from an empty binary |
| `aether snapshot <project> [--out <file>]` | Pin every row of all seven groups to a JSON file | the file is deterministic, so two runs `cmp` clean |
| `aether changes <project> <snapshot>` | Diff the store against that file, matched on stable names | `added` / `removed` / `renamed` / `moved` / `changed`, `--fail-changed` for a non-zero exit |

Row commands share their verbs through one generic implementation (`Fetch<T>.swift`, `Count<T>.swift`, `Delete<T>.swift`, `Insert<T>.swift` — the `<T>` is literally in the file names), so a filter or flag added to one group is asked for by all of them.

## Output shape

A `fetch` prints a header, then — when the result is paged — the paging hint, then one line per row made of `key=value` columns:

```
$ aether section fetch readme20/ThinTest.aetherproj --limit 3
Showing 3 (1-3) of 11 sections:
… 8 more — --all for every row, --offset 3 for the next page
__TEXT,__text @1000006E8 size=888 offset=6E8 align=2 flags=80000400 executable=true zerofill=false code=true segment=__TEXT program=thin_test
__TEXT,__stubs @100000A60 size=108 offset=A60 align=2 flags=80000408 executable=true zerofill=false code=true segment=__TEXT program=thin_test
__TEXT,__const @100000AD0 size=26 offset=AD0 align=4 flags=0 executable=false zerofill=false code=false segment=__TEXT program=thin_test
```

An empty result is `Showing 0 (0-0) of 0 annotations:` with exit 0 — which is also what a mistyped project path produces.

## Examples

### Import a binary

```
$ aether import readme20/ThinTest.aetherproj ./thin_test
Mach-O: 51480 bytes, 64-bit
Parsing 20 load commands
Parsing 0 sections in __PAGEZERO
Parsing 7 sections in __TEXT
        __TEXT,__text
        __TEXT,__stubs
        __TEXT,__const
        __TEXT,__swift5_typeref
        __TEXT,__cstring
        __TEXT,__swift5_entry
        __TEXT,__unwind_info
Parsing 2 sections in __DATA_CONST
        __DATA_CONST,__objc_imageinfo
        __DATA_CONST,__got
Parsing 2 sections in __DATA
        __DATA,__data
        __DATA,__common
Parsing 0 sections in __LINKEDIT
Parsed 26 symtab entries -> 26 symbols in 1 ms
Parsed 5 segments, 11 sections, 33 symbols (7 generated) in 2 ms
Detected 14 procedures in 2 ms
thin_test machO arm64 little 64-bit 51480 bytes sha256=BBE70CFB1F227538EFFD8A1433E1763003DB38CE12F558C339A98F915F89F59E base=100000000 entry=1000006E8 stack=0 file=/Users/…/.qwen/tmp/thin_test segments=5 sections=11 symbols=42 procedures=14 references=0 annotations=0 bookmarks=0
```

The narration goes to **stdout**, the header row is the program row, and the symbol count in it (`42`) is higher than the loader's (`33`) because detection synthesized 9 more rows (`stub_…`) on top of the 7 the loader generated.

### Query the document

```
$ aether program fetch readme20/ThinTest.aetherproj
Showing 1 (1-1) of 1 programs:
thin_test machO arm64 little 64-bit 51480 bytes sha256=BBE70CFB… base=100000000 entry=1000006E8 stack=0 file=/Users/…/.qwen/tmp/thin_test segments=5 sections=11 symbols=42 procedures=14 references=0 annotations=0 bookmarks=0

$ aether segment fetch readme20/ThinTest.aetherproj
Showing 5 (1-5) of 5 segments:
__PAGEZERO @0 size=4294967296 file=0+0 prot=--- maxprot=0 initprot=0 sections=0 program=thin_test
__TEXT @100000000 size=16384 file=0+4000 prot=r-x maxprot=5 initprot=5 sections=7 program=thin_test
__DATA_CONST @100004000 size=16384 file=4000+4000 prot=rw- maxprot=3 initprot=3 sections=2 program=thin_test
__DATA @100008000 size=16384 file=8000+4000 prot=rw- maxprot=3 initprot=3 sections=2 program=thin_test
__LINKEDIT @10000C000 size=16384 file=C000+918 prot=r-- maxprot=1 initprot=1 sections=0 program=thin_test

$ aether procedure fetch readme20/ThinTest.aetherproj --limit 2
Showing 2 (1-2) of 14 procedures:
… 12 more — --all for every row, --offset 2 for the next page
_main @1000006E8 size=660 frame=160 thunk=false leaf=true demangled= blocks=0 callers=0 callees=0 arguments=[] locals=[] program=thin_test
_$s9thin_test12sumOfSquaresyS2i_SitF @10000097C size=56 frame=0 thunk=false leaf=true demangled= blocks=0 callers=0 callees=0 arguments=[] locals=[] program=thin_test

$ aether symbol count readme20/ThinTest.aetherproj --kind 1
14
```

`count` reports the total a `fetch` would return — filters apply to it too, and `--json` prints `{"plural": "symbols", "count": "14"}`: the numbers are JSON strings, as in every row this CLI emits.

Strings are symbols with a stored value, so `--min-length` is how you list them:

```
$ aether symbol fetch readme20/ThinTest.aetherproj --min-length 21 --json
[
{"name": "str_100000B00", "address": "100000B00", "size": "21", "kind": "data", "type": "ascii", "binding": "local", "import": "false", "export": "false", "identifier": "str_100000B00", "value": "sumOfSquares(3, 4) = ", "program": "thin_test"},
…
]
```

### Read a document without editing it

```
$ aether doctor readme20/ThinTest.aetherproj
project=/Users/…/readme20/ThinTest.aetherproj store=/Users/…/readme20/ThinTest.aetherproj/StoreContent cli=1.0 programs=1 segments=5 sections=11 symbols=42 procedures=14 annotations=0 bookmarks=0
thin_test: format=machO endian=little architecture=arm64 bits=64 bytes=51480 base=100000000 entry=1000006E8 file=/Users/…/.qwen/tmp/thin_test
thin_test: 42 symbols over 11 sections — 28 inside a section, 13 at address 0, 1 outside one
outside one — a row with bytes no section accounts for:
  __mh_execute_header @100000000 size=1768 kind=data type=unknown binding=global import=false export=true identifier=__mh_execute_header value= program=thin_test
thin_test: kinds unknown:13 function:14 data:15 — types unknown:27 ascii:1 function:14 — bindings local:27 global:2 external:13

$ aether addr readme20/ThinTest.aetherproj @100000AD0
@100000AD0 off=AD0 program=thin_test segment=__TEXT prot=r-x section=__TEXT,__const symbol=stub_100000AC0 @100000AC0+0 procedure=stub_100000AC0

$ aether bytes readme20/ThinTest.aetherproj @100000AD0 --length 16
@100000AD0 off=AD0 program=thin_test segment=__TEXT section=__TEXT,__const bytes=16
100000AD0:01 00 00 00 00 00 00 00 02 00 00 00 00 00 00 00 |................|

$ aether bytes readme20/ThinTest.aetherproj str_100000B00 --as cstr
@100000B00 off=B00 program=thin_test segment=__TEXT section=__TEXT,__cstring read=cstr count=1
100000B00 cstr = "sumOfSquares(3, 4) = "

$ aether find readme20/ThinTest.aetherproj --text sumOfSquares
search=text pattern=sumOfSquares program=thin_test
Showing 2 (0-1) of 2 hits:
off=B00 @100000B00 segment=__TEXT section=__TEXT,__cstring
off=C590 @10000C590 segment=__LINKEDIT section=none

$ aether find readme20/ThinTest.aetherproj --bytes "4d80??00"
search=bytes pattern=4D80??00 program=thin_test
No hits in thin_test

$ aether find readme20/ThinTest.aetherproj --pointer-to @100000B00
search=pointer pattern=@100000B00 program=thin_test
Showing 1 (0-0) of 1 hits:
off=210 @100000210 segment=__TEXT section=none aligned=true

$ aether hash readme20/ThinTest.aetherproj --scope file
Project: ThinTest.aetherproj
Digests — one row per program and scope:
program=thin_test scope=file input=51480 md5=95B1FCC57A61BC77AB42B1A1D82A0440 sha256=BBE70CFB1F227538EFFD8A1433E1763003DB38CE12F558C339A98F915F89F59E

$ aether procedure detect readme20/ThinTest.aetherproj --dry-run
thin_test: ProcedureDetector: 2 code sections, 14 entry points, 0 synthesized symbols, 0 procedures, 14 total procedures

$ aether inspect ./thin_test --analyze
thin_test machO arm64 little 64-bit 51480 bytes sha256=BBE70CFB1F227538EFFD8A1433E1763003DB38CE12F558C339A98F915F89F59E base=100000000 entry=1000006E8 stack=0 file=/Users/lancelot/Developer/Hacking/Aether/.qwen/tmp/thin_test segments=5 sections=11 symbols=42 procedures=14 references=0 annotations=0 bookmarks=0
5 segments:
        __PAGEZERO @0 size=4294967296 file=0+0 prot=--- maxprot=0 initprot=0 sections=0 program=thin_test
        __TEXT @100000000 size=16384 file=0+4000 prot=r-x maxprot=5 initprot=5 sections=7 program=thin_test
        …
```

`find`'s hit offsets are file offsets (`off=210`), not addresses — the line shows the address they resolve to and whether the match sits at an aligned offset (`aligned=true`), which is what separates a real pointer from a byte sequence that happens to look like one. `--bytes` takes `??` for any byte (`4d80??00`); a pattern with no match prints `No hits in thin_test` rather than an empty `Showing` header.

`doctor`'s third line is the point of the command: 13 rows at address 0 and 1 row outside any section say *what* is odd, which is how an analysis-only document is told apart from a binary that really has nothing in it.

### Pin a document, then diff it

```
$ aether snapshot readme20/ThinTest.aetherproj --out thin.json
Snapshot 73 rows to thin.json — 1 programs, 5 segments, 11 sections, 42 symbols, 14 procedures

$ aether changes readme20/ThinTest.aetherproj thin.json
Differences: 0 of 73 pinned rows — the project matches the snapshot

$ aether symbol insert readme20/ThinTest.aetherproj thin_test marker_20 @100004010
Inserted marker_20 @100004010 size=1 kind=unknown type=unknown binding=undefined import=false export=false identifier=marker_20 value= program=thin_test

$ aether changes readme20/ThinTest.aetherproj thin.json
Differences: 2 of 73 pinned rows — 1 added, 1 changed
changed program thin_test — symbols 42 -> 43
added symbol marker_20 @100004010
```

`changes` matches rows by name rather than by persistent ID, so a renamed symbol prints as one `renamed symbol old -> new @address` line, a renumbered one as `moved`, and the program row's per-kind counts (`symbols 42 -> 43`) catch a change a symbol diff would miss. `--fail-changed` makes a non-matching project exit 1, and a snapshot pinned from a *different* project reads as every row gone: `Differences: 24056 of 23978 pinned rows — 78 added, 23978 removed`.

### Edit a document

`--dry-run` reports the rows a write would take without saving them; without it the write commits.

```
$ aether symbol insert readme20/ThinTest.aetherproj thin_test probe @100000B00 --dry-run
Inserted probe @100000B00 size=1 kind=unknown type=unknown binding=undefined import=false export=false identifier=probe value= program=thin_test

$ aether symbol count readme20/ThinTest.aetherproj
42

$ aether symbol delete readme20/ThinTest.aetherproj --name _main --dry-run
Deleted 1 symbols — left behind 1 procedures pointing at a deleted symbol

$ aether program delete readme20/ThinTest.aetherproj --dry-run
Deleted 1 programs — the cascade takes 5 segments, 11 sections, 42 symbols, 14 procedures
```

The second line of that `delete` report is a warning, not a success: `ProcedureModel.symbol` is a required link with no delete rule, so deleting a symbol that a procedure points at leaves a procedure row whose symbol cannot be loaded any more. Deleting such a row by `PersistentID` aborts the process (exit 133) in a SwiftData fatal, and any `procedure fetch` over the same program traps on it too. `program delete` is the supported way to remove a program and its whole cascade.

### Error handling

`import` validates the header *before* saving, so a failed import leaves the document untouched:

```
$ aether import readme20/ThinTest.aetherproj notmacho.txt
Error: Not a Mach-O binary (magic 0x6c6c6568 — not a Mach-O header)

$ aether import readme20/ThinTest.aetherproj /bin/ls
Error: Unsupported binary: fat/universal Mach-O (magic 0xbebafeca) — thin images only

$ aether import readme20/ThinTest.aetherproj does-not-exist
Error: The file “does-not-exist” couldn’t be opened because there is no such file.
```

All three exit 1. A usage error — missing `<project>`, unknown option, `--kind function` — exits 64 and prints a `Usage:` line. `--limit 0` prints the header and no rows and exits 0, while a negative window only arrives as `--limit=-1` (a bare `--limit -1` is read as a missing value, exit 64).

**stderr is not clean**: CoreData writes debug chatter (`CoreData: debug: PostSaveMaintenance: incremental_vacuum …`) around writes, and the store's own warnings appear on stderr. Redirect stderr, not stdout, when scripting.

## Document format

An `.aetherproj` is a **plain directory** (a bundle; the UTType is `com.lancelotbronner.aetherproj`, `.package`-conforming) containing the SwiftData store:

```
ThinTest.aetherproj/
├── StoreContent              # SwiftData (CoreData/SQLite) store — the whole document
├── StoreContent-wal
├── StoreContent-shm
└── .StoreContent_SUPPORT/
```

- The CLI opens it with `ModelConfiguration(schema: .project, url: <doc>/StoreContent)` — `.project` is the AetherKit model-type list in `AetherKit/Sources/AetherKit/Schema/`. A container opened without that configuration lands on `~/Library/Application Support/default.store` instead.
- The imported **binary's bytes live inside the store** (`BinaryModel.data`), not as a separate file in the bundle. The original path is kept in `BinaryModel.fileURL` for reference.
- Everything below a program cascades from `BinaryModel` (`segment`, `section`, `symbol`, `procedure`, `annotation`, `bookmark`), which is why `program delete` reports the whole cascade. `#Unique` constraints keep one row per `(binary, address, identifier)` for symbols and per `(binary, address)` for segments and sections; procedures are unique on their symbol.
- **Strings are `SymbolModel` rows.** `MachOLoader` symbolizes data sections from their Mach-O section type (`MachOLoader.symbolize(in:)`): `__cstring`/`__ustring` runs become `.ascii`/`.utf16` symbols with the decoded text stored in `stringValue` (it round-trips through `--json`), pointer/literal sections become per-element `.ptr`/`.u32`/`.u64`/`.u128` symbols, and untyped sections get one `.unknown` symbol each.
- Procedure rows are *not* in the `.project` model-type list — they are reachable through the program's cascade, which is why `procedure detect` needs a store to work against.

## Development

```sh
cd aether-cli
swift build            # debug build, no install
swift build -c release # what the transcripts above came from
swift run aether --help
```

After any source edit to `aether-cli/` **or `AetherKit/`**, reinstall to refresh the installed tool:

```sh
swift package experimental-uninstall aether && swift package experimental-install
```

Notes:

- There is no test target in this package; behavior is verified by running the release binary against scratch documents (`.qwen/tmp/` in the repo root is git-ignored scratch space).
- **This README is generated by hand from real output.** Regenerate the transcript from a real run rather than writing plausible output; re-check it after any change to `describe()`.
- `AetherKit` is shared with the app target — schema/loader changes made for the CLI affect the app too. Validate app-side impact with `xcodebuild -project Aether.xcodeproj -scheme Aether -destination 'platform=macOS' build` from the repo root.
- The source file names literally contain `<T>` (`Count<T>.swift`, `Fetch<T>.swift`); that's intentional (generic commands), not a typo. Shell quoting of those paths needs the angle brackets quoted.
