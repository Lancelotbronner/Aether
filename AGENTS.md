# Aether

Aether is a Ghidra-style reverse engineering / decompilation IDE written in Swift. It is a document-based SwiftUI app (macOS / iPadOS / visionOS, deployment target 27.0) that loads Mach-O, ELF, PE, and JAR binaries, disassembles them with Capstone, and represents instructions as Ghidra-like p-code for analysis and decompilation.

This project was rescued from a botched AI-generated prototype.
The author is working to get it in a usable state.
As such many parts of the codebase are disconnected, duplicated or in-progress.

## Repository Layout

| Path | What it is |
| --- | --- |
| `Aether.xcodeproj` | Xcode project using the new single-file `project.xcproj` format (Xcode 26+). Do not look for `project.pbxproj`. |
| `Aether/` | The app target (SwiftUI). |
| `AetherKit/` | Swift package (`swift-tools 6.3`, macOS 26+, Swift 6 language mode). Shared IR + plugin + utility code. |
| `CoreAether/` | C/C++ Swift package (`swift-tools 6.4`, C2X). Mach-O N-stab / `nlist` definitions in `Sources/include/CoreAether/mach-o.h`; `aether.h` is a stub. |
| `DerivedData/` | Build artifacts (not source). |

### App target (`Aether/`)

- `Scene/` — `AetherScene` is a `DocumentGroup` over `ProjectDocument` (`Document/`); commands, toolbar, sidebar in the same folder.
- `Models/` — `AppState`, `Architecture`, `BinaryFile`, `Disassembly`, `Function`, `Instruction`, `Project`, `Symbol`.
- `Core/Binary/` — Loaders: `MachOLoader`, `ELFLoader`, `PELoader`, `JARLoader`, plus `BinaryLoader`/`BinaryPatcher`.
- `Core/Disassembler/` — `DisassemblerEngine` (actor) drives Capstone via `CapstoneDisassembler`; `JavaDisassembler` handles JVM bytecode; `DisassemblerPlugin` is the extension point. `Instruction` values carry a p-code range (`pcode: Range<Int>`).
- `Core/Decompiler/` — `Decompiler.swift`, `JavaDecompiler.swift`.
- `Core/Analysis/` — ~20 analyzers (xrefs, data flow, control-flow structuring, crypto/malware/packer detection, deobfuscation, DWARF, ObjC/Swift analysis, entropy, signatures, strings, type recovery, IoC extraction, AI annotation).
- `Core/Emulation/Emulator.swift`.
- `Navigator/` — sidebar panes: Exports, Functions, Imports, Sections, Strings, Symbols.
- `Inspector/`, `UI/`, `Settings/`, `Services/` (AI client, export, Frida script generation, plugin system, scripting engine).

### AetherKit package

- `Sources/Pcode/` — Ghidra-like p-code IR: the `Pcode` enum (copy/load/store, goto/branch/call, int & FP arithmetic, comparisons, zext/sext/concat), `Varnode`, `Address`/`AddressSpaceId` (space kind bits: special/memory/register, e.g. `.const`, `.stack`, `.mem`, `.reg`), and `Context` (`ContextVariable` with `ContiguousMask` bit-field masks).
- `Sources/Plugin/` — `AetherPlugin` protocol and plugin load/open support.
- `Sources/Utilities/` — `Rc` (reference counting), `Cow`, `ContiguousMask`, `Size`.
- `Sources/Extensions/Swift+.swift` — Swift standard-library extensions.
- Tests use the `swift-testing` framework (`Tests/Tests.swift`, scheme `AetherTests`).
- Dependencies: `swift-argument-parser`, `swift-case-accessors` (author's own package), `swift-syntax` — evidence of CLI/code-generation tooling.

### Key project dependencies

- `CapstoneKit` from the author's fork `github.com/Lancelotbronner/capstone` (branch `next`) — only adds SwiftPM build support.
- `Zip` from `tomasf/Zip`.
- `Cartograph` aggregate target runs `/opt/homebrew/bin/cartograph check --report-format xcode` as a build-time check; reports unused code.

## Building and Running

- **Xcode (preferred):** open `Aether.xcodeproj`, scheme **Aether**, run on "My Mac". Other schemes: `CoreAether`, `Tests` (CoreAether tests), `AetherKit`, `AetherTests`, `Cartograph`.
- **CLI build:**
  ```sh
  xcodebuild -project Aether.xcodeproj -scheme Aether -destination 'platform=macOS' build
  ```
- **Package tests:**
  ```sh
  cd AetherKit && swift test
  cd CoreAether && swift test
  ```
- There is no CI configuration or README in the repo.

## Development Conventions

- **Indentation:** tabs, not spaces.
- **Concurrency:** app target uses Swift 5 mode with `SWIFT_APPROACHABLE_CONCURRENCY`, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, and the experimental `Lifetimes` feature; packages use strict Swift 6 language mode with `Sendable` types everywhere. Engines (e.g. `DisassemblerEngine`) are `actor`s. Migration to Swift 6 is in progress.
- **Style:** `@inlinable` on hot IR accessors, `Rc` for reference-counted shared state (`~Copyable` structs), `nonisolated` for background-context types.
- **Sandbox:** app is sandboxed with user-selected file read/write, no network connections — external services (e.g. `AIClient`) go through the `Services/` layer.

## Git Context

- `main` — current work: hand-rolled p-code IR in AetherKit, Capstone disassembly pipeline.
- `experiment/ghidra` — experiments converting Ghidra Sleigh `.sla` files into the p-code system (see `d5e6dcd` "More progress on Ghidra-like pcode system from SLA"). The author also studies Ghidra's Sleigh decision-tree resolution (`DecisionNode`) for constructor selection; frame Sleigh-related discussion in terms of compile-time tree construction (`DecisionNode::split`, `chooseOptimalField`) vs. runtime walking (`DecisionNode::resolve` via `Sleigh::resolve`). Note the Sleigh *compiler* C in Ghidra is generated from `slghparse.y` at build time.
