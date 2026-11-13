# ProcedureDetector extension — completed

## Files changed (only these 4 + test file)
- `AetherKit/Sources/AetherKit/Analysis/ProcedureDetector.swift` (new file, untracked)
- `AetherKit/Tests/AetherTests/ProcedureDetectorTests.swift` (new file, untracked)
- `AetherKit/Sources/AetherKit/Load/MachOLoader.swift` (~line 174: `report.created` + timing line)
- `Aether/Models/AppState.swift` (~line 258, `findFunctions`: logs `report.created` / total)
- `aether-cli/Sources/Procedure.swift` (new file, untracked — DetectCommand prints `report.summary`)

Nothing committed.

## Constants written verbatim
- framePair: mask `0xFCC0_03E0`, pattern `0xA880_03E0`; imm7 = bits 21-15, sign bit 6 → `abs(signed)*8`
- linkStore: mask `0xFD00_03FF`, pattern `0xF800_03FE`; **offset is the raw 9-bit signed byte count in bits 20-12** (not imm7 bits 21-15 — that gave 504 for `str x30,[sp,#-8]!`)
- stackAdjust: mask `0xFD00_03FF`, pattern `0xD100_03FF`; imm12 bits 21-10, shift bits 22-21 → `imm12 << (6*shift)`
- `bti` = `0xD503_245F`, `pacibsp` = `0xD503_237F` (both confirmed by clang probe)
- stub load: mask `0xFD00_03FF`, pattern `0xF900_0210`; stub branch: mask `0xFE1F_03E0`, pattern `0xD61F_0200`; `stubThunkWidth = 12`

Clang probe encodings: `adrp x16,0` = 90000010, `adrp x16,0x1db000` = F0000ED0, `ldr x16,[x16,#8]` = F9400610, `br x16` = D61F0200, `bti c` = D503245F, `pacibsp` = D503237F, `stp x29,x30,[sp,#-0x10]!` = A9BF7BFD, `stp x20,x19,[sp,#-0x10]!` = A9BF4FF4, `stp x29,x30,[sp,#0x10]` = A9017BFD, `ldp x29,x30,[sp],#0x10` = A8C17BFD, `sub sp,sp,#64` = D10103FF, `sub sp,sp,1,lsl 12` = D14007FF, `str x30,[sp,#-8]!` = F81F8FFE, `str x30,[sp,#-0x100]!` = F8100FFE.

## Verification
- `cd AetherKit && swift test`: 9 tests, all passed, 0 issues ("Test run with 9 tests in 0 suites passed after 0.017 seconds").
- `cd aether-cli && swift build`: "Build complete! (3.51 secs.)".
- Real-binary sanity check via `aether new`/`import`/`procedure detect`:
  - /usr/local/bin/rustc: `ProcedureDetector: 4 code sections, 5982 entry points, 0 synthesized symbols, 0 procedures, 5981 total procedures` on the second run (idempotent, 0 new). 232 `stub_` procedures — matches the expected 232 stub thunks. entryPoints 5982 vs the parent's ~6484 estimate (2213 symtab functions largely coincide with prologue hits, so dedupe lands lower than 6484).
  - /tmp/probe_bin: `2 code sections, 6 entry points, 0 synthesized symbols, 0 procedures, 5 total procedures` — matches expected codeSections 2 / entryPoints 6 / 1 stub thunk.
- Scratch projects in /tmp were deleted; scratch evidence lives in `.qwen/tmp/` (enc_probe.s/.o, strimm*.s, mask_check.py, rustc_dis.txt).
