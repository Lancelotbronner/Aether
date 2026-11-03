import Foundation
import MachO
import CoreAether
import OSLog

/// Mach-O binary format loader
public nonisolated final class MachOLoader {
	public init() {}
}

public nonisolated extension MachOLoader {

	func canLoad(data: Data) -> Bool {
		guard let magic = data.readUInt32LE(at: 0) else { return false }
		return magic == MH_MAGIC || magic == MH_CIGAM ||
		magic == MH_MAGIC_64 || magic == MH_CIGAM_64 ||
		magic == FAT_MAGIC || magic == FAT_CIGAM
	}

	/// Model-based Mach-O loader. Thin 64-bit Mach-O only: fat, 32-bit
	/// and non-Mach-O input throws a `BinaryLoaderError` (never traps).
	/// Format validation and the re-parse guard live in `machO(for:)` so
	/// every caller of the model-based path gets them.
	@concurrent
	static func load(_ model: BinaryModel) async throws {
		try machO(for: model)
	}

	static func machO(for model: BinaryModel) throws {
		// Format gate (B3): the model-based path supports thin 64-bit
		// Mach-O only. Fat, 32-bit and non-Mach-O input used to hit a
		// fatalError; now it throws a typed error the "Load..." call
		// site logs.
		guard let magic = model.data.readUInt32LE(at: 0) else {
			throw BinaryLoaderError.invalidHeader
		}
		if magic == FAT_MAGIC || magic == FAT_CIGAM {
			throw BinaryLoaderError.unsupportedBinary("fat/universal Mach-O (magic 0x\(String(format: "%08x", magic))) — thin images only")
		}
		if magic == MH_MAGIC || magic == MH_CIGAM {
			throw BinaryLoaderError.unsupportedBinary("32-bit Mach-O (magic 0x\(String(format: "%08x", magic))) — 64-bit only")
		}
		guard magic == MH_MAGIC_64 || magic == MH_CIGAM_64 else {
			throw BinaryLoaderError.invalidMagic("0x\(String(format: "%08x", magic)) — not a Mach-O header")
		}

		// Re-parse guard (B3): "Load..." must be idempotent. Chose
		// reset-first over skip: a previously failed load can leave
		// partial state (rows appended before a throw), which a skip
		// guard would wedge permanently; reset also lets "Load..."
		// re-parse from scratch. All four child relationships are
		// .cascade, so removeAll() deletes the rows.
		if !model.segments.isEmpty {
			model.procedures.removeAll()
			model.symbols.removeAll()
			model.sections.removeAll()
			model.segments.removeAll()
			model.entryPoint = 0
			model.stackSize = 0
			model.baseAddress = 0
		}

		var bytes = model.data.bytes
		let header = bytes.unsafeLoad(as: mach_header_64.self)

		let is64Bit = header.magic == MH_MAGIC_64 || header.magic == MH_CIGAM_64
		let swapped = header.magic == MH_CIGAM || header.magic == MH_CIGAM_64
		model.endian = swapped ? .big : .little

		let start = ContinuousClock.now
		var log = "Mach-O: \(bytes.byteCount) bytes, \(is64Bit ? "64-bit" : "32-bit")\(swapped ? ", byte-swapped" : "")\n"

		bytes = bytes.extracting(droppingFirst: MemoryLayout<mach_header_64>.size)

		// `n_sect` is a 1-based ordinal over the sections in load-command
		// order, so the symbol table cannot be decoded until every section
		// exists. Capture the command and decode after the loop.
		var symtab: symtab_command?

		log += "Parsing \(header.ncmds) load commands\n"
		for _ in 0..<header.ncmds {
			let item = bytes.unsafeLoad(as: load_command.self)

			switch item.cmd {
			case UInt32(bitPattern: LC_SEGMENT_64):
				let command = bytes.unsafeLoad(as: segment_command_64.self)
				let segment = SegmentModel(in: model)
				model.segments.append(segment)

				segment.name = withUnsafeBytes(of: command.segname) {
					String(cString: $0, maxLength: 16)
				}
				segment.address = command.vmaddr
				segment.size = command.vmsize
				segment.fileOffset = command.fileoff
				segment.fileSize = command.filesize
				segment.initProtection = UInt32(bitPattern: command.initprot)
				segment.maxProtection = UInt32(bitPattern: command.maxprot)

				log += "Parsing \(command.nsects) sections in \(segment.name)\n"

				var sectionBytes = bytes.extracting(droppingFirst: MemoryLayout<segment_command_64>.size)
				sectionBytes = sectionBytes.extracting(droppingLast: sectionBytes.byteCount % MemoryLayout<section_64>.size)
				let sections = Span<section_64>(_bytes: sectionBytes)
					.extracting(first: Int(command.nsects))

				for item in sections {
					let section = SectionModel(in: segment, of: model)
					segment.sections.append(section)
					model.sections.append(section)

					section.name = withUnsafeBytes(of: item.sectname) {
						String(cString: $0, maxLength: 16)
					}
					section.segmentName = withUnsafeBytes(of: item.segname) {
						String(cString: $0, maxLength: 16)
					}
					section.address =  UInt64(item.addr)
					section.size =  UInt64(item.size)
					section.offset = item.offset
					section.alignment = item.align
					section.flags = item.flags

					log += "\t\(section.segmentName),\(section.name)\n"
				}
			case UInt32(bitPattern: LC_SYMTAB):
				// `symoff` (nlist array) and `stroff` (string table) are
				// ABSOLUTE FILE OFFSETS into the whole image — not offsets
				// relative to the load-command stream, so both are read from
				// `model.data` (see the legacy path's
				// `strOffset = binaryOffset + Int(symtab.stroff)` reference).
				symtab = bytes.unsafeLoad(as: symtab_command.self)
			case LC_MAIN:
				let command = bytes.unsafeLoad(as: entry_point_command.self)
				let address = model.segments.first { $0.name == "__TEXT" }?.address ?? 0
				model.entryPoint = address + command.entryoff
				model.stackSize = command.stacksize

//			case UInt32(bitPattern: LC_UNIXTHREAD):
				// Parse thread state for entry point (older binaries)
//				entryPoint = try parseUnixThread(data: data, offset: cmdOffset, cpuType: header.cpuType)

			default:
				break
			}

			bytes = bytes.extracting(droppingFirst: Int(item.cmdsize))
		}

		if let symtab {
			let symbolsStart = ContinuousClock.now
			let parsed = try parseSymbols(model, symtab)
			log += "Parsed \(symtab.nsyms) symtab entries -> \(parsed) symbols in \(symbolsStart.duration(to: .now).logDescription)\n"
		}

		let generated = symbolize(in: model)
		model.symbols.append(contentsOf: generated)

		log += "Parsed \(model.segments.count) segments, \(model.sections.count) sections, \(model.symbols.count) symbols (\(generated.count) generated) in \(start.duration(to: .now).logDescription)"
		Logger.app.info("\(log)")
		print(log)

		// Determine base address (skip __PAGEZERO which has address 0)
		let baseAddress = model.segments.first(where: { $0.name != "__PAGEZERO" && $0.address > 0 })?.address ?? model.segments.first?.address ?? 0
		model.baseAddress = baseAddress

		model.format = .machO
		model.is64 = is64Bit
		model.architecture = mapCPUType(UInt32(header.cputype))

		// Procedures are an analysis result, not part of the file format:
		// run the pass once the symbol table and sections exist.
		let proceduresStart = ContinuousClock.now
		let report = ProcedureDetector().detect(in: model)
		let proceduresLine = "Detected \(report.created) procedures in \(proceduresStart.duration(to: .now).logDescription)"
		log += proceduresLine
		Logger.app.info("\(log)")
		print(proceduresLine)
	}

	/// Decode the Mach-O symbol table into `SymbolModel` rows.
	///
	/// `n_type` is one byte split as `0xe0` N_STAB / `0x10` N_PEXT /
	/// `0x0e` N_TYPE / `0x01` N_EXT (`<mach-o/nlist.h>`). N_STAB entries are
	/// symbolic debugging records whose `n_value` is a line number or an
	/// offset rather than an address, so they are dropped — decoding them as
	/// symbols is what used to bury the real ones.
	///
	/// Runs after the load commands because `n_sect` is a 1-based ordinal over
	/// section order: a symbol is a function only when the section it lives in
	/// is executable.
	static func parseSymbols(_ model: BinaryModel, _ symtab: symtab_command) throws -> Int {
		struct Entry {
			let type: n_type
			let external: Bool
			let sect: UInt8
			let address: UInt64
			let name: String
		}

		let count = Int(symtab.nsyms)
		let symoff = Int(symtab.symoff)
		let stroff = Int(symtab.stroff)
		let entrySize = MemoryLayout<nlist_64>.size
		guard symoff >= 0, stroff >= 0, model.data.count >= symoff + count * entrySize else {
			throw BinaryLoaderError.corruptedFile("Symbol table extends past end of file (symoff=\(symoff), nsyms=\(count))")
		}

		// Pass 1: read the nlist_64 array and drop the stabs. nlist_64 is not
		// BitwiseCopyable, so each record is loaded through a Span slice.
		var entries: [Entry] = []
		entries.reserveCapacity(count)
		let symbolTable = model.data.bytes
		for i in 0..<count {
			let sym = symbolTable.extracting(droppingFirst: symoff + i * entrySize).unsafeLoad(as: nlist_64.self)
			let n_type = unsafeBitCast(sym.n_type, to: n_type_field.self)
			// The bitfields hold shifted extractions (N_TYPE >> 1, N_STAB >> 5),
			// while the SDK enums are byte values — decode from the raw byte so
			// the `switch entry.type` below can match `.N_SECT` (0x0e) etc.
			if is_stab(n_type.byte) { continue }
			let strx = sym.n_un.n_strx
			entries.append(Entry(
				type: n_type_of(n_type.byte),
				external: n_type.n_ext,
				sect: sym.n_sect,
				address: sym.n_value,
				name: strx == 0 ? "" : (model.data.readCString(at: stroff + Int(strx)) ?? "")))
		}

		// Pass 2: derive sizes. `nlist_64` has no size field, so a symbol runs
		// to the next symbol in the same section; the last symbol per section
		// has nothing to bound it and gets size 0 (an unknown size must not be
		// reported as a fabricated one-byte body).
		var addressesBySection: [UInt8: Set<UInt64>] = [:]
		for entry in entries where entry.sect != 0 {
			addressesBySection[entry.sect, default: []].insert(entry.address)
		}
		var sizes: [UInt64: UInt64] = [:]
		for section in addressesBySection.keys.sorted() {
			let sorted = Array(addressesBySection[section]!).sorted()
			for i in 0..<sorted.count {
				// Same address in several sections: the highest section
				// ordinal wins; local + global aliases at one address derive
				// the same size.
				sizes[sorted[i]] = i + 1 < sorted.count ? sorted[i + 1] - sorted[i] : 0
			}
		}

		// Dedupe: `#Unique<SymbolModel>([\.binary, \.address, \.identifier])`
		// rejects repeated (address, name) pairs, so keep the highest-preference
		// entry per pair — N_SECT (a real body) beats N_ABS beats N_UNDF, and
		// external beats local within a kind. Aliases (same address, different
		// name) and imports (different names at address 0) are kept.
		func preference(_ entry: Entry) -> Int {
			let external = entry.external ? 1 : 0
			switch entry.type {
			case .N_SECT: return 4 + external
			case .N_ABS:  return 2 + external
			default:     return external // N_UNDF, N_PBUD, N_INDR: no body in this file
			}
		}
		struct SymKey: Hashable {
			let address: UInt64
			let name: String
		}
		var winners: [SymKey: (index: Int, rank: Int)] = [:]
		for (i, entry) in entries.enumerated() {
			let rank = preference(entry)
			let key = SymKey(address: entry.address, name: entry.name)
			if let current = winners[key], current.rank >= rank { continue }
			winners[key] = (index: i, rank: rank)
		}

		var kept = 0
		for (i, entry) in entries.enumerated() where winners[SymKey(address: entry.address, name: entry.name)]?.index == i {
			let symbol = SymbolModel(in: model)
			model.symbols.append(symbol)

			// N_INDR means "this symbol is another symbol": `n_value` is a
			// string-table index, not an address, so it must not be recorded
			// as one.
			symbol.address = entry.type == .N_INDR ? 0 : entry.address
			symbol.name = entry.name
			symbol.identifier = entry.name
			symbol.size = sizes[entry.address] ?? 0

			switch entry.type {
			case .N_SECT:
				// `n_sect` is a 1-based ordinal, but `n_value` is not guaranteed
				// to sit inside it: `__mh_execute_header` is declared in `__text`
				// while pointing at the image base. Only an address really inside
				// an executable section is a function body.
				let ordinal = Int(entry.sect) - 1
				let section = ordinal >= 0 && ordinal < model.sections.count ? model.sections[ordinal] : nil
				let inCode = section?.isExecutable == true && section?.contains(address: entry.address) == true
				// Named data symbols keep `type: .unknown`: their extent is
				// usually not a single fixed-width element.
				symbol.kind = inCode ? .function : .data
				symbol.type = inCode ? .function : .unknown
				symbol.binding = entry.external ? .global : .local
			case .N_ABS:
				// Absolute symbol: `n_value` is a constant, not a load address.
				symbol.kind = .unknown
				symbol.size = 0
				symbol.binding = entry.external ? .global : .local
			case .N_UNDF, .N_PBUD, .N_INDR, .N_6:
				// Referenced here, defined elsewhere (or pre-bound to a dylib).
				symbol.kind = .unknown
				symbol.size = 0
				symbol.binding = entry.external ? .external : .undefined
			default:
				symbol.kind = .unknown
				symbol.size = 0
				symbol.binding = entry.external ? .external : .undefined
			}

			symbol.refresh()
			kept += 1
		}

		return kept
	}

	/// Eager memory-map symbolization (supersedes the printable-ASCII
	/// `scanStrings` pass).
	///
	/// Walks every non-executable section and emits `SymbolModel` rows typed
	/// by the section's Mach-O type (low byte of `flags`):
	/// - `S_CSTRING_LITERALS`: one symbol per NUL-terminated run —
	///   `__cstring` → `.ascii` (min 4 bytes), `__ustring` → `.utf16`
	///   (min 2 characters).
	/// - Pointer sections (`S_LITERAL_POINTERS`, symbol-pointer tables,
	///   `S_MOD_*_FUNC_POINTERS`, `S_INTERPOSING`,
	///   `S_LAZY_DYLIB_SYMBOL_POINTERS`) → `.ptr` per 8 bytes.
	/// - `S_4BYTE_LITERALS` / `S_INIT_FUNC_OFFSETS` → `.u32` per 4 bytes.
	/// - `S_8BYTE_LITERALS` → `.u64` per 8 bytes (the flag says literal,
	///   not pointer — no guessing).
	/// - `S_16BYTE_LITERALS` → `.u128` per 16 bytes.
	/// - Everything else (including `S_SYMBOL_STUBS` — stub width varies per
	///   architecture — and zerofill) → one `.unknown` symbol spanning the
	///   section.
	///
	/// Generated rows have `identifier == name` (`str_<vaddr>` / `DAT_<vaddr>`),
	/// `kind: .data`, `binding: .local`. Elements overlapping a named
	/// symbol's range are skipped, and a section that holds named symbols
	/// gets no section-spanning `.unknown` row.
	nonisolated static func symbolize(in model: BinaryModel) -> [SymbolModel] {
		let data = model.data

		// Ranges the symtab already owns, sorted by lower bound.
		let named: [(lo: UInt64, hi: UInt64)] = model.symbols
			.filter { $0.address != 0 && $0.size > 0 }
			.map { ($0.address, $0.address + $0.size) }
			.sorted { $0.lo < $1.lo }

		func overlapsNamed(_ lo: UInt64, _ hi: UInt64) -> Bool {
			named.contains { $0.hi > lo && $0.lo < hi }
		}

		func makeSymbol(at address: UInt64, size: UInt64, type: SymbolType, stringValue: String) -> SymbolModel {
			let symbol = SymbolModel(in: model)
			symbol.address = address
			symbol.size = size
			symbol.kind = .data
			symbol.type = type
			symbol.stringValue = stringValue
			symbol.binding = .local
			symbol.name = (type.isString ? "str_" : "DAT_") + String(format: "%llX", address)
			symbol.identifier = symbol.name
			return symbol
		}

		var result: [SymbolModel] = []

		for section in model.sections where section.size > 0 {
			// Code is symbolized through the symtab (procedures).
			guard !section.isExecutable else { continue }

			let stype = Int32(section.flags & 0xFF)
			let hasNamed = overlapsNamed(section.address, section.address + section.size)

			// Fixed element width from the section type (0 = no chunking).
			var width = 0
			var element: SymbolType = .unknown
			// S_INTERPOSING (0x100) and S_LAZY_DYLIB_SYMBOL_POINTERS (0x200)
			// share low byte 0x00 with S_REGULAR — test the full flags.
			if section.flags & 0x100 != 0 || section.flags & 0x200 != 0 {
				width = 8
				element = .ptr
			} else {
				switch stype {
				case 0x08, 0x24, 0x26, 0x29, 0x2B:  // S_LITERAL_POINTERS, symbol pointers, mod init/term
					width = 8
					element = .ptr
				case 0x1B, 0x22:  // S_INIT_FUNC_OFFSETS, S_4BYTE_LITERALS
					width = 4
					element = .u32
				case 0x25:  // S_8BYTE_LITERALS
					width = 8
					element = .u64
				case 0x2C:  // S_16BYTE_LITERALS
					width = 16
					element = .u128
				default:
					break
				}
			}

			let sectionSize = Int(section.size)
			let fileBacked = Int(section.offset) + sectionSize <= data.count

			if stype == 0x02, fileBacked {  // S_CSTRING_LITERALS
				// NUL-terminated runs; UTF-16 in `__ustring`. A run ends at a
				// zero unit; the row size includes the terminator so the
				// memory map stays contiguous.
				let isUTF16 = section.name == "__ustring"
				let unit = isUTF16 ? 2 : 1
				let minUnits = isUTF16 ? 2 : 4
				guard sectionSize % unit == 0 else { continue }
				let bytes = data.subdata(in: Int(section.offset)..<(Int(section.offset) + sectionSize))

				func flushRun(from start: Int, to end: Int) {
					let units = (end - start) / unit
					guard units >= minUnits else { return }
					let lo = section.address + UInt64(start)
					let hi = lo + UInt64(end - start)
					guard !overlapsNamed(lo, hi) else { return }
					let value = isUTF16
						? (String(data: bytes[start..<end], encoding: .utf16LittleEndian) ?? "")
						: String(decoding: bytes[start..<end], as: UTF8.self)
					result.append(makeSymbol(at: lo, size: UInt64(end - start), type: isUTF16 ? .utf16 : .ascii, stringValue: value))
				}

				var runStart = -1
				for i in stride(from: 0, to: sectionSize, by: unit) {
					let isZero = unit == 1
						? bytes[i] == 0
						: bytes[i] == 0 && bytes[i + 1] == 0
					if !isZero {
						if runStart < 0 { runStart = i }
					} else if runStart >= 0 {
						flushRun(from: runStart, to: i)
						runStart = -1
					}
				}
				// Flush a run that reaches the end of the section.
				if runStart >= 0 {
					flushRun(from: runStart, to: sectionSize)
				}
			} else if width > 0 {
				if fileBacked {
					for off in stride(from: 0, to: sectionSize, by: width) {
						let count = min(width, sectionSize - off)
						let lo = section.address + UInt64(off)
						let hi = lo + UInt64(count)
						guard !overlapsNamed(lo, hi) else { continue }
						// A trailing partial element is not a full instance
						// of the section's type.
						result.append(makeSymbol(at: lo, size: UInt64(count), type: count == width ? element : .unknown, stringValue: ""))
					}
				} else if !hasNamed {
					// Not file-backed (e.g. zerofill with a literal flag):
					// nothing to chunk, fall back to a single row.
					result.append(makeSymbol(at: section.address, size: section.size, type: .unknown, stringValue: ""))
				}
			} else if !hasNamed {
				// Untyped section: one symbol spanning it.
				result.append(makeSymbol(at: section.address, size: section.size, type: .unknown, stringValue: ""))
			}
		}

		return result
	}

	static func mapCPUType(_ cpuType: UInt32) -> Architecture {
		switch cpuType {
		case UInt32(bitPattern: CPU_TYPE_X86_64):
			return .x86_64
		case UInt32(bitPattern: CPU_TYPE_ARM64):
			return .arm64
		case UInt32(bitPattern: CPU_TYPE_X86):
			return .i386
		case UInt32(bitPattern: CPU_TYPE_ARM):
			return .armv7
		default:
			return .unknown
		}
	}
}
