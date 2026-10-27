---
name: swiftui-anti-pattern-audit
description: 2026-10-11 SwiftUI anti-pattern audit of AetherScene-reachable views; SwiftUI.md deleted from root in 1c51b64, findings folded into new PLAN.md bug list B1–B12
type: project
category: project_introduction
keywords:
  - "SwiftUI audit"
  - "SwiftUI.md"
  - "AetherScene"
  - "AppState god model"
  - "functionNavigator setter bug"
usage_scenarios:
  - "User asks to fix SwiftUI findings or P0/P1 issues"
  - "Touching AppState, DisassemblyView, DecompilerView, HexView, navigators"
---

A full anti-pattern audit (per the the-swiftui-way skill) of all views reachable from `AetherScene` was completed on 2026-10-11. The report was `SwiftUI.md` at the repo root (tracked) — **it was deleted from root in `1c51b64` (2026-10-25)**; a recovered copy is at `.qwen/tmp/SwiftUI.md.prev`. Its surviving findings were verified against code on 2026-10-26 and folded into `PLAN.md`'s bug list B1–B12:

- G1: functionNavigator setter fixed; **sectionNavigator setter still ignores newValue** (B4) → Task 3.
- F1: DecompilerView shows placeholder output — dormant stub confirmed (`.task { appState.decompileCurrentFunction() }` sets `// Decompiling...` permanently) → Task 8.
- D11: `clearDisassemblyCache` corrupts/crashes the instruction cache → Task 4.
- L1 variant: toolbar clusters disabled on never-set `currentFile` (B6) → Task 3.
- N2: "CFG" button calls `analyzeAll()` (B7) → Task 3.

**Why:** the project is a rescued AI-generated prototype with disconnected/duplicated UI code; the user wants it usable.

**How to apply:** do not look for SwiftUI.md at the repo root; use `PLAN.md`'s bug table (B1–B12) and task list, which supersedes the audit's P0/P1/P2 breakdown. Before touching AppState, the disassembly/decompiler/hex views, or the sidebar navigators, check the matching PLAN.md task.
