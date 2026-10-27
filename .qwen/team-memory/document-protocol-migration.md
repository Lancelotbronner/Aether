---
name: document-protocol-migration
description: State of Aether's SwiftData document migration (branch experiment/swift-data) — verified at 1c51b64, 12-task PLAN.md, bug list B1–B12; post-experimental/cli-merge layout (schema/loader in AetherKit, aether-cli)
type: project
category: project_introduction
keywords:
  - "DocumentGroup modelTypes"
  - "_SwiftData_SwiftUI ModelDocument"
  - "Aether Schema.swift models"
  - "AppState session split"
  - "aetherproj package format"
usage_scenarios:
  - "Touching the Aether scene or document layer"
  - "Deciding where data persists (SwiftData vs session)"
  - "Planning UI migration of a specific view"
---

SwiftData `DocumentGroup` migration (branch `experiment/swift-data`) verified against code at `1c51b64` (2026-10-26, Agent 1 exploration):

- `AetherScene` uses the private `_SwiftData_SwiftUI` bridge: `editing: .project`, per-document `ModelContainer`, autosave. `prepareDocument` is empty — file entry is the AetherCommands "Import Binary..." (⇧⌘O) `fileImporter` creating a `BinaryModel`, then ProgramNavigator "Load..." → `MachOLoader.load(_:)`. `AetherRootView` owns per-window `@State session = AppState()`.
- All six sidebar tabs are `@Query`-based; `DisassemblyView` is model-driven; `AppState` is a hybrid (model selection adopted; `currentFile` never set → toolbar cluster permanently disabled; ~25 stubbed methods; renames/comments/bookmarks in dicts; caches never populated).
- `.project` model list = [Binary, Segment, Section, Symbol, Annotation, Bookmark]; Procedure/Block/String/XRef ride the BinaryModel cascade.
- **Bug list B1–B12 is in PLAN.md** (all code-verified): B1 LC_SYMTAB stroff/symoff applied to command-relative stream (names garbage), B2 `symbol.size` never assigned (functions disassemble to one byte), B3 fat/32-bit/non-Mach-O → fatalError + no re-parse guard, B4 G1 remnant (sectionNavigator), B5 D11 (clearDisassemblyCache), B6 toolbar currentFile gates, B7 CFG button → analyzeAll, B8 BinaryModel read(at:) raw offsets, B9 HexView whole-file slice, B10 dead operand caches, B11 StringModel.cached never populated, B12 search filters commented out.
- **Dead code (grep-verified):** ProjectManager, ExportService, Project struct, AppState persistence tail (saveProject/etc + ProjectData/PatchData). `Bookmark` struct LIVE (AppState dict). `ExportManager` (Services/) is the live exporter.
- `DisassemblerEngine` is model-agnostic (`disassemble(data:address:architecture:)`) — no port needed.
- Build baseline 2026-10-26: xcodebuild Aether SUCCEEDED (12.3 s, capstone warnings only); AetherKit + CoreAether `swift test` pass with **0 test cases** (no automated coverage).

**Post-merge layout update (2026-10-26, `experimental/cli` merged at `3e1968e`):** the SwiftData schema moved `Aether/Schema/Schema.swift` → `AetherKit/Sources/AetherKit/Schema/` (split into Schema/Arch/Document files); the model-based `MachOLoader` (`machO(for:)`/`load(_:)`) lives at `AetherKit/Sources/AetherKit/Load/MachOLoader.swift` (app-side `Aether/Core/Binary/MachOLoader.swift` keeps only the legacy `BinaryFile` path); `CoreAether/` was absorbed into `AetherKit` (standalone dir deleted; C target + tests now `AetherKit/Sources/CoreAether/`). New `aether-cli/` package (terminal tool for `.aetherproj`: new/import/program/segment/section/string, each fetch+count) — docs in `aether-cli/README.md` + `aether-cli/AGENTS.md`. B1/B2/B3 from the bug list are fixed in the moved loader (stroff/symoff absolute, size derivation, thin-64-bit gate + idempotent re-parse). Agent 12 also fixed CLI bugs: `count` subcommand was unreachable (registered as a second `fetch`) and `aether import` now loads *before* saving so parsed children persist and failed imports leave no row.

**The running plan is `PLAN.md` at repo root** — rewritten 2026-10-26 as a definitive 12-task ordered plan (LC_SYMTAB fix → loader robustness → session fixes → D11 → modelize annotations → strings → search → decompiler → HexView reads → operand resolution → schema housekeeping/dead-code deletion → analyzer conversion). Each task has files/steps/acceptance + build step; Progress log at the end; per-agent handoffs in `.qwen/handoffs/NN-slug.md`; orchestrator commits between agents. Old phase-based plan and SwiftUI.md were deleted from root in `1c51b64`; recovered copies at `.qwen/tmp/PLAN.md.prev` / `SwiftUI.md.prev`, findings folded into the new PLAN.md.

**Why:** the app is a rescued prototype; the god-model AppState blocked the document layer.
**How to apply:** for any migration work, read PLAN.md's "Current state" + bug table + the task for the view/file you touch, and the latest `.qwen/handoffs/` file for context.
