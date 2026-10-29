# aether-cli — agent notes

Terminal tool for creating/inspecting Aether project documents (`.aetherproj`). This file is for AI agents working in this directory; `README.md` is the user-facing doc.

## Package layout

SwiftPM package `aether`, one executable target, no test target. `swift-tools-version: 6.4`, `platforms: [.macOS(.v27)]`, strict Swift 6 language mode is inherited from conventions but the target only enables `ApproachableConcurrency`.

| File | Role |
| --- | --- |
| `Sources/Aether.swift` | `@main` command tree (subcommands: program, section, segment, string, new, import) + `AetherOptions` — the shared `--project` option that lazily opens the document's `ModelContainer` from `<project>/StoreContent` (`try!`: a corrupt store crashes rather than throws). |
| `Sources/Fetch<T>.swift` | `FetchableModel` protocol (plural, `describe()`, `descriptor(using:)`) + generic `FetchCommand<Model>` (`fetch`, default subcommand of every group; `--limit`/`--offset`). |
| `Sources/Count<T>.swift` | Generic `CountCommand<Model>` (`count`; prints `fetchCount`). |
| `Sources/Program.swift` | `program` group; `BinaryModel: FetchableModel` (describe = name + persistent ID). |
| `Sources/Segment.swift` / `Section.swift` | `segment`/`section` groups; make the respective model `FetchableModel` (segment → `name`, section → `fullName`). Each group: `fetch` + `count`, `fetch` is default. |
| `Sources/String.swift` | `string` group — **not** a `FetchableModel` (the generic fetch can't express a filter): dedicated `StringFetchCommand`/`StringCountCommand` fetch `SymbolModel` and filter `type.isString` in memory (strings are symbol rows; decoded text in `stringValue`). Fetch prints `"\(stringValue) @\(address)"` sorted by address. |
| `Sources/New.swift` | `new <path>` — creates the bundle directory + an empty SwiftData store at `<path>/StoreContent`. Appends `.aetherproj` if the extension is missing. |
| `Sources/Import.swift` | `import <executable>` — reads the file into a `BinaryModel` (bytes stored in the store), runs `MachOLoader.load(_:)` from AetherKit, **then** saves. The load-before-save order is deliberate: the loader throws on bad input (so a failed import leaves no row) and nothing else in this path saves the parsed children. Don't reorder it back. |

File names `Count<T>.swift` / `Fetch<T>.swift` literally contain `<T>` — intentional.

## Build / install workflow

```sh
swift build                                  # check compiles
swift package experimental-uninstall aether  # required before reinstalling
swift package experimental-install           # installs to ~/.swiftpm/bin/aether
```

**Staleness trap:** `~/.swiftpm/bin/aether` is a snapshot. If `aether --help` doesn't match the source you just wrote, the installed binary is stale — do the uninstall+install cycle. Both `aether-cli/` and `AetherKit/` changes require it.

There are no tests; verify behavior by running the installed binary against scratch documents (use `.qwen/tmp/` at the repo root — git-ignored).

## Test documents

- **Create one:** `aether new .qwen/tmp/clidocs/Doc` then `aether import --project .qwen/tmp/clidocs/Doc.aetherproj <thin-mach-o>`.
- **Thin 64-bit Mach-O only.** The loader (`AetherKit/Sources/AetherKit/Load/MachOLoader.swift`) throws `BinaryLoaderError` for anything else — exact messages: `Not a Mach-O binary (magic 0x… — not a Mach-O header)`, `Unsupported binary: fat/universal Mach-O (magic 0x… — thin images only)`, `Unsupported binary: 32-bit Mach-O (…) — 64-bit only`. A smoke binary lives at `.qwen/tmp/thin_test`; recompile with `xcrun swiftc -target arm64-apple-macos14 -O -o .qwen/tmp/thin_test .qwen/tmp/thin_test.swift` if missing. `/bin/ls` is fat and will be rejected.
- A large real-world document (Transport Fever 3) was used as a read-only example but is no longer on disk; create a scratch document for behavior checks instead. The store is plain SQLite (`StoreContent`, tables `ZBINARYMODEL`, `ZSEGMENTMODEL`, …) — checkpoint the WAL (`PRAGMA wal_checkpoint(TRUNCATE);`) before hand edits.

## Conventions

- Tabs, not spaces.
- Swift 6 language mode; `AetherOptions.mainContext` is `@MainActor`, query commands fetch on a fresh background `ModelContext`.
- New query command = make a model conform to `FetchableModel`, then add `FetchCommand<X>`/`CountCommand<X>` to a group's `subcommands:` list (see `Program.swift`).
- Keep `aether-cli/` a sibling of `AetherKit/` — the manifest references it by relative path.
- Don't commit `Package.resolved` churn from builds unless the manifest itself changed.

## Pitfalls

- **AetherKit is shared with the app target.** The SwiftData schema (`AetherKit/Sources/AetherKit/Schema/`) and `MachOLoader` live there; CLI-facing changes affect the app too. App build gate: `xcodebuild -project Aether.xcodeproj -scheme Aether -destination 'platform=macOS' build` from the repo root (the project uses the single-file `project.xcproj` format — no `project.pbxproj`).
- **Strings are `SymbolModel` rows.** `MachOLoader.symbolize(in:)` generates them at import time from Mach-O section types; the decoded text is stored in `stringValue`, so values round-trip across reopens. Deleting `StringModel` was a destructive schema change — documents imported before it show 0 strings until re-imported (delete + `aether import` again).
- **A missing `--project` file is silently created** as an empty store by SwiftData — queries then report `Showing 0 models:` with exit 0. No error is raised.
- **The document is a directory**, not a file: `StoreContent` (+`-wal`/`-shm`, `.StoreContent_SUPPORT/`) is the whole document; the imported binary's bytes are inside the store (`BinaryModel.data`), the original path is only kept in `fileURL`.
- `AetherOptions.modelContainer` uses `try!` — schema/store corruption crashes the CLI instead of producing a clean error.
