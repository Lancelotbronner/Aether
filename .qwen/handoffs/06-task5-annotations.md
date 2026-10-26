# Handoff 06 — Task 5: modelize annotations, bookmarks, renames (+ modelContext wiring)

Date: 2026-10-26. Branch `experiment/swift-data`. Executed **by the orchestrator** (Agent 6 spawn failed with a subagent context-overflow — see ORCHESTRATOR_NOTES.md). No commit made here (orchestrator commits after verification).

## 1. Files changed

| File | Change |
| --- | --- |
| `Aether/Models/AppState.swift` | (1) `import SwiftData` added. (2) The four user-annotation dicts (`renamedFunctions`, `renamedSymbols`, `comments`, `bookmarks: [UInt64: Bookmark]`) **deleted**. (3) New `@ObservationIgnored var modelContext: ModelContext?` in the Services block. (4) Rename/comment/bookmark methods rewritten as model-backed (below). (5) Dead `getDisplayName(forFunctionAt:)`/`getDisplayName(forSymbolAt:)` **deleted** (zero live callers — only commented-out search code referenced them; Task 10 builds its own model-based lookups). (6) Dead persistence tail reconciled: `ProjectData` lost its `renamedFunctions/renamedSymbols/comments/bookmarks` fields; `saveProject`/`loadProject` no longer touch them (the tail itself stays — Task 11 deletes it). |
| `Aether/Scene/AetherContent.swift` | `import SwiftData` + `@Environment(\.modelContext)` captured; `onAppear` now also does `appState.modelContext = modelContext` (mirrors the existing `appState.undoManager = undoManager`). |
| `Aether/Navigator/FunctionsNavigator.swift` | `FunctionRow.displayName`: `appState.renamedFunctions[address] ?? function.shortDisplayName` → `function.shortDisplayName` (renames now live on the symbol model, which `shortDisplayName` reads). |
| `Aether/UI/DisassemblyView/BranchVisualization.swift` | Row comment display: `appState.comments[instruction.address]` → `appState.getComment(at:)` (the one live dict reader; Inspector's is commented out). |

## 2. Decisions + reasoning

1. **Renames → `SymbolModel.name`.** The schema already models this: `SymbolModel.identifier` is the original name, `name` the current one (`refresh()` resets `name = identifier`, so the original is always recoverable). A rename at address A = find the symbol at A, set `name`. Empty new name = un-rename (restore `identifier`), matching the old "empty → dict entry nil → fallback" semantics. `renameFunction` prefers the `ProcedureModel`'s symbol at the address; `renameSymbol` prefers plain symbols; each falls back to the other kind. No new model, no schema change.
2. **Comments → `AnnotationModel` rows** (kind `.inline` by default; existing row's kind preserved on restore). One row per address: `setComment` updates the existing row's `text` if present, inserts if not, deletes if the new comment is empty. `getComment(at:)` = first annotation at the address.
3. **Bookmarks → `BookmarkModel` rows** (`name`, `address`, `summary` ← old `description`, `created` = Date.now). `removeBookmark` deletes the row at the address.
4. **Undo: `modelContext.undoManager` finding — it is NOT wired.** `modelContext.undoManager` is an optional the developer must assign; the `_SwiftData_SwiftUI` DocumentGroup bridge does not assign it (framework contract; could not be runtime-confirmed headlessly). Per the task rule ("if nil, keep the manual mechanism and record the finding"), the **manual `registerUndoRedo` was kept** — its closures now mutate/insert/delete *models* instead of dict entries. ⌘Z still works in-session (the window `UndoManager` is set in `AetherContent.onAppear` as before).
   - Delete-undo is done by **rebuilding a fresh model object** in the undo closure (not by re-inserting the deleted instance) — re-inserting a row whose persistent identity was already committed as deleted is unsafe across autosaves.
   - **Follow-up candidate (not done):** assigning `modelContext.undoManager = <window undo manager>` would give native SwiftData auto-undo for *all* model changes, but it interacts with autosave in ways that need manual testing; recorded as an open question, not a Task 5 requirement.
5. **`hasUnsavedChanges = true` dropped from the mutators.** The flag is legacy patch-flow state (only dead code reads/writes it now); SwiftData autosave persists model changes as the document. Keeping the assignments would have implied a save path that no longer exists.
6. **`getDisplayName` helpers deleted as dead** (see §1.5) — they referenced both rename dicts and the never-populated legacy caches; nothing live calls them.

## 3. Evidence

- Build: `xcodebuild -project Aether.xcodeproj -scheme Aether -destination 'platform=macOS' build` → `** BUILD SUCCEEDED ** [5.100 sec]` (first attempt failed on missing `import SwiftData` in AetherContent.swift — `\.modelContext` requires it; fixed, second attempt green).
- Grep: `renamedFunctions|renamedSymbols|appState.comments|bookmarks\[` under `Aether/` → only (a) the dead `Project` struct's own independent fields in `Models/Project.swift` (Task 11), (b) one commented-out line in `Inspector.swift`. Zero live references to the deleted dicts.
- `git diff --stat`: AppState +95/−67-ish across 4 source files (details in §1).

## 4. What Agent 7 (Task 6: populate strings, B11) needs

- **Strings are eager-at-Load or at-Analyze** — decide in Task 6 (plan recommends eager). `StringModel` already has `@Transient cached: String?` + `value = cached ?? "not loaded"` and a `BinaryModel.strings` cascade relationship; the loader (`machO(for:)`, after the reset-first guard) is the natural insertion point.
- `StringModel` init: `init(binary:address:encoding:cached:)`. `StringEncoding` enum exists (check `Models/BinaryFile.swift` or Schema for its cases).
- Do NOT touch the annotation/bookmark/rename code — Task 5 surface is done.
- The disassembly-cache stale-on-re-Load issue and the `instructions(in:)` underflow trap (handoff 05 §2.5/§2.6) are **still open** — they block Task 8, not Task 6.
- Re-Load (reset-first) deletes `BinaryModel` child rows via cascade — `strings` is cascade too, so re-parsing strings is automatically idempotent.

## 5. Manual UI smoke steps (for the user, at end of session)

1. Import `.qwen/tmp/thin_test` → Load... → Functions tab → right-click a function → Rename... → type a new name → OK. Row shows the new name; the rename **persists across document close/reopen** (it's a model row now).
2. ⌘Z immediately after the rename → name reverts in-session; ⌘⇧Z re-applies.
3. (Comments/bookmarks have no live UI yet — `setComment`/`addBookmark` are API-only for now; persistence is covered by the same model machinery and will be exercised when their UI lands.)

## 6. Risks / known interim states

- `getComment(at:)` is an O(annotations) scan per disassembly row render (was O(1) dict). Fine at prototype scale; if annotations grow large, add an address index.
- The legacy `Bookmark` struct (`Models/Project.swift`) is now fully unused — Task 11 deletes it (PLAN already says post-Task 5).
- `UndoAction` enum still exists in AppState (dead; its `addBookmark/removeBookmark` cases reference the legacy `Bookmark` struct). Task 11 deletes the whole enum.
- If the user's document was created before this change, it simply has no annotation rows — nothing to migrate (the old dicts were never persisted anywhere reachable).
