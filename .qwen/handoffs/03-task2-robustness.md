# Handoff 03 — Task 2: Loader robustness (B3)

Agent 3, 2026-10-26, branch `experiment/swift-data`. No commit made (orchestrator commits).

## Files changed

| File | Change |
| --- | --- |
| `Aether/Core/Binary/BinaryLoader.swift` | Added `BinaryLoaderError.invalidMagic(String)` and `.unsupportedBinary(String)` cases + `LocalizedError` descriptions. No other changes. |
| `Aether/Core/Binary/MachOLoader.swift` | (1) `load(_:)` reduced to a wrapper: `try await machO(for: model)` — removed the dead commented-out fat block. (2) Magic gate at the top of `machO(for:)` (before any parsing). (3) Reset-first re-parse guard. (4) Deleted the 32-bit `fatalError`. (5) In-pass dedupe in the model-path LC_SYMTAB + filtered append loop + collapsed-alias count in the log line. Legacy path (`load(data:)`, `loadFatBinary`, `parse*`) untouched. |

`Schema.swift` and `ProgramNavigator.swift` needed **no** changes (see below).

## Decisions + reasoning

1. **fatalError → typed errors.** `machO(for:)` starts with:
   - `< 4` bytes → `.invalidHeader`
   - magic == `FAT_MAGIC`/`FAT_CIGAM` → `.unsupportedBinary("fat/universal Mach-O … — thin images only")`
   - magic == `MH_MAGIC`/`MH_CIGAM` → `.unsupportedBinary("32-bit Mach-O … — 64-bit only")`
   - magic != `MH_MAGIC_64`/`MH_CIGAM_64` → `.invalidMagic("0x… — not a Mach-O header")`
   The gate lives in `machO(for:)` so *every* model-based caller gets it. Note: the fat/32-bit magic constants from `import MachO` are already `UInt32` — direct `==` comparison; an early build failure came from wrapping them in `UInt32(bitPattern:)` (whose init takes `Int32`). Fixed by dropping the wrapper.
2. **Re-parse guard: reset-first, not skip.** A previously *failed* load can leave partial rows (symbol/section appends happen before later throws); a skip guard would then wedge the model permanently (guard sees non-empty, never re-parses). Reset makes "Load..." idempotent and lets it re-parse from scratch. Safe because all four child relationships (`procedures`, `symbols`, `sections`, `segments`) are `deleteRule: .cascade`, so `removeAll()` actually deletes rows. Order: procedures → symbols → sections → segments, then zero `entryPoint`/`stackSize`/`baseAddress`. **Magic validation runs before the reset** — a Load of a bad file leaves any previously parsed content intact. (Mid-parse throw *after* reset leaves the model empty + logged error; next Load recovers.)
3. **Error visibility:** the Load... call site in `ProgramNavigator.swift` already wraps `MachOLoader.load(binary)` in `Task { @concurrent in do { … } catch { Logger.app.error("Failed to load \(binary.name) binary: \(error)") } }` — verified, no change made.
4. **`#Unique<SymbolModel>([\.binary, \.address])`: in-pass dedupe, constraint kept.** In the LC_SYMTAB pass, per address keep the highest-preference entry:
   `N_SECT external (5) > N_SECT local (4) > N_ABS external (3) > N_ABS local (2) > N_UNDF external (1) > N_UNDF local (0)`.
   This deliberately refines the task's "e.g. global > external > local > undefined": kind (where the body is) outranks the external/local bit, so an absolute constant or undefined stub can never displace a real function body at the same address. `#Unique` stays as the safety net — with the in-pass dedupe it should never fire.
   **Known consequence (do not "fix" locally):** all `N_UNDF` symbols sit at address 0, so per binary the imports collapse to *one* representative row (thin_test has 13 imports → 1 row at 0; `/bin/ls` would have ~91). The Imports tab will look wrong until the constraint is revisited — e.g. make it unique on `(binary, address, identifier)`. That is a schema change, so it's out of this task's scope.
5. **`unsafeLoadUnaligned`:** no *new* struct reads were introduced (the magic check uses the existing unaligned-safe `Data.readUInt32LE(at:)`), so no new unaligned-load call sites were needed. Task 1's `Span.unsafeLoad` for nlist_64 was left untouched per instructions.

## Evidence

- Build: `xcodebuild -project Aether.xcodeproj -scheme Aether -destination 'platform=macOS' build` → `** BUILD SUCCEEDED ** [4.547 sec]` (one red build in between, fixed as described in decision 1).
- Smoke binary (both files left in `.qwen/tmp/`, git-ignored):
  - `.qwen/tmp/thin_test.swift` — ~30-line program: `square`, `sumOfSquares`, `fib` (recursive), global `counter`, top-level entry code (a `func main()` in a single-file `swiftc` program is *not* auto-invoked — that was the v1 mistake).
  - `.qwen/tmp/thin_test` — `xcrun swiftc -target arm64-apple-macos14 -O -o .qwen/tmp/thin_test .qwen/tmp/thin_test.swift`
  - `file`: `thin_test: Mach-O 64-bit executable arm64` (thin, not universal)
  - runs: `sumOfSquares(3, 4) = 25` / `fib(10) = 55` / `counter = 67`
  - `nm` (defined, abridged): `t _$s9thin_test12sumOfSquaresyS2i_SitF` @ 0x10000097c, `t _$s9thin_test3fibyS2iF` @ 0x1000009b4, `t _$s9thin_test6squareyS2iF` @ 0x100000a44, `s _$s9thin_test7counterSivp` @ 0x100008008, `T __mh_execute_header` @ 0x100000000, `T _main` @ 0x1000006e8
  - 13 undefined (`U`) symbols, all at address 0 (examples: `_$s5print_…`, `_$ss5print_9separator10terminatoryypd_S2StF`) — this is the 13→1 Imports collapse in action.

## What Agent 4 (Task 3: AppState + toolbar fixes B4/B6/B7) needs

- **Load... already logs errors** via `Logger.app.error` in `ProgramNavigator.swift` — nothing to add there.
- Model-based path is **thin 64-bit only** by design; expect `BinaryLoaderError.unsupportedBinary` (fat/32-bit) or `.invalidMagic` for anything else. Don't treat those as crashes/regressions.
- **"Load..." is idempotent** — repeated clicks reset and re-parse; the model will never accumulate duplicate rows from repeated Loads.
- **Imports tab caveat:** one row per binary at address 0 (representative N_UNDF). `SymbolModel.isImported` is `binding == .external && address == 0`. If Task 3 touches the Imports navigator, this collapse is the root cause — fix belongs to the `#Unique` revisit, not Task 3.
- **Cascade relationships:** all four `BinaryModel` child relationships are `.cascade`; `removeAll()` on any of them is safe. Don't add non-cascade child relationships.
- **Ordering invariant in `machO(for:)`:** magic gate → reset → parse. If you add pre-parse validation, keep it before the reset; if you add recovery of partially-parsed state, it must be after.
- **Fat/slice facts carried to Task 12:** fat images have slice-relative `symoff`/`stroff` (add slice base `binaryOffset + symoff`), and the Task 1 nlist read uses alignment-strict `Span.unsafeLoad` — switch to `unsafeLoadUnaligned` when non-zero slice bases are introduced.
- Smoke assets: `.qwen/tmp/thin_test` (+ `.swift` source). Re-compile if missing: `xcrun swiftc -target arm64-apple-macos14 -O -o .qwen/tmp/thin_test .qwen/tmp/thin_test.swift`.

## Manual UI smoke steps (orchestrator)

1. Import `.qwen/tmp/thin_test` → Load... → Symbols tab shows the named Swift symbols (`_$s9thin_test…`) with non-zero sizes for the N_SECT entries; one import row at 0.
2. Load... again on the same binary → **no duplicate** rows (reset-first), same symbol set.
3. Import `/bin/ls` → Load... → clean logged error (`Unsupported binary: fat/universal Mach-O (magic 0xcafebabe) — thin images only`), no crash, app responsive.

## Risks for later tasks

- Imports-tab collapse (above) will look like a regression to anyone not reading this file.
- `#Unique` safety net: if a future code path appends symbols outside the dedupe'd pass, SwiftData will throw a unique violation on save — that's the constraint working as intended, but it will surface as a model-save failure, not a load error.
- The `sym.n_sect == 1` (__TEXT,__text) size heuristic is pre-existing; it's why only __text symbols currently get real sizes — Task 12 should generalize per-section.
- Legacy `BinaryFile` path still exists and still has its own fat handling; Task 11 deletes it. Until then, `BinaryLoader` dispatch (legacy) and `MachOLoader.load` (model) are two different code paths with different fat behavior — the legacy one *does* parse fat images.
