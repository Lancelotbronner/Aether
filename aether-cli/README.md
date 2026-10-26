# aether — Aether project tool (CLI)

A terminal utility for working with **Aether project documents** (`.aetherproj`). The Aether IDE saves its documents as SwiftData stores; `aether` lets you create them, import Mach-O binaries into them, and query their contents (programs, segments, sections, strings) from the command line — no GUI required.

Use it to script around Aether documents, sanity-check a saved analysis, or inspect a document on a machine that can't run the app.

## Prerequisites

- **macOS 27** (the package declares `platforms: [.macOS(.v27)]`)
- **Swift 6.4 toolchain** (`swift-tools-version: 6.4`) — e.g. Xcode 26.x; verified with `Apple Swift version 6.4 (swiftlang-6.4.0.34.1)`

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

> **Staleness trap:** the installed binary is a snapshot. After editing anything under `Sources/` (or `AetherKit/`), re-run `experimental-uninstall` + `experimental-install`, or `aether --help` will keep advertising the old command tree.

## Commands

Every query command takes `--project <file>` (the `.aetherproj` document) and optionally `--limit`/`--offset`. In each model group `fetch` is the default subcommand, so `aether segment --project D` is the same as `aether segment fetch --project D`.

| Command | Purpose | Key flags |
| --- | --- | --- |
| `aether new <path>` | Create an empty project (appends `.aetherproj` if missing) | — |
| `aether import --project <p> <executable>` | Import a **thin 64-bit Mach-O** executable and parse it (segments, sections, symbols, strings) into the document | `--project` |
| `aether program [fetch]` | List programs (`BinaryModel` rows: name + persistent ID) | `--project`, `--limit`, `--offset` |
| `aether program count` | Count programs | same |
| `aether segment [fetch]` | List Mach-O segments (`__TEXT`, `__DATA`, …) | same |
| `aether segment count` | Count segments | same |
| `aether section [fetch]` | List sections (`__TEXT,__text`, …) | same |
| `aether section count` | Count sections | same |
| `aether string [fetch]` | List scanned strings (address + value, see caveat below) | same |
| `aether string count` | Count strings | same |

See `aether <command> --help` for the full help text of any command.

## Examples

The output below is captured verbatim from a real run.

### Create a project and import a binary

```
$ aether new ThinTest
Successfully created ThinTest.aetherproj

$ aether import --project ThinTest.aetherproj thin_test
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
Parsing 26 symbols
Parsed 26 symbols in 1 ms
Parsed 5 segments, 11 sections, 26 symbols, 1 strings in 2 ms
Successfully imported as PersistentIdentifier(id: SwiftData.PersistentIdentifier.ID(backing: SwiftData.PersistentIdentifier.PersistentIdentifierBacking.managedObjectID(0x941149142f241db6 <x-coredata://BDB005FB-4680-49CA-98A0-698AB943E0D8/BinaryModel/p1>))).
```

(`thin_test` here is a small single-architecture arm64 executable; the per-UUID identifier and timings will differ on your machine.)

### Query the document

```
$ aether program --project ThinTest.aetherproj
Showing 1 models:
thin_test
id: PersistentIdentifier(id: SwiftData.PersistentIdentifier.ID(backing: SwiftData.PersistentIdentifier.PersistentIdentifierBacking.managedObjectID(0x9b6dd3511ee2c1f5 <x-coredata://BDB005FB-4680-49CA-98A0-698AB943E0D8/BinaryModel/p1>)))

$ aether segment --project ThinTest.aetherproj
Showing 5 models:
__DATA_CONST
__PAGEZERO
__TEXT
__LINKEDIT
__DATA

$ aether section --project ThinTest.aetherproj
Showing 11 models:
__TEXT,__unwind_info
__TEXT,__text
__TEXT,__const
__TEXT,__swift5_typeref
__DATA_CONST,__objc_imageinfo
__TEXT,__stubs
__DATA,__common
__TEXT,__cstring
__DATA_CONST,__got
__DATA,__data
__TEXT,__swift5_entry

$ aether program count --project ThinTest.aetherproj
1
$ aether segment count --project ThinTest.aetherproj
5
$ aether section count --project ThinTest.aetherproj
11
$ aether string count --project ThinTest.aetherproj
1
```

`--limit`/`--offset` page through results:

```
$ aether segment --project ThinTest.aetherproj --limit 2 --offset 1
Showing 2 models:
__PAGEZERO
__TEXT
```

### Inspect an existing document

`~/Downloads/TF3.aetherproj` is a Transport Fever 3 document saved by the app:

```
$ aether program --project ~/Downloads/TF3.aetherproj
Showing 1 models:
TransportFever3
id: PersistentIdentifier(id: SwiftData.PersistentIdentifier.ID(backing: SwiftData.PersistentIdentifier.PersistentIdentifierBacking.managedObjectID(0x9d7f3784d0629102 <x-coredata://04A9E176-0527-49F4-A973-A8024C4E94A8/BinaryModel/p1>)))

$ aether segment count --project ~/Downloads/TF3.aetherproj
5
$ aether section count --project ~/Downloads/TF3.aetherproj
24
$ aether string count --project ~/Downloads/TF3.aetherproj
33622
```

### Error handling

`import` validates the header *before* saving, so a failed import leaves the document untouched:

```
$ aether import --project ThinTest.aetherproj notmacho.txt
Error: Not a Mach-O binary (magic 0x6c6c6568 — not a Mach-O header)

$ aether import --project ThinTest.aetherproj /bin/ls
Error: Unsupported binary: fat/universal Mach-O (magic 0xbebafeca) — thin images only

$ aether import --project ThinTest.aetherproj does-not-exist
Error: The file “does-not-exist” couldn’t be opened because there is no such file.
```

One quirk: a **nonexistent `--project` path is not an error** — SwiftData transparently creates an empty store there, and queries report `Showing 0 models:` (exit 0). Double-check the path if a document appears to be empty.

## Document format

An `.aetherproj` is a **plain directory** (a bundle; the UTType is `com.lancelotbronner.aetherproj`, `.package`-conforming) containing the SwiftData store:

```
MyDoc.aetherproj/
├── StoreContent              # SwiftData (CoreData/SQLite) store — the whole document
├── StoreContent-wal
├── StoreContent-shm
└── .StoreContent_SUPPORT/
```

- The CLI opens it with `ModelConfiguration(schema: .project, url: <doc>/StoreContent)` — the `.project` schema (the AetherKit model-type list) is defined in `AetherKit/Sources/AetherKit/Schema/`.
- The imported **binary's bytes live inside the store** (`BinaryModel.data`), not as a separate file in the bundle. The original path is kept in `BinaryModel.fileURL` for reference.
- Parsed children (`SegmentModel`, `SectionModel`, `SymbolModel`, `ProcedureModel`, `StringModel`) cascade from `BinaryModel`.
- **String values do not round-trip.** `StringModel.cached` (the display value) is `@Transient`, so after the importing process exits every string prints as `not loaded @<vaddr>` — the address is real, the value only existed in the context that scanned it. `string count` is reliable; `string fetch` is an address listing until this is fixed.

## Development

```sh
cd aether-cli
swift build            # debug build, no install
swift run aether --help
```

After any source edit to `aether-cli/` **or `AetherKit/`**, reinstall to refresh the installed tool:

```sh
swift package experimental-uninstall aether && swift package experimental-install
```

Notes:

- There is no test target in this package; behavior is verified by running the installed binary against scratch documents (`.qwen/tmp/` in the repo root is git-ignored scratch space).
- `AetherKit` is shared with the app target — schema/loader changes made for the CLI affect the app too. Validate app-side impact with `xcodebuild -project Aether.xcodeproj -scheme Aether -destination 'platform=macOS' build` from the repo root.
- The source file names literally contain `<T>` (`Count<T>.swift`, `Fetch<T>.swift`); that's intentional (generic commands), not a typo.
