# Aether

Aether is a Ghidra-style reverse engineering / decompilation IDE written in Swift. It is a document-based SwiftUI app (macOS / iPadOS / visionOS, deployment target 27.0) that loads Mach-O, ELF, PE, and JAR binaries, disassembles them with Capstone, and represents instructions as Ghidra-like p-code for analysis and decompilation.

This project was rescued from a botched AI-generated prototype.
The author is working to get it in a usable state.
As such many parts of the codebase are disconnected, duplicated or in-progress.

A migration from the god-model `AppState` + ad-hoc `Project` persistence to SwiftData documents is in progress on branch `experiment/swift-data`; the living plan is `PLAN.md` at the repo root.

## Repository Layout

| Path | What it is |
| --- | --- |
| `Aether.xcodeproj` | Xcode project using the new single-file `project.xcproj` format (Xcode 26+). Do not look for `project.pbxproj`. |
| `Aether/` | The app target (SwiftUI). |
| `AetherKit/` | Swift package (`swift-tools 6.4`, macOS 27+, Swift 6 language mode). Shared IR + plugin + utility code; also hosts the SwiftData document schema (`Sources/AetherKit/Schema/`), the model-based Mach-O loader (`Sources/AetherKit/Load/MachOLoader.swift`), and the former `CoreAether` C target (absorbed — standalone dir deleted). |
| `aether-cli/` | Swift package (`swift-tools 6.4`, macOS 27). The `aether` terminal tool for `.aetherproj` documents: `new`, `import`, and `program`/`segment`/`section`/`string` groups (each with `fetch` + `count`). See `aether-cli/README.md`. |
| `DerivedData/` | Build artifacts (not source). |
| `PLAN.md` | Living plan to complete the SwiftData migration (current state, ordered tasks, progress log). |

### App target (`Aether/`)

- `Scene/` — `AetherScene` is a `DocumentGroup` built on the private `_SwiftData_SwiftUI` bridge (`editing: .project`, per-document `ModelContainer`, built-in autosave); `prepareDocument` is empty — file entry is the `AetherCommands` "Import Binary..." (⇧⌘O) `fileImporter`, which creates a `BinaryModel` (file bytes + URL + name) and inserts it, and the Programs navigator's "Load..." context menu then parses it via `MachOLoader.load(_:)`. `AetherRootView` owns a per-window `@State session = AppState()` (selection, transient state, UI flags, services) injected into the environment. Commands, toolbar, sidebar in the same folder.
- `Schema/` — the SwiftData models, `UTType.project` (`.package`-conforming, `com.lancelotbronner.aetherproj`), and the `Array<any PersistentModel.Type>.project` model-type list now live in `AetherKit/Sources/AetherKit/Schema/` (shared with `aether-cli`): `BinaryModel` (file bytes + `baseAddress`), `SegmentModel`, `SectionModel`, `SymbolModel`, `ProcedureModel`/`BlockModel`, `StringModel` with `@Transient cached`, `AnnotationModel`, `CrossReferenceModel`, `BookmarkModel`. Procedure/Block/String/XRef models are *not* in that list — they are reachable via the `BinaryModel` cascade.
- `Models/` — `AppState` (per-window session: model-based selection, transient caches, UI flags, services, ~25 stubbed analysis methods, dict-based renames/comments/bookmarks), `Architecture`, `BinaryFile`, `Disassembly`, `Function`, `Instruction`, `Project`, `Symbol` — the last five are legacy god-model types still consumed by the analyzers/decompiler.
- `Core/Binary/` — Loaders: `MachOLoader` (the model-based path `machO(for: BinaryModel)` moved to `AetherKit/Sources/AetherKit/Load/MachOLoader.swift`; the app-side file keeps only the legacy `BinaryFile`-returning path), `ELFLoader`, `PELoader`, `JARLoader`, plus `BinaryLoader`/`BinaryPatcher`.
- `Core/Disassembler/` — `DisassemblerEngine` (actor) drives Capstone via `CapstoneDisassembler`; `JavaDisassembler` handles JVM bytecode; `DisassemblerPlugin` is the extension point. `Instruction` values carry a p-code range (`pcode: Range<Int>`).
- `Core/Decompiler/` — `Decompiler.swift`, `JavaDecompiler.swift`.
- `Core/Analysis/` — ~20 analyzers (xrefs, data flow, control-flow structuring, crypto/malware/packer detection, deobfuscation, DWARF, ObjC/Swift analysis, entropy, signatures, strings, type recovery, IoC extraction, AI annotation).
- `Core/Emulation/Emulator.swift`.
- `Navigator/` — sidebar panes: Exports, Functions, Imports, Sections, Strings, Symbols.
- `Inspector/`, `UI/`, `Settings/`, `Services/` (AI client, export, Frida script generation, plugin system, scripting engine).

### AetherKit package

- `Sources/AetherKit/Pcode/` — Ghidra-like p-code IR: the `Pcode` enum (copy/load/store, goto/branch/call, int & FP arithmetic, comparisons, zext/sext/concat), `Varnode`, `Address`/`AddressSpaceId` (space kind bits: special/memory/register, e.g. `.const`, `.stack`, `.mem`, `.reg`), and `Context` (`ContextVariable` with `ContiguousMask` bit-field masks).
- `Sources/AetherKit/Schema/` — the SwiftData document schema shared by the app target and `aether-cli` (model types, `UTType.project`, `.project` model-type list).
- `Sources/AetherKit/Load/` — model-based `MachOLoader` (`machO(for: BinaryModel)` / `load(_:)`); thin 64-bit Mach-O only, typed `BinaryLoaderError`.
- `Sources/AetherKit/Plugin/` — `AetherPlugin` protocol and plugin load/open support.
- `Sources/AetherKit/Utilities/` — `Rc` (reference counting), `Cow`, `ContiguousMask`, `Size`.
- `Sources/AetherKit/Extensions/Swift+.swift` — Swift standard-library extensions.
- `Sources/CoreAether/` — the former standalone `CoreAether` package, absorbed (C2X): Mach-O N-stab / `nlist` definitions in `include/CoreAether/mach-o.h`; `aether.h` is a stub.
- Tests use the `swift-testing` framework (`Tests/Tests.swift`, scheme `AetherTests`); `CoreAetherTests` covers the C target.
- Dependency: `Zip` (`tomasf/Zip`) — the argument-parser / case-accessors / swift-syntax pins were dropped when `aether-cli` became its own package.

### Key project dependencies

- `CapstoneKit` from the author's fork `github.com/Lancelotbronner/capstone` (branch `next`) — only adds SwiftPM build support.
- `Zip` from `tomasf/Zip` — now `AetherKit`'s only external dependency (argument-parser / case-accessors / swift-syntax pins dropped).
- `aether-cli` additionally uses `swift-argument-parser` (1.8.2+) and the local `AetherKit` package by relative path.
- `Cartograph` aggregate target runs `/opt/homebrew/bin/cartograph check --report-format xcode` as a build-time check; reports unused code.

## Building and Running

- **Xcode (preferred):** open `Aether.xcodeproj`, scheme **Aether**, run on "My Mac". Other schemes: `CoreAether`, `Tests` (CoreAether tests), `AetherKit`, `AetherTests`, `Cartograph`.
- **CLI build:**
  ```sh
  xcodebuild -project Aether.xcodeproj -scheme Aether -destination 'platform=macOS' build
  ```
- **Package tests:**
  ```sh
  cd AetherKit && swift test   # AetherKit + absorbed CoreAether targets
  ```
- **CLI (`aether-cli/`):**
  ```sh
  cd aether-cli
  swift build
  swift package experimental-install        # → ~/.swiftpm/bin/aether
  swift package experimental-uninstall aether
  ```
  The installed binary is a snapshot — reinstall after any edit to `aether-cli/` or `AetherKit/`. See `aether-cli/README.md`.
- There is no CI configuration or README in the repo.

## Development Conventions

- **Indentation:** tabs, not spaces.
- **Concurrency:** app target uses Swift 5 mode with `SWIFT_APPROACHABLE_CONCURRENCY`, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, and the experimental `Lifetimes` feature; packages use strict Swift 6 language mode with `Sendable` types everywhere. Engines (e.g. `DisassemblerEngine`) are `actor`s. Migration to Swift 6 is in progress.
- **Style:** `@inlinable` on hot IR accessors, `Rc` for reference-counted shared state (`~Copyable` structs), `nonisolated` for background-context types.
- **Sandbox:** app is sandboxed with user-selected file read/write, no network connections — external services (e.g. `AIClient`) go through the `Services/` layer.

## Git Context

- `main` — current work: hand-rolled p-code IR in AetherKit, Capstone disassembly pipeline.
- `experiment/swift-data` — SwiftData document migration (unattended agent pipeline; see PLAN.md).
- `experimental/cli` — merged into `experiment/swift-data` 2026-10-26 (commit `3e1968e`): added `aether-cli/`, moved the SwiftData schema + model-based Mach-O loader into `AetherKit`, absorbed the `CoreAether` package into `AetherKit`.
- `experiment/ghidra` — experiments converting Ghidra Sleigh `.sla` files into the p-code system (see `d5e6dcd` "More progress on Ghidra-like pcode system from SLA"). The author also studies Ghidra's Sleigh decision-tree resolution (`DecisionNode`) for constructor selection; frame Sleigh-related discussion in terms of compile-time tree construction (`DecisionNode::split`, `chooseOptimalField`) vs. runtime walking (`DecisionNode::resolve` via `Sleigh::resolve`). Note the Sleigh *compiler* C in Ghidra is generated from `slghparse.y` at build time.
