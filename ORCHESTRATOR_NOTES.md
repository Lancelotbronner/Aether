# ORCHESTRATOR NOTES — SwiftData migration

Session: 2026-10-25, unattended. Branch: `experiment/swift-data`.
Goal: complete the transition from ad-hoc project state (god-model `AppState`, `Project`/`ProjectData`) to SwiftData-backed documents.

## Process

- Agents run **sequentially**, one task each (unless a task is small and can be combined with an explicit note).
- Each agent writes/updates a handoff file in `.qwen/handoffs/NN-slug.md` — serves as crash recovery and context for the next agent.
- I (orchestrator) commit between agents, verify builds, and record decisions/issues here.
- All decisions, workarounds, and issues are recorded here for later review.

## Log

### 2026-10-25 session start
- Starting state: clean tree at `1c51b64` "Get ready for long unattended session".
- Prior state (from memory, verify against code): SwiftData `DocumentGroup` (private `_SwiftData_SwiftUI` bridge) landed in `591c157`; schema in `Aether/Schema/Schema.swift`; per-window `AppState` session in `AetherRootView`; Mach-O loading into models works, function loading works, instruction selection crashed then fixed (data(in:) guards, N_ABS symbols). Running plan was in `PLAN.md` (phases 0–6). SwiftUI anti-pattern audit in `SwiftUI.md`. Open: `symbol.size` always 1 (functions disassemble to one byte); dead `Project`/`ProjectManager`/`ProjectData` slated for deletion.
- Agent 1 launched: exploration + AGENTS.md update + PLAN.md rewrite.

### Agent 1 complete (2026-10-26)
- Verification pass against code: migration state confirmed (DocumentGroup bridge working, @Query navigators, model-driven DisassemblyView, hybrid AppState); dead code confirmed by grep (ProjectManager, ExportService, Project, AppState persistence tail; Bookmark struct still live); DisassemblerEngine confirmed model-agnostic (no port needed).
- Build baseline green: xcodebuild Aether `** BUILD SUCCEEDED ** [12.287 sec]` (capstone warnings only); AetherKit + CoreAether `swift test` pass with 0 test cases each (no automated coverage exists).
- Bug list B1–B12 finalized (incl. symbol.size always 1 / LC_SYMTAB offsets). AGENTS.md updated; PLAN.md rewritten as a 12-task ordered plan with progress log; handoff at `.qwen/handoffs/01-exploration.md`. Documentation only — no source changes, no commit (orchestrator to commit this).
- Agent 2 to execute Task 1 (LC_SYMTAB fix) per the handoff.
