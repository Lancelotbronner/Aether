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
			model.strings.removeAll()
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
				let command = bytes.unsafeLoad(as: symtab_command.self)
				let stringTable = model.data
				let symbolTable = model.data

				model.symbols.reserveCapacity(model.symbols.count + Int(command.nsyms))

				let start = ContinuousClock.now
				log += "Parsing \(command.nsyms) symbols\n"

				// Pass 1: read the nlist_64 array (bounds-guarded against a
				// truncated table) and remember everything the size derivation
				// in pass 2 needs. nlist_64 has no size field — sizes must be
				// derived from the next symbol in the same section.
				struct SymbolEntry {
					let sym: nlist_64
					let name: String
				}

				let entrySize = MemoryLayout<nlist_64>.size
				guard symbolTable.count >= Int(command.symoff) + Int(command.nsyms) * entrySize else {
					throw BinaryLoaderError.corruptedFile("Symbol table extends past end of file (symoff=\(command.symoff), nsyms=\(command.nsyms))")
				}

				//FIXME: MachO's nlist_64 doesn't conform to BitwiseCopyable, wait until fixed by Apple
				let rawSymbols = [nlist_64](
					unsafeUninitializedCapacity: Int(command.nsyms),
					initializingWith: { buffer, count in
						for i in 0..<Int(command.nsyms) {
							buffer[i] = symbolTable.bytes
								.extracting(droppingFirst: Int(command.symoff) + i * entrySize)
								.unsafeLoad(as: nlist_64.self)
						}
						count = Int(command.nsyms)
					})

				let entries = rawSymbols.map { sym in
					SymbolEntry(
						sym: sym,
						name: sym.n_un.n_strx == 0 ? "" :
							stringTable.readCString(at: Int(command.stroff) + Int(sym.n_un.n_strx)) ?? "")
				}

				// Pass 2: derive sizes. Per section (n_sect), in ascending
				// address order, a symbol runs until the next symbol in the
				// same section. The last symbol per section and every
				// N_ABS/N_UNDF symbol has no next symbol to bound it — those
				// get size 0 (recorded decision: 0, not the SymbolModel
				// default of 1; an unknown size must not be reported as a
				// fabricated one-byte body).
				var sectionSizes: [UInt8: Set<UInt64>] = [:]
				for entry in entries where entry.sym.n_sect != 0 {
					sectionSizes[entry.sym.n_sect, default: []].insert(entry.sym.n_value)
				}
				var sizes: [UInt64: UInt64] = [:]
				for section in sectionSizes.keys.sorted() {
					let sorted = Array(sectionSizes[section]!).sorted()
					for i in 0..<sorted.count {
						// Same address in several sections: the highest
						// section ordinal wins; local + global aliases at
						// the same address derive the same size.
						sizes[sorted[i]] = i + 1 < sorted.count
							? sorted[i + 1] - sorted[i] : 0
					}
				}

				// In-pass dedupe (B3): a symtab can repeat the exact same
				// (address, name) pair; `#Unique<SymbolModel>([\.binary,
				// \.address, \.identifier])` rejects such duplicates, so keep
				// only the highest-preference entry per (address, name):
				// N_SECT (real body) beats N_ABS beats N_UNDF, external beats
				// local within a kind. Aliases (same address, different name)
				// and imports (different names at address 0) are kept.
				func preference(_ sym: nlist_64) -> Int {
					let n_type = unsafeBitCast(sym.n_type, to: n_type_field.self)
					let external = n_type.n_ext ? 1 : 0
					switch n_type.n_type {
					case .N_SECT:
						return 4 + external
					case .N_ABS:
						return 2 + external
					default:
						// N_UNDF and the rest: no body in this file.
						return external
					}
				}
				struct SymKey: Hashable {
					let address: UInt64
					let name: String
				}
				var winners: [SymKey: (index: Int, rank: Int)] = [:]
				for (i, entry) in entries.enumerated() {
					let rank = preference(entry.sym)
					let key = SymKey(address: entry.sym.n_value, name: entry.name)
					if let current = winners[key], current.rank >= rank {
						continue
					}
					winners[key] = (index: i, rank: rank)
				}
				let kept = Set(winners.values.map { $0.index })

				for (i, entry) in entries.enumerated() where kept.contains(i) {
					let sym = entry.sym
					let symbol = SymbolModel(in: model)
					model.symbols.append(symbol)

					symbol.address = sym.n_value
					// Aliases at the same address (local + global) share the
					// derived size; N_SECT symbols without a derived entry
					// (cannot happen: n_sect != 0 implies a dict entry) fall
					// back to the SymbolModel default.
					symbol.size = sizes[sym.n_value] ?? 1

					symbol.name = entry.name
					symbol.identifier = entry.name

					let n_type = unsafeBitCast(sym.n_type, to: n_type_field.self)
					let isExternal = n_type.n_ext

					switch n_type.n_type {
					case .N_ABS:
						// Absolute symbols: n_value is a constant, not a load
						// address — never treat as a function.
						symbol.type = .unknown
						symbol.size = 0
						symbol.binding = isExternal ? .global : .local
					case .N_SECT:
						// Check if this looks like a function (in __TEXT,__text)
						symbol.type = sym.n_sect == 1 ? .function : .data
						symbol.binding = isExternal ? .global : .local
					default:
						// N_UNDF and the rest: no body in this file.
						symbol.type = .unknown
						symbol.size = 0
						symbol.binding = isExternal ? .external : .undefined
					}

					symbol.refresh()

					if symbol.type == .function && symbol.address != 0 {
						let procedure = ProcedureModel(is: symbol, in: model)
						model.procedures.append(procedure)
					}
				}

				log += "Parsed \(command.nsyms) symbols"
				+ (entries.count - kept.count > 0 ? " (\(entries.count - kept.count) same-address aliases collapsed)" : "")
				+ " in \(start.duration(to: .now).logDescription)\n"
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

		model.strings = scanStrings(in: model)

		log += "Parsed \(model.segments.count) segments, \(model.sections.count) sections, \(model.symbols.count) symbols, \(model.strings.count) strings in \(start.duration(to: .now).logDescription)"
		Logger.app.info("\(log)")
		print(log)

		// Determine base address (skip __PAGEZERO which has address 0)
		let baseAddress = model.segments.first(where: { $0.name != "__PAGEZERO" && $0.address > 0 })?.address ?? model.segments.first?.address ?? 0
		model.baseAddress = baseAddress

		model.format = .machO
		model.is64 = is64Bit
		model.architecture = mapCPUType(UInt32(header.cputype))
	}

	/// Eager C-string scan (Task 6, B11).
	///
	/// Scans the `__TEXT` segment's file bytes in a single linear pass for
	/// printable-ASCII runs of at least 4 bytes and inserts one `StringModel`
	/// per hit with `cached` set, so the Strings tab is populated immediately
	/// at Load.
	///
	/// Refinement: if the `__TEXT` segment declares a `__cstring` section, only
	/// that section's bytes are scanned (where the compiler puts C-strings);
	/// otherwise the whole segment is scanned so binaries without `__cstring`
	/// still get string coverage. Virtual address = region address + intra-region
	/// file offset.
	nonisolated static func scanStrings(in model: BinaryModel) -> [StringModel] {
		let data = model.data
		guard let text = model.segments.first(where: { $0.name == "__TEXT" }),
			  text.fileSize > 0,
			  Int(text.fileOffset) + Int(text.fileSize) <= data.count else { return [] }

		// Prefer the __cstring section if declared; else scan the whole segment.
		let region: (address: UInt64, fileStart: Int, fileEnd: Int)
		if let cstring = text.sections.first(where: { $0.name == "__cstring" }),
		   cstring.size > 0,
		   Int(cstring.offset) + Int(cstring.size) <= data.count {
			region = (cstring.address, Int(cstring.offset), Int(cstring.offset) + Int(cstring.size))
		} else {
			region = (text.address, Int(text.fileOffset), Int(text.fileOffset) + Int(text.fileSize))
		}
		let bytes = data.subdata(in: region.fileStart..<region.fileEnd)
		let minLen = 4

		var result: [StringModel] = []
		var runStart = -1
		for i in 0..<bytes.count {
			let b = bytes[i]
			if b >= 0x20 && b < 0x7F {
				if runStart < 0 { runStart = i }
			} else {
				let len = i - runStart
				if runStart >= 0 && len >= minLen {
					let value = String(decoding: bytes[runStart..<i], as: UTF8.self)
					let vaddr = region.address + UInt64(runStart)
					result.append(StringModel(binary: model, address: vaddr, encoding: .ascii, cached: value))
				}
				runStart = -1
			}
		}
		// Flush a run that reaches the end of the region.
		if runStart >= 0 {
			let len = bytes.count - runStart
			if len >= minLen {
				let value = String(decoding: bytes[runStart..<bytes.count], as: UTF8.self)
				let vaddr = region.address + UInt64(runStart)
				result.append(StringModel(binary: model, address: vaddr, encoding: .ascii, cached: value))
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
