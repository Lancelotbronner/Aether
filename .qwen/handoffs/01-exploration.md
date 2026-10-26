# Handoff 01 — Exploration (Agent 1 → Agent 2)

Date: 2026-10-26. Branch `experiment/swift-data`, verified at HEAD `1c51b64`.
Agent 1 was documentation-only: verified the migration state against code, established the build/test baseline, updated AGENTS.md, rewrote PLAN.md, wrote this handoff. **No source code was modified and nothing was committed.**

## What you (Agent 2) execute: **Task 1 — Fix LC_SYMTAB: real symbol names + sizes (B1, B2)**

Read `PLAN.md` at the repo root first ("Tasks" → Task 1, plus "Conventions"). Details:

### The bug, precisely

In `Aether/Core/Binary/MachOLoader.swift`, `machO(for: BinaryModel)`:

- `bytes` is the **per-load-command stream**: the loop does `bytes = bytes.extracting(droppingFirst: Int(item.cmdsize))` each iteration. So after the segment load commands, `bytes` starts at the LC_SYMTAB *command*, not at the file start.
- The port then does `let strings = bytes.extracting(droppingFirst: Int(command.stroff))` and `var symbolBytes = bytes.extracting(droppingFirst: Int(command.symoff))`. But `stroff`/`symoff` are **absolute file offsets** into the whole file. Applying them to the command-relative stream reads garbage → symbol names are wrong/empty (B1).
- Reference form (the old path in the same file, `parseSymtab`): `strOffset = binaryOffset + Int(symtab.stroff)` into the whole-file buffer. In the model path the thin image is at offset 0 in `model.data`, so the correct read is straight from `model.data` at `Int(command.stroff)` / `Int(command.symoff)`, **bounds-guarded** — use the existing `data(in:)`/`span(in:)`-style accessors on `BinaryModel` (they return nil out of bounds; do not index raw).
- The read of the `symtab_command` header itself from `bytes` is fine — only the stroff/symoff application is wrong.

### Sizes — `nlist_64` has NO size field

- Pass 1: collect `(address, n_sect, type, name)` for all `nsyms` entries.
- Pass 2: per section (the 1-based `n_sect` index into the section list), sort by address; set each symbol's `size = nextHigher.address − this.address`; 0 if last/unknown.
- `N_ABS`/`N_UNDF` symbols: size 0 is fine; they don't create procedures (only `N_SECT` with address ≠ 0 do — that logic is already correct, keep it).
- **Decision to make and record in your handoff:** for the last symbol in a section (no successor) — leave size 0 (empty `addressRange`, function disassembles to nothing) or fall back to 1 (one byte). Either is defensible; just be consistent and note it. `SymbolModel.size` currently defaults to 1 and `ProcedureModel.contains(address:)` uses `symbol.addressRange`.
- After the fix, FunctionsTab sizes should read like "1.2 KB", not "1 B" for every row.

### Testing / acceptance

- Build: `xcodebuild -project Aether.xcodeproj -scheme Aether -destination 'platform=macOS' build` (do NOT use the xcode MCP server — it cannot enumerate schemes of the single-file `project.xcproj`). Baseline was green in 12.3 s with only CapstoneKit warnings.
- Manual smoke: new document → Import Binary... (⇧⌘O) → pick `/bin/ls` → Programs navigator → "Load...". Then:
  1. Symbols tab shows real names (`_main`, `_dyld_*`, …) — not garbage.
  2. Functions tab: sizes are sane, not all "1 B".
  3. Click a function → DisassemblyView shows the whole function (many instructions).
- **Warning:** the re-parse guard doesn't exist yet (Task 2). Repeated "Load..." on the same document appends duplicate segments/symbols and can hit the `#Unique<SymbolModel>([\.binary, \.address])` constraint. Test with a **fresh document per run**.

### Process rules

- Tabs, not spaces. App target = Swift 5 (MainActor default isolation); don't re-style unrelated lines.
- **Do not commit.** The orchestrator commits after your session.
- Before you finish: append a dated entry to the "Progress log" section of `PLAN.md`, and write `.qwen/handoffs/02-lc-symtab.md` (findings, the size-fallback decision, what Agent 3 executing Task 2 needs).

## Other findings you may care about (full detail in PLAN.md)

- **Dead code (grep-verified zero external refs):** `ProjectManager`, `ExportService` (both `Models/Project.swift`), `Project` struct, AppState `saveProject/loadProject/openProject/saveProjectAs` + `ProjectData`/`PatchData`. `Bookmark` struct is LIVE (AppState bookmarks dict) — don't touch. `ExportManager` in `Services/` is the live exporter.
- **B3 (Task 2 preview):** `load(_:)` `fatalError`s on fat (0xcafebabe) / 32-bit (0xfeedface) / non-Mach-O; fat handling is commented out. Task 2 replaces this with thrown errors + a re-parse guard.
- **Bug table B1–B12** is in PLAN.md; each maps to a later task.
- `DisassemblerEngine` is model-agnostic (`disassemble(data:address:architecture:)` — no port needed, resolves an old open question).
- Build baseline: xcodebuild Aether SUCCEEDED (exit 0); `swift test` in AetherKit and CoreAether both pass with **0 test cases** — there is no automated coverage, so manual smoke is the acceptance path.
