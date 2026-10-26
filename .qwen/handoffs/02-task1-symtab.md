# Handoff 02 — Task 1: LC_SYMTAB fix (B1, B2)

**Backfilled by the orchestrator** (Agent 2 completed the code work but never wrote its
progress-log entry or this file; see ORCHESTRATOR_NOTES.md). Facts verified by the
orchestrator against the code and the build.

## What was done

`Aether/Core/Binary/MachOLoader.swift` — `machO(for:)` LC_SYMTAB case rewritten:

1. **B1 fixed:** `symoff` (nlist array) and `stroff` (string table) are treated as
   *absolute file offsets* and read from `model.data` (whole file) with bounds guards;
   a truncated table now throws `BinaryLoaderError.corruptedFile` instead of trapping.
   Previously they were applied to the per-load-command `bytes` stream → garbage names.
2. **B2 fixed:** two-pass size derivation (`nlist_64` has no size field):
   - Pass 1: read all `nsyms` entries as `nlist_64` (16-byte stride, `MemoryLayout<nlist_64>.size`)
     + names via `readCString` from the string table.
   - Pass 2: per `n_sect`, collect `n_value`s, sort, `size[i] = sorted[i+1] − sorted[i]`.
   - **Decision: size 0** (not the `SymbolModel` default 1) for the last symbol per
     section and for all `N_ABS`/`N_UNDF` — an unknown size must not masquerade as a
     1-byte body. `N_ABS`/`N_UNDF` also get `.unknown` type and `.external`/`.undefined` binding.
   - Local+global aliases at the same address share the derived size (same key in the dict).
3. `nlist_64`/`symtab_command` come from **Apple's Darwin MachO Swift overlay**
   (`import MachO`), not CoreAether's C headers — 16-byte size is guaranteed in-build.

## Evidence

- Standalone script `.qwen/tmp/symtab_check.swift` (git-ignored, kept as evidence)
  parses `/bin/ls` identically and matches `nm` entry-for-entry: 93 entries
  (91 `N_UNDF` + `__mh_execute_header` at `0x100000000` size 0 + one hidden N_STAB entry).
  `/bin/ls` has **no** `_main`/`_dyld_*` symbols — absence confirmed by `nm`, not a bug.
- `xcodebuild -project Aether.xcodeproj -scheme Aether -destination 'platform=macOS' build`
  → BUILD SUCCEEDED (orchestrator re-verified).

## Critical facts for Agent 3 (Task 2)

1. **All system binaries are fat (3-arch)** — `/bin/ls`, `/usr/bin/*` are
   `Mach-O universal binary [x86_64, arm64e, arm64e.x1]`. The thin-only `machO(for:)`
   path cannot load them (fat → `fatalError` today, typed error after Task 2).
   For any manual smoke, compile a thin one:
   `xcrun swiftc -target arm64-apple-macos14 -O -o /tmp/thin_test /tmp/thin_test.swift`
   (a ~20-line program with a few named functions gives symbols + a real body).
2. **Slice-relative symtab offsets:** in a fat image, `symoff`/`stroff` are relative
   to the slice's `mach_header`, not file-absolute (verified: x86_64 slice at base
   `0x4000`; real table at `0x4000+0x66e8`). Any future slice/fat support must use
   `binaryOffset + symoff` (the legacy path's reference form). The thin path (slice
   base 0) is exactly what Task 1 shipped.
3. **Alignment:** the new nlist read uses alignment-strict `Span.unsafeLoad`. If you
   introduce non-zero slice bases, switch to `unsafeLoadUnaligned` (the legacy
   `parseSymtab` does).
4. **`#Unique<SymbolModel>([\.binary, \.address])` risk:** the loader appends *every*
   entry, so local+global aliases at one address produce duplicate `(binary, address)`
   rows. After your re-parse guard, try loading a real thin binary and watch SwiftData
   for unique violations in the log; dedupe (keep global, skip local) or drop the
   constraint — record the choice.

## Open / deferred

- `sym.n_sect == 1` is used as the "is __TEXT,__text" heuristic for `.function`
  classification (pre-existing). Works in practice; refine later.
- Fat *slicing* support is out of scope for Task 2 (typed error only), per plan.
- Manual UI smoke (import thin binary → Load → Symbols tab real names, Functions tab
  real sizes, click function → full body) is left for the user — headless session.
