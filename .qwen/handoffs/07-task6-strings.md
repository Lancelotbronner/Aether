# Handoff 07 — Task 6: populate strings (B11)

Date: 2026-10-26. Branch `experiment/swift-data`. Executed by **Agent 8** (finishing the task; the scanner code was written by the previous agent and verified correct — not rewritten). No commit made here (orchestrator commits after verification).

## 1. Files changed

| File | Change |
| --- | --- |
| `Aether/Core/Binary/MachOLoader.swift` | (1) `machO(for:)` now calls `model.strings = scanStrings(in: model)` right after the load-command loop (~line 341, before the baseAddress/format assignment). (2) New `nonisolated static func scanStrings(in: BinaryModel) -> [StringModel]` (~lines 367–409): the eager C-string scanner (details in §2). Diff: +64/−1, no other files touched. |
| `ORCHESTRATOR_NOTES.md` | **Not changed by this task** — it shows as modified in `git status` because the *orchestrator* maintains it; left untouched. |

Evidence assets (git-ignored, `.qwen/tmp/`): `strings_mirror.swift` + compiled `strings_mirror` — a **fresh** mirror script written by Agent 8 (the previous agent's `strings_scan_check.swift` is still there but was not reconstructed or used). `thin_test(.swift)` — the existing smoke binary, reused as-is (51 480 bytes, matches ground truth).

## 2. Decisions + reasoning

1. **Eager at Load** (plan-recommended): the scan runs inside `machO(for:)`, after segments/sections are parsed so the `__TEXT`/`__cstring` regions are known. Re-Load idempotency is free: Task 2's reset-first guard clears child rows and `BinaryModel.strings` is `.cascade`, so every Load rescans fresh. No new AppState state.
2. **`__cstring` preference with whole-`__TEXT` fallback**: if the `__TEXT` segment declares a `__cstring` section with `offset + size <= data.count`, only that section's bytes are scanned (that's where the compiler puts C-strings, and code bytes are excluded). Otherwise the whole `__TEXT` segment is scanned so binaries without `__cstring` still get coverage. Each candidate region is bounds-guarded (`Int(fileOffset) + Int(fileSize) <= data.count`) *before* the `subdata` slice, so a corrupt/truncated header can't trap.
3. **Threshold: printable-ASCII runs of ≥ 4 bytes** (`0x20…0x7E`), single linear pass over the region slice; a run reaching the region end is flushed. 4 is the same minimum `strings(1)` uses by default.
4. **vaddr = region.address + intra-region file offset** — correct for both regions because `__cstring.address` and `__TEXT.vmaddr` are the actual virtual bases and the region's file offset is the base of the slice. One `StringModel(binary: model, address: vaddr, encoding: .ascii, cached: value)` per hit; `cached` is set, so `StringModel.value` never falls back to `"not loaded"`.
5. **Scope difference vs `strings(1)`, by design:** the scanner only scans `__cstring`, so it does **not** report `yypG` (file offset 0xaef, which sits in `__swift5_typeref`), while `strings(1)` (whole file) does. Recorded, not "fixed" — reporting compiler-internal section contents as user strings would be noise.

## 3. Evidence

- **Build:** `xcodebuild -project Aether.xcodeproj -scheme Aether -destination 'platform=macOS' build` → `** BUILD SUCCEEDED ** [2.537 sec]` (only the pre-existing CapstoneKit "no rule to process file" warnings). No source changes by Agent 8 — the green build confirms the previous agent's code compiles as committed-to-tree.
- **Ground truth verified (not re-derived), `otool -l .qwen/tmp/thin_test`:** `__TEXT` vmaddr `0x100000000`, fileoff 0, filesize 16384; `__cstring` addr `0x100000b00`, size `0x16` (22), offset 2816; `__swift5_typeref` offset 2794, size 10 (0xaea–0xaf5). `thin_test` = 51 480 bytes.
- **`strings -t x .qwen/tmp/thin_test`** (hex file offsets):
  ```
  aef yypG
  b00 sumOfSquares(3, 4) =
  ```
- **Scanner mirror** (`.qwen/tmp/strings_mirror` — same threshold, same region preference, same vaddr formula as `scanStrings`):
  ```
  0x100000B00  sumOfSquares(3, 4) =
  scanned region: __cstring, 22 bytes
  ```
  Exactly one hit: same string as `strings(1)`'s `0xb00` entry, at vaddr `0x100000000 + 0xb00 = 0x100000b00` — the same virtual address the scanner would store. `yypG` (0xaef, in `__swift5_typeref`) is the one expected absence vs `strings(1)` — §2.5, correct by design.
- **Mirror-script debugging note (why it took several iterations):** three bugs were in the *mirror script*, never the scanner — (a) `ncmds` read from mach_header offset 32 instead of 16; (b) `segment_command_64.nsects` is at +64 (I first read `filesize` at +48 → 16384 bogus section iterations) and `section_64.size` is a **u64 at +40** (reading +44 gave the high word = 0); (c) the scan loop started at file offset 0 instead of `region.start`, mislabeling header/load-command bytes with `__cstring` vaddrs. The real `scanStrings` slices `subdata(in: fileStart..<fileEnd)` and indexes the slice from 0, so it is unaffected by (c).

## 4. What Agent 9 (Task 7: search filters + SearchSheet, B12) needs

- Strings are now populated at Load; `StringsNavigator` already displays `StringModel.value` and row tap calls `appState.goToAddress(str.address)` (verified — do not change either).
- **Important constraint for the Strings filter:** `StringModel.value` is `cached ?? "not loaded"` where `cached` is `@Transient` — it is **not persisted**, so `#Predicate` cannot query it. The Strings filter must be **in-memory** (`strings.filter { $0.value.localizedCaseInsensitiveContains(searchText) }`), matching the plan's "in-memory filter is acceptable at prototype scale". The other four navigators can use `#Predicate` (their searchable fields — `name`/`identifier` — are stored).
- SearchSheet result cases (commented out in `UI/MainWindow/MainView.swift`) can query `StringModel` rows directly; the same `@Transient` caveat applies to filtering on `value`.
- Do not touch `scanStrings`, the `__cstring` preference, or the vaddr formula — that's settled Task 6 surface.
- Still open from before (block Task 8, not Task 7): stale disassembly cache on re-Load and the `instructions(in:)` `UInt64` underflow trap (handoff 05 §2.5/§2.6).

## 5. Manual UI smoke steps (for the user, at end of session)

1. New document → Import Binary... (⇧⌘O) → pick `.qwen/tmp/thin_test` → Programs navigator → **Load...**.
2. **Strings tab:** shows `sumOfSquares(3, 4) = ` at `0x100000b00` (no "not loaded" rows).
3. Tap that row → `goToAddress` lands at `0x100000b00` (disassembly/hex context moves there).
4. Load... a second time → the Strings tab still shows exactly the same single row (cascade reset, no duplicates).

## 6. Risks / known interim states

- The **whole-`__TEXT` fallback path is untested** — `thin_test` declares `__cstring`, so only the primary path was exercised. Fallback binaries will also surface printable runs inside code/const sections (noise); that's the accepted trade-off for the no-`__cstring` case.
- ASCII-only scan (`0x20…0x7E`): UTF-16 and high-byte UTF-8 strings are not reported. Fine for B11's scope (C-strings); a future analyzer can widen it.
- `StringModel.value` returning `"not loaded"` for rows created outside the loader (none exist yet) is unchanged.
