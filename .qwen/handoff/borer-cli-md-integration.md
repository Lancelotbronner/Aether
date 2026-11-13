# CLI.md borer integration — done (2026-11-13)

Only `CLI.md` was edited. borer capture files: `.qwen/tmp/borer_help.txt` (100 lines, complete), `.qwen/tmp/borer_probe1.txt`, `.qwen/tmp/borer_task_notes.md` (verified Aether API facts).

## borer help shape
Flat command list, no groups: `borer --help` lists ~55 commands + 8 global options; `borer <cmd> --help` and `borer help <cmd>` both print only that command's usage line. No man page, no completion scripts. Docs at `/opt/homebrew/Cellar/borer/0.2.12/README.md`. `version`/`--version`/`-V`. Bare `borer` = MCP stdio server (never run it).

## Added to CLI.md
- Tier 1: 21 `aether addr` (borer `addr <va|rva:<n>|off:<n>>`, `<address|name>` everywhere), 22 `aether snapshot`/`changes` (borer `snapshot`/`changes`/`anchors`/`fingerprint`/`diff`).
- Tier 2: 23 fetch page totals (borer `# showing N of M`, per-command caps — `--limit`/`--offset` already exist in `Fetch<T>.swift`, `CountCommand` shares them), 24 `aether graph` (borer `cfg`, `callgraph`), 25 `aether hash` (borer `hashes`, `fingerprint`).
- Tier 3: 26 `aether decompile` (borer `decompile ... [skeleton|full]`; `Decompiler.swift:93` already public), 27 `aether grep`/`index` (borer `index` + `grep ... re:<expression>`).
- Folded: 1 (`info <binary>`), 3 (`hexdump`/`read [kind] [count]`, `off:`), 4 (`search` `??` wildcards, `sig`, `findstr`, `fieldrefs`), 5 (`why`), 7 (`tools` JSON, `names <ida|ghidra|binja|x64dbg>`), 8 (`strings [filter] [offset] [limit]`), 13 (`disasm [count]` default 32 max 256, `disasmfn`), 16 (`index`, `triage`), 17 (`doctor [offline]` + `aether --version` unregistered).
- Still-open line extended with 21-27; tail `## Not features` section and the Verified/Gotchas sections untouched.

## Corrections found while verifying (worth keeping)
- `--limit`/`--offset` ALREADY shipped on fetch and count (`Fetch<T>.swift` `FetchOptions` → `descriptor.fetchLimit`/`fetchOffset`), so no paging entry was created; the gap is the missing total and `count --limit` reporting the page.
- Entry 4's Status line lumps BlockModel with CrossReferenceModel: only `BlockModel.procedure`/`init`/`size` are internal — the edge/address fields are public. Noted inline in entry 4 rather than rewritten.
- AetherKit `Analysis/EntropyAnalyzer.swift`, `IoCExtractor.swift`, `PackerDetector.swift`, `MalwareAnalyzer.swift` are public result structs with zero `func`; only `ProcedureDetector` (+ `Decompiler`, `DisassemblerEngine`) has real code in the package.
- `ControlFlowStructurer` is internal end-to-end, so a CLI graph prints the stored CFG, not the structured shape.
- No `version` in `Sources/Aether.swift`'s `CommandConfiguration` → `aether --version` unregistered.

## Judged irrelevant (not written)
MCP server/`setup`/`tools` registry/`update`/`fetch-pdb`/`reload`; `pack`/`packs`/`pack-keys`/`export-pack`/`sigmake` (the SwiftData document is the pack); protocol recovery (`class`, `vslot`, `schema(s)`, `encode(s)`, `senders`, `protocol`, `hooks`, `dispatchers`, `opcodes`, `opsends`, `shape`, `messages`, `map`, `attrs`, `ports`, `qt`); emulator family (`emulate`, `run`, `solve`, `partial`, `oracle`, `unpack`, `devirt`, `vm`, `taint`, `layout`, `verify`, `certify`, `blame`); Windows live-process tools; `yara`/`crypto` constants; `encoded`/`hidden`; `--arch` raw-dump mode (model path is Mach-O only — loader port, not CLI surface).
