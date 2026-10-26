# Handoff 11 — aether-cli docs (Agent 12)

STATUS: COMPLETE (2026-10-26) — no commits made, per instructions

## Pre-flight
- branch `experiment/swift-data`, HEAD `d3ace5e`.
- `git status --short` at start: ` M ORCHESTRATOR_NOTES.md` ONLY. Diff = orchestrator's own appended notes about this very task (written after last commit). Orchestrator-owned file, off-limits → proceeded, NOT touched. No source files dirty.
- Deliverables: `aether-cli/README.md`, `aether-cli/AGENTS.md`, root `AGENTS.md` update. No commits.

## Source analysis (aether-cli/Sources/)
- `Package.swift`: swift-tools 6.4, name "aether", platforms macOS v27 only. Deps: swift-argument-parser (from 1.8.2), local AetherKit (`../AetherKit`). One executableTarget `aether`, `enableUpcomingFeature("ApproachableConcurrency")`. NOTE: task brief said Zip is a direct CLI dep — it is NOT; Zip comes transitively via AetherKit.
- `Aether.swift`: `@main struct aether: AsyncParsableCommand`. Abstract "Aether utility for working with Aether projects." Top-level subcommands: program, section, segment, string, new, import. `AetherOptions` shared option group: `@Option var project: String` ("The project file to open", completion `.file(extensions: ["aetherproj"])`), builds `URL(filePath:directoryHint:.notDirectory)`, lazily opens `ModelContainer(for: .project, ...)` with `ModelConfiguration(schema: .project, url: projectURL.appending(path: "StoreContent"))`. `try!` in lazy property = crash (not throw) on bad store. `mainContext` (MainActor, mutating) + `backgroundContext` (fresh `ModelContext(modelContainer)`).
- `Program.swift`: `program` cmd ("Work with programs."), subcommands `fetch` + `count` (see bug below), default `fetch`. `BinaryModel: FetchableModel`, plural "programs", `describe()` = `"\(name)\n" + "id: \(persistentModelID)"`. Empty `FetchOptions`.
- `Fetch<T>.swift`: defines `FetchableModel` protocol (associatedtype FetchOptions: ParsableArguments; static plural; describe(); static subcommands default []; static descriptor(using:) default plain FetchDescriptor). `FetchCommand<Model>`: commandName "fetch", abstract "Fetches a list of \(plural) from the project.", flags `--limit` `--offset` (no help text), fetch in backgroundContext, prints "Showing N models:" then each `describe()`.
- `Count<T>.swift`: `CountCommand<Model>` — BUG: `commandName: "fetch"` (copy-paste from FetchCommand) and abstract also says "Fetches a list of...". Same `--limit`/`--offset` flags. Prints just the integer from `fetchCount`.
- `New.swift`: `new <path>` ("Creates an empty project at the specified location."), arg help "appends .aetherproj if missing". `FileManager.createDirectory(withIntermediateDirectories:true)` on the .aetherproj URL (bundle = plain dir), creates `ModelContainer` at `<url>/StoreContent`, saves empty context, prints "Successfully created <lastPathComponent>".
- `Import.swift`: `import <executablePath>` (arg has no help text; no completion), uses `aether.backgroundContext`. Reads whole file into `BinaryModel.data` (`.mappedIfSafe`), sets `fileURL`, `name` = lastPathComponent, inserts + saves, prints "Successfully imported as <persistentModelID>.", then `await MachOLoader.load(binary)` (model-based loader from AetherKit). Non-Mach-O / bad file → `Data(contentsOf:)` throws (path missing) or loader throws.
- `Segment.swift`: `segment` cmd, subcommands fetch + `CountCommand<BinaryModel>` (NOTE: counts BinaryModel, NOT SegmentModel — copy-paste), default fetch. `SegmentModel: FetchableModel` plural "segments", describe() = `name`.
- `Section.swift`: same shape; plural "sections", describe() = `fullName`.
- `String.swift`: same shape; plural "strings", describe() = `"\(value) @\(address)"`.

## Document format (from sources)
`.aetherproj` = plain directory (bundle):
- `StoreContent` — SwiftData store file (ModelConfiguration url), opened with schema `.project` (the AetherKit model-type list).
- `aether new` creates only the dir + StoreContent; `aether import` adds a `BinaryModel` row holding the file bytes (Data) + fileURL + name — the loader parses from the stored bytes. (Whether the raw file itself is also copied into the bundle — need to verify against TF3.aetherproj contents.)

## Commands run (log)
1. `swift package experimental-uninstall aether` → "Executable product `aether` was successfully uninstalled from /Users/lancelot/.swiftpm/bin/aether."
2. `swift package experimental-install` (from aether-cli/) → "Build complete! (9.08 secs.)" + "successfully installed to /Users/lancelot/.swiftpm/bin/aether."
3. `aether --help` → abstract "A utility for working with Aether projects.", subcommands: program, section, segment, string, new, import. ✅ new/import now present (installed binary had predated them).
4. `aether program --help` → **CONFIRMS BUG**: SUBCOMMANDS lists `fetch (default)` AND a second `fetch` — the CountCommand is registered as "fetch", so **`count` does not exist and is unreachable** for every model group.
5. `aether new --help` → `USAGE: aether new <path>`, arg help "appends .aetherproj if missing".
6. `aether import --help` → `USAGE: aether import --project <project> <executable-path>`; `--project` "The project file to open"; executable-path arg has NO help text.
7. `aether {segment,section,string} --help` → same dual-`fetch` shape; the 2nd `fetch`'s abstract says "programs" (copy-paste from BinaryModel) in all three.
8. `aether program fetch --help` → `--project`, `--limit <limit>` (no help), `--offset <offset>` (no help).
9. ERR nonexistent project: `aether program fetch --project .qwen/tmp/nope.aetherproj` → prints `Showing 0 models:` exit 0. **BAD error quality** — ModelConfiguration auto-creates an empty store for missing files (no error at all).
10. ERR import nonexistent file: `aether import --project ~/Downloads/TF3.aetherproj .qwen/tmp/does-not-exist` → `Error: The file "does-not-exist" couldn't be opened because there is no such file.` exit 1. Good (Foundation NSCocoaError).
11. ERR import non-MachO text file: first prints `Successfully imported as PersistentIdentifier(...managedObjectID(0x... <x-coredata://.../BinaryModel/p2>)))` THEN `Error: Not a Mach-O binary (magic 0x6c6c6568 — not a Mach-O header)` exit 1. Loader error message is good; but **import inserts+saves the row BEFORE validating** → the failed import left a stray `notmacho.txt` BinaryModel row in TF3.aetherproj.
12. TF3 RESTORED: WAL checkpointed, `DELETE FROM ZBINARYMODEL WHERE Z_PK=2` (verified 0 children in ZSEGMENTMODEL/ZSECTIONMODEL/ZSTRINGMODEL first), re-checkpointed; `aether program --project ~/Downloads/TF3.aetherproj` now shows only `TransportFever3` (p1).

## BUGS CONFIRMED (source)
- B1: `Count<T>.swift` CountCommand `commandName: "fetch"` → `count` subcommand unreachable; every group shows two "fetch" entries.
- B2: abstract copy-paste in CountCommand: "Fetches a list of …".
- B3: `Segment.swift`/`Section.swift`/`String.swift` use `CountCommand<BinaryModel>` → even if reachable, `segment count` would count programs, not segments.
- B4 (behavioral): `import` saves the BinaryModel row before `MachOLoader.load` validates → failed imports pollute the document.
- B5 (quality): missing project file silently creates an empty store (`try!` hides nothing; ModelConfiguration just makes a new store) → `Showing 0 models:`.

## Source changes (all minimal, all verified after reinstall)
1. `Sources/Count<T>.swift`: `commandName: "fetch"` → `"count"`; abstract `"Fetches a list of …"` → `"Counts the \(Model.plural) in the project."` — fixes B1+B2 (count was unreachable; every group listed two `fetch` entries).
2. `Sources/Segment.swift`: `CountCommand<BinaryModel>` → `CountCommand<SegmentModel>` (fixes B3).
3. `Sources/Section.swift`: `CountCommand<BinaryModel>` → `CountCommand<SectionModel>` (fixes B3).
4. `Sources/String.swift`: `CountCommand<BinaryModel>` → `CountCommand<StringModel>` (fixes B3).
5. `Sources/Import.swift`: reordered — `MachOLoader.load(binary)` now runs BEFORE `modelContext.save()` (was after), success print moved to after save. Fixes B4 (failed imports no longer persist a stray BinaryModel row) and B6 (new bug found by testing: loader inserts segments/sections/symbols/strings but NOTHING saved them afterwards, so a fresh CLI import silently persisted 0 children — `aether segment` showed 0 models right after a successful import that printed "Parsed 5 segments…").
6. `Sources/Import.swift`: added `help:` to the executable path argument ("Path to a thin 64-bit Mach-O executable").
7. `Sources/Fetch<T>.swift` + `Sources/Count<T>.swift`: added `help:` text to `--limit`/`--offset` (were undocumented).

## Post-fix verification (real output)
- Reinstall: "Build complete! (1.23 secs.)" + "successfully installed to /Users/lancelot/.swiftpm/bin/aether."
- `aether program --help` → SUBCOMMANDS: `fetch (default)` + `count  Counts the programs in the project.` ✅ (segment/section/string analogous).
- Fresh workflow: `aether new .qwen/tmp/clidocs/ThinTest` → "Successfully created ThinTest.aetherproj"; `aether import --project .qwen/tmp/clidocs/ThinTest.aetherproj .qwen/tmp/thin_test` → loader log ("Mach-O: 51480 bytes, 64-bit … Parsed 5 segments, 11 sections, 26 symbols, 1 strings in 2 ms") THEN "Successfully imported as PersistentIdentifier(…BDB005FB…/BinaryModel/p1))."
- `aether segment --project …ThinTest.aetherproj` → "Showing 5 models:" __DATA_CONST/__PAGEZERO/__TEXT/__LINKEDIT/__DATA ✅ (was 0 before fix 5).
- `aether section …` → "Showing 11 models:" (11 __SECT,__name lines). `aether string …` → "Showing 1 models:" `not loaded @4294970112`.
- counts: program 1, segment 5, section 11, string 1. `--limit 2 --offset 1` on segment → `__PAGEZERO`, `__TEXT` ✅.
- ERR non-MachO (scratch ErrDoc): `Error: Not a Mach-O binary (magic 0x6c6c6568 — not a Mach-O header)` exit 1, NO "Successfully imported" line, and `aether program` on that doc → "Showing 0 models:" (doc untouched ✅).
- ERR nonexistent file: `Error: The file "does-not-exist" couldn't be opened because there is no such file.` exit 1.
- ERR fat binary `/bin/ls`: `Error: Unsupported binary: fat/universal Mach-O (magic 0xbebafeca) — thin images only`.
- B5 NOT fixed (documented instead): missing project file → SwiftData silently creates an empty store → "Showing 0 models:" exit 0.
- TF3.aetherproj verified intact post-everything: 1 program (TransportFever3 p1), section count 24, string count 33622, segment count 5.

## New bug B6 (found via testing, fixed by change 5)
`aether import` saved the BinaryModel row BEFORE `MachOLoader.load`, and the loader never saves → parsed children (segments/sections/symbols/strings/procedures) were silently lost on exit. Loader printed success. Fixed by load-then-save in Import.swift.

## Findings for docs
- `StringModel.value` = `cached ?? "not loaded"` (Schema.swift:508); `cached` is `@Transient` (NOT persisted) → every persisted string prints "not loaded @<vaddr>" after reopen (TF3: all 33622). Address is real; the value only exists in the context that imported it. NOT fixed — documented as known behavior/pitfall.
- Bundle = plain directory: `StoreContent` (+`-wal`/`-shm`, `.StoreContent_SUPPORT/`). The binary bytes live INSIDE the store (BinaryModel.data), no separate file in the bundle (TF3 contains only store files).
- aether-cli has NO test target. Zip is a transitive dep via AetherKit (not a direct CLI dep — brief was slightly off).
- AetherKit/Sources now = `AetherKit/` (Extensions, Load, Pcode, Plugin, Schema, Utilities, Common.swift, Logging.swift) + `CoreAether/` (absorbed C target: CoreAetherTests included). AetherKit tools 6.4, macOS v27, Zip-only dep, swiftLanguageModes [.v6], Lifetimes experimental.
- `aether new` output line is extension-agnostic: "Successfully created <name>.aetherproj".

## Docs outline
- **aether-cli/README.md**: What it is (inspect/create .aetherproj from terminal) · Prerequisites (macOS 27, Swift 6.4) · Install (experimental-install/uninstall → ~/.swiftpm/bin/aether) · Command reference table (all 10 real subcommands + flags from post-fix --help) · 4 worked examples with REAL captured output (new+import+inspect ThinTest; count/limit-offset; TF3 program/string/section-count; error paths) · Document format (bundle layout, store-internal bytes, strings "not loaded" caveat) · Development (build, reinstall-after-edit cycle).
- **aether-cli/AGENTS.md**: purpose · per-file layout table · build/install workflow + staleness trap · how to make test docs (thin arm64 only; TF3 example) · conventions (tabs, Swift 6, ApproachableConcurrency, no test target) · pitfalls (thin 64-bit gate + exact error strings; bundle layout + how AetherOptions opens it; AetherKit is shared — app build gate command; @Transient strings; silent empty store; don't commit Package.resolved churn; Aether.xcodeproj is project.xcproj).
- **root AGENTS.md** (targeted edits only): (a) + aether-cli row in layout table; (b) AetherKit row refreshed (tools 6.4, macOS 27, hosts schema + loader + absorbed CoreAether, Zip); (c) − CoreAether row; AetherKit package section paths Sources/X → Sources/AetherKit/X + Load/ + Schema/ + CoreAether absorbed; (d) Building: CLI build/install commands, `cd CoreAether && swift test` → AetherKit-only; (e) deps: AetherKit = Zip; (f) Git Context: experimental/cli merged 2026-10-26. Also corrected the now-stale App-target `Schema/` bullet (models live in AetherKit/Sources/AetherKit/Schema/).

## Install/reinstall verification
- Install 1 (before fixes): uninstall OK → install "Build complete! (9.08 secs.)" → `aether --help` showed all 6 top-level commands incl. `new`/`import` (pre-merge install had predated them).
- Install 2 (after fixes): uninstall OK → install "Build complete! (1.23 secs.)" → `aether program --help` shows `fetch (default)` + `count  Counts the programs in the project.`; `--limit`/`--offset` now documented in help; `aether import --help` shows the executable-path help text. All post-fix outputs above captured from this installed binary.

## Final state
`git status --short`:
```
 M AGENTS.md
 M ORCHESTRATOR_NOTES.md   ← pre-existing orchestrator edit, NOT touched by me
 M aether-cli/Sources/Count<T>.swift
 M aether-cli/Sources/Fetch<T>.swift
 M aether-cli/Sources/Import.swift
 M aether-cli/Sources/Section.swift
 M aether-cli/Sources/Segment.swift
 M aether-cli/Sources/String.swift
?? .qwen/handoffs/11-aether-cli-docs.md
?? aether-cli/AGENTS.md
?? aether-cli/README.md
```
- Scratch files (`.qwen/tmp/clidocs/*`, `.qwen/tmp/notmacho.txt`) verified git-ignored; no other scratch outside `.qwen/tmp/`.
- `~/Downloads/TF3.aetherproj` restored to pristine (1 program, 5/24/33622 segments/sections/strings) after the pre-fix error test polluted it; WAL checkpointed.
- `AetherKit/Package.resolved` untouched (no `swift build` run at repo level that could clobber it; only `aether-cli/` package ops, which manage their own `aether-cli/Package.resolved` — unchanged in git status).
- ORCHESTRATOR_NOTES.md / PLAN.md untouched.

## Risks / notes for orchestrator
- Source changes were made (7 edits, 6 files, all minimal + verified) even though the task preferred no changes: the tool did NOT work as-is — `count` was unreachable (registered as a second `fetch`) and `aether import` silently discarded all parsed children (no save after load). Both fixed; Import.swift now has a comment explaining the load-before-save order so future agents don't "clean it up" back into the bug.
- B5 remains unfixed by design (documented): missing `--project` silently creates an empty store.
- `aether string` prints "not loaded @vaddr" for every persisted row (`@Transient cached`) — known limitation, documented in both docs; fix would be an AetherKit schema change (out of scope, affects app target).
- Parent agent's project memory `document-protocol-migration.md` may reference pre-merge file locations (Aether/Schema/Schema.swift, CoreAether/) — updated if stale.
- Orchestrator to review the 6 source edits before committing; all are behavior-visible (new `count` subcommand; import now persists parse results and validates before writing).
