# CLI.md prune — plan (branch experiment/swift-data, HEAD 3504ddd)

## Verified surface (empirical: `swift run aether --help` in aether-cli, build OK)
Subcommands: program, section, segment, symbol, procedure, annotation, bookmark, new, import.
program = fetch/count/delete only; the six child groups add insert; procedure adds detect.
No inspect / bytes / find / doctor / disassemble / analyze anywhere in aether-cli/Sources.

## Entry decisions
- 1 inspect: KEEP (no subcommand; MachOLoader still prints at AetherKit/Sources/AetherKit/Load/MachOLoader.swift:161 & :178, detection inline at :174)
- 3 bytes: KEEP, fix one now-false caveat — Schema+.swift now exposes public Span accessors: bytes(at:) :37, span(at:) :42, bytes(in:) :49, span(in:) :57, format(hex:) :80 goes through span(in:) not Data. `hex(bytes:)` still absent.
- 4 find: KEEP (CrossReferenceModel stored props still internal: Schema.swift:273-278; BlockModel.procedure internal :225)
- 5 --explain: TRIM (detect shipped; ProcedureDetectionReport still only codeSections/entryPoints/synthesized/created at Analysis/ProcedureDetector.swift:22-31; note(:stackSize:isStub:) at :108 has no per-pattern counter)
- 7 --json: KEEP (no --json anywhere; Import.swift still prints persistentModelID)
- 8 symbol parity: TRIM (Symbol.swift FetchOptions has binary/name/address/kind/type/binding/value + --imported/--exported; NO --min-length / --section / --raw)
- 11 --demangle: TRIM (Procedure.swift:98 `--demangled` on insert shipped; demangleSwift/demangleCPP still `return nil` at Schema+.swift:180/:187)
- 12 doctor/validation: KEEP (Aether.swift:31 still `try! ModelContainer(...)`)
- 13 disassemble: TRIM + FIX — CLAIM WAS FALSE. AetherKit/Package.swift:16 depends on Lancelotbronner/capstone branch next, target links CapstoneKit; AetherKit/Sources/AetherKit/Disassembler/{DisassemblerEngine,CapstoneDisassembler,...}.swift exists, `public actor DisassemblerEngine` :65, `public func disassemble(data:address:architecture:) -> DisassemblyResult` :71. The app-side Aether/Core/ tree is GONE (glob empty) — HEAD 3504ddd moved core into AetherKit. Packaging blocker resolved; the CLI command is still absent.
- 15 import --replace + census: TRIM (delete shipped on all 7 groups; no --replace flag in Import.swift; DeleteCommand prints only its own count)
- 16 analyze: TRIM (DetectCommand standalone, loops every BinaryModel, honours --dry-run; no analyze/--list-passes/--pass; machO(for:) still calls detect inline at :174)
- 17 doctor: KEEP (still open; migration hazard live via try!)
- 19 --no-analyze/--quiet: TRIM (import load-before-save + bare --dry-run shipped; loader still prints :161/:178 and detects inline :174)
- 20 README: KEEP, trim shipped-half sentence; fix line ref: defaultSubcommand claim is README.md line 33 (not 31). README still has `aether string [fetch]` :45, `aether string count` :46, intro "strings" :3, no insert/delete rows.

## Deletions: NONE — no entry's proposed feature is fully shipped (evidence above).

## DONE (CLI.md edited, 197 → 190 lines)
- Header HEAD 87ba326 → 3504ddd; rest of the verified-surface section verified accurate (filter vocab, guards, describe(), try! trap, sort keys) — no other claim touched.
- Kept verbatim: 1, 3(1 caveat rewritten), 4, 7, 12, 17, 20(minor).
- Trimmed shipped-half prose: 5, 8, 11, 15, 16, 19.
- Rewrote 13's cost: packaging blocker gone (CapstoneKit in AetherKit/Package.swift:16; public actor DisassemblerEngine at Disassembler/DisassemblerEngine.swift:65, disassemble(...) at :71; Aether/Core tree is gone). Added caveat: engine uses try! at :78 for the per-arch CapstoneDisassembler.
- "### Still open after these changes" list (CLI.md:62) already names exactly the 14 survivors — left as is.
- Empirical checks: `.build/debug/aether symbol --project X` → "Error: Unknown option '--project" exit 64; `symbol fetch --help` has no --min-length/--section/--raw.


## Also
- Header: "HEAD `87ba326` plus uncommitted filters and inserts" → HEAD `3504ddd` (filters/inserts now committed).
- Still-open cross-ref list must match survivors: 1, 3, 4, 5, 7, 8, 11, 12, 13, 15, 16, 17, 19, 20.
- Keep tabs, no space-indented blocks; tail "Not features" section untouched.
