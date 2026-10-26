import Foundation
import MachO
import CoreAether
import OSLog
import AetherKit

/// Mach-O binary format loader
nonisolated final class MachOLoader: BinaryLoaderProtocol {

	// MARK: - Protocol Implementation

	func canLoad(data: Data) -> Bool {
		guard let magic = data.readUInt32LE(at: 0) else { return false }
		return magic == MH_MAGIC || magic == MH_CIGAM ||
		magic == MH_MAGIC_64 || magic == MH_CIGAM_64 ||
		magic == FAT_MAGIC || magic == FAT_CIGAM
	}

	func load(data: Data) throws -> BinaryFile {
		guard let magic = data.readUInt32LE(at: 0) else {
			throw BinaryLoaderError.invalidHeader
		}

		// Handle fat/universal binaries
		if magic == FAT_MAGIC || magic == FAT_CIGAM {
			return try loadFatBinary(data: data, swapped: magic == FAT_CIGAM)
		}

		return try loadMachO(data: data, offset: 0)
	}

	@concurrent
	static func load(_ model: BinaryModel) async throws {
		// Handle fat/universal binaries
//		if magic == FAT_MAGIC || magic == FAT_CIGAM {
//			return try loadFatBinary(data: model.embedded, swapped: magic == FAT_CIGAM)
//		}

		return try machO(for: model)
	}

	// MARK: - Fat Binary Loading

	private func loadFatBinary(data: Data, swapped: Bool) throws -> BinaryFile {
		// Fat header is ALWAYS big-endian, regardless of host architecture
		guard let nfatArch = data.readUInt32BE(at: 4) else {
			throw BinaryLoaderError.invalidHeader
		}

		// Find the best architecture (prefer arm64, then x86_64)
		var bestOffset: UInt32 = 0
		var bestArch: UInt32 = 0

		for i in 0..<nfatArch {
			let archOffset = 8 + Int(i) * 20
			// Fat arch entries are also big-endian
			guard let cpuType = data.readUInt32BE(at: archOffset) else { continue }
			guard let offset = data.readUInt32BE(at: archOffset + 8) else { continue }

			// Prefer ARM64, then x86_64
			if cpuType == CPU_TYPE_ARM64 {
				bestOffset = offset
				bestArch = cpuType
				break
			} else if cpuType == CPU_TYPE_X86_64 && bestArch != CPU_TYPE_ARM64 {
				bestOffset = offset
				bestArch = cpuType
			} else if bestOffset == 0 {
				bestOffset = offset
				bestArch = cpuType
			}
		}

		return try loadMachO(data: data, offset: Int(bestOffset))
	}

	// MARK: - Mach-O Loading

	static func machO(for model: BinaryModel) throws {
		var bytes = model.data.bytes
		let header = bytes.unsafeLoad(as: mach_header_64.self)

		let is64Bit = header.magic == MH_MAGIC_64 || header.magic == MH_CIGAM_64
		let swapped = header.magic == MH_CIGAM || header.magic == MH_CIGAM_64
		model.endian = swapped ? .big : .little

		let start = ContinuousClock.now
		var log = "Mach-O: \(bytes.byteCount) bytes, \(is64Bit ? "64-bit" : "32-bit")\(swapped ? ", byte-swapped" : "")\n"

		if !is64Bit {
			fatalError("32-bit files aren't supported")
		}

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

				for entry in entries {
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

				log += "Parsed \(command.nsyms) symbols in \(start.duration(to: .now).logDescription)\n"
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
		log += "Parsed \(model.segments.count) segments, \(model.sections.count) sections, \(model.symbols.count) symbols in \(start.duration(to: .now).logDescription)"
		Logger.app.info("\(log)")

		// Determine base address (skip __PAGEZERO which has address 0)
		let baseAddress = model.segments.first(where: { $0.name != "__PAGEZERO" && $0.address > 0 })?.address ?? model.segments.first?.address ?? 0
		model.baseAddress = baseAddress

		model.format = .machO
		model.is64 = is64Bit
		model.architecture = mapCPUType(UInt32(header.cputype))
	}

	private func loadMachO(data: Data, offset: Int) throws -> BinaryFile {
		guard let magic = data.readUInt32LE(at: offset) else {
			throw BinaryLoaderError.invalidHeader
		}

		let is64Bit = magic == MH_MAGIC_64 || magic == MH_CIGAM_64
		let swapped = magic == MH_CIGAM || magic == MH_CIGAM_64
		let start = ContinuousClock.now
		Logger.app.info("Mach-O: \(data.count) bytes, \(is64Bit ? "64-bit" : "32-bit")\(swapped ? ", byte-swapped" : "")")

		// Parse header
		let header = try parseMachOHeader(data: data, offset: offset, is64Bit: is64Bit, swapped: swapped)

		// Parse load commands
		let headerSize = is64Bit ? 32 : 28
		var cmdOffset = offset + headerSize

		var segments: [Segment] = []
		var sections: [_Section] = []
		var symbols: [Symbol] = []
		var entryPoint: UInt64 = 0

		Logger.app.debug("Parsing \(header.ncmds) load commands")
		for _ in 0..<header.ncmds {
			guard let cmd = data.readUInt32LE(at: cmdOffset),
				  let cmdSize = data.readUInt32LE(at: cmdOffset + 4) else {
				break
			}

			switch cmd {
			case UInt32(bitPattern: LC_SEGMENT):
				let (seg, sects) = try parseSegment32(data: data, offset: cmdOffset, binaryData: data, binaryOffset: offset)
				segments.append(seg)
				sections.append(contentsOf: sects)
			case UInt32(bitPattern: LC_SEGMENT_64):
				try parseSegment64(data: data, offset: cmdOffset, binaryData: data, binaryOffset: offset, into: &segments, into: &sections)
			case UInt32(bitPattern: LC_SYMTAB):
				try parseSymtab(data: data, offset: cmdOffset, is64Bit: is64Bit, binaryOffset: offset, into: &symbols)
			case LC_MAIN:
				if let entryOff = data.readUInt64LE(at: cmdOffset + 8) {
					// Find __TEXT segment to calculate entry point
					if let textSeg = segments.first(where: { $0.name == "__TEXT" }) {
						entryPoint = textSeg.address + entryOff
					}
				}

			case UInt32(bitPattern: LC_UNIXTHREAD):
				// Parse thread state for entry point (older binaries)
				entryPoint = try parseUnixThread(data: data, offset: cmdOffset, cpuType: header.cpuType)

			default:
				break
			}

			cmdOffset += Int(cmdSize)
		}
		Logger.app.info("Parsed \(segments.count) segments, \(sections.count) sections, \(symbols.count) symbols in \(start.duration(to: .now).logDescription)")

		// Determine base address (skip __PAGEZERO which has address 0)
		let baseAddress = segments.first(where: { $0.name != "__PAGEZERO" && $0.address > 0 })?.address ?? segments.first?.address ?? 0

		return BinaryFile(
			format: .machO,
			architecture: Self.mapCPUType(header.cpuType),
			endianness: swapped ? .big : .little,
			is64Bit: is64Bit,
			fileSize: data.count,
			entryPoint: entryPoint,
			baseAddress: baseAddress,
			sections: sections,
			segments: segments,
			symbols: symbols,
			data: data
		)
	}

	// MARK: - Header Parsing

	private struct MachOHeader {
		let magic: UInt32
		let cpuType: UInt32
		let cpuSubtype: UInt32
		let fileType: UInt32
		let ncmds: UInt32
		let sizeOfCmds: UInt32
		let flags: UInt32
	}

	private func parseMachOHeader(data: Data, offset: Int, is64Bit: Bool, swapped: Bool) throws -> MachOHeader {
		guard let magic = data.readUInt32LE(at: offset),
			  let cpuType = data.readUInt32LE(at: offset + 4),
			  let cpuSubtype = data.readUInt32LE(at: offset + 8),
			  let fileType = data.readUInt32LE(at: offset + 12),
			  let ncmds = data.readUInt32LE(at: offset + 16),
			  let sizeOfCmds = data.readUInt32LE(at: offset + 20),
			  let flags = data.readUInt32LE(at: offset + 24) else {
			throw BinaryLoaderError.invalidHeader
		}

		return MachOHeader(
			magic: magic,
			cpuType: swapped ? cpuType.byteSwapped : cpuType,
			cpuSubtype: swapped ? cpuSubtype.byteSwapped : cpuSubtype,
			fileType: swapped ? fileType.byteSwapped : fileType,
			ncmds: swapped ? ncmds.byteSwapped : ncmds,
			sizeOfCmds: swapped ? sizeOfCmds.byteSwapped : sizeOfCmds,
			flags: swapped ? flags.byteSwapped : flags
		)
	}

	// MARK: - Segment Parsing

	private func parseSegment32(data: Data, offset: Int, binaryData: Data, binaryOffset: Int) throws -> (Segment, [_Section]) {
		let segNameData = data.subdata(in: (offset + 8)..<(offset + 24))
		let segName = String(data: segNameData, encoding: .utf8)?.trimmingCharacters(in: .init(charactersIn: "\0")) ?? ""

		guard let vmaddr = data.readUInt32LE(at: offset + 24),
			  let vmsize = data.readUInt32LE(at: offset + 28),
			  let fileoff = data.readUInt32LE(at: offset + 32),
			  let filesize = data.readUInt32LE(at: offset + 36),
			  let maxprot = data.readUInt32LE(at: offset + 40),
			  let initprot = data.readUInt32LE(at: offset + 44),
			  let nsects = data.readUInt32LE(at: offset + 48) else {
			throw BinaryLoaderError.corruptedFile("Invalid segment")
		}

		let segment = Segment(
			name: segName,
			address: UInt64(vmaddr),
			size: UInt64(vmsize),
			fileOffset: UInt64(fileoff),
			fileSize: UInt64(filesize),
			maxProtection: maxprot,
			initProtection: initprot
		)

		var sections: [_Section] = []
		var sectOffset = offset + 56

		for _ in 0..<nsects {
			let section = try parseSection32(data: data, offset: sectOffset, segName: segName, binaryData: binaryData, binaryOffset: binaryOffset)
			sections.append(section)
			sectOffset += 68
		}

		return (segment, sections)
	}

	private func parseSegment64(
		data: Data,
		offset: Int,
		binaryData: Data,
		binaryOffset: Int,
		into segments: inout [Segment],
		into sections: inout [_Section]
	) throws {
		let seg = data.bytes.unsafeLoadUnaligned(fromByteOffset: offset, as: segment_command_64.self)
		let name = withUnsafeBytes(of: seg.segname) {
			String(cString: $0, maxLength: 16)
		}

		segments.append(Segment(
			name: name,
			address: seg.vmaddr,
			size: seg.vmsize,
			fileOffset: seg.fileoff,
			fileSize: seg.filesize,
			maxProtection: UInt32(bitPattern: seg.maxprot),
			initProtection: UInt32(bitPattern: seg.initprot)
		))

		Logger.app.debug("Parsing \(seg.nsects) sections in \(name)")
		try data.dropFirst(offset + MemoryLayout<segment_command_64>.size).withUnsafeBytes { bytes in
			for sect in bytes.bindMemory(to: section_64.self).prefix(Int(seg.nsects)) {
				let section = try parseSection64(sect, data: data, segName: name, binaryData: binaryData, binaryOffset: binaryOffset)
				sections.append(section)
			}
		}
	}

	// MARK: - Section Parsing

	private func parseSection32(data: Data, offset: Int, segName: String, binaryData: Data, binaryOffset: Int) throws -> _Section {
		let sectNameData = data.subdata(in: offset..<(offset + 16))
		let sectName = String(data: sectNameData, encoding: .utf8)?.trimmingCharacters(in: .init(charactersIn: "\0")) ?? ""

		guard let addr = data.readUInt32LE(at: offset + 32),
			  let size = data.readUInt32LE(at: offset + 36),
			  let fileOffset = data.readUInt32LE(at: offset + 40),
			  let align = data.readUInt32LE(at: offset + 44),
			  let flags = data.readUInt32LE(at: offset + 52) else {
			throw BinaryLoaderError.corruptedFile("Invalid section")
		}

		// Read section data
		let sectionData: Data
		if size > 0 && fileOffset > 0 {
			let dataOffset = binaryOffset + Int(fileOffset)
			sectionData = binaryData.subdata(in: dataOffset..<(dataOffset + Int(size)))
		} else {
			sectionData = Data()
		}

		return _Section(
			name: sectName,
			segmentName: segName,
			address: UInt64(addr),
			size: UInt64(size),
			offset: fileOffset,
			alignment: align,
			flags: flags,
			data: sectionData
		)
	}

	private func parseSection64(_ sect: section_64, data: Data, segName: String, binaryData: Data, binaryOffset: Int) throws -> _Section {
		let sectionName = withUnsafeBytes(of: sect.sectname) {
			String(cString: $0, maxLength: 16)
		}
		let segmentName = withUnsafeBytes(of: sect.segname) {
			String(cString: $0, maxLength: 16)
		}

		let lowerBound = binaryOffset + Int(sect.offset)
		let upperBound = lowerBound + Int(sect.size)
		let data = binaryData[lowerBound..<upperBound]

		Logger.app.debug("    \(segmentName),\(sectionName)")
		return _Section(
			name: sectionName,
			segmentName: segmentName,
			address: sect.addr,
			size: sect.size,
			offset: sect.offset,
			alignment: sect.align,
			flags: sect.flags,
			data: data
		)
	}

	// MARK: - Symbol Table Parsing

	private func parseSymtab(data: Data, offset: Int, is64Bit: Bool, binaryOffset: Int, into symbols: inout [Symbol]) throws {
		let symtab = data.bytes.unsafeLoadUnaligned(fromByteOffset: offset, as: symtab_command.self)
		let strOffset = binaryOffset + Int(symtab.stroff)
		symbols.reserveCapacity(symbols.count + Int(symtab.nsyms))
		let start = ContinuousClock.now
		Logger.app.debug("Parsing \(symtab.nsyms) symbols")
		data
			.dropFirst(binaryOffset + Int(symtab.symoff))
			.withUnsafeBytes { b in
				if is64Bit {
					for sym in b.bindMemory(to: nlist_64.self).prefix(Int(symtab.nsyms)) {
						let symbol = processSymbol(from: sym, with: data, strOffset: strOffset)
						symbols.append(symbol)
					}
				} else {
					for sym in b.bindMemory(to: nlist.self).prefix(Int(symtab.nsyms)) {
						let nlist64 = nlist_64(
							n_un: .init(n_strx: sym.n_un.n_strx),
							n_type: sym.n_type,
							n_sect: sym.n_sect,
							n_desc: UInt16(bitPattern: sym.n_desc),
							n_value: UInt64(sym.n_value))
						let symbol = processSymbol(from: nlist64, with: data, strOffset: strOffset)
						symbols.append(symbol)
					}
				}
			}
		Logger.app.info("Parsed \(symtab.nsyms) symbols in \(start.duration(to: .now).logDescription)")
	}

	private func processSymbol(
		from sym: nlist_64,
		with data: Data,
		strOffset: Int,
	) -> Symbol {
		let name = sym.n_un.n_strx == 0 ? "" : data.readCString(at: strOffset + Int(sym.n_un.n_strx)) ?? ""
		let n_type = unsafeBitCast(sym.n_type, to: n_type_field.self)
		let symType: SymbolType
		let binding: SymbolBinding
		let isExternal = n_type.n_ext

		switch n_type.n_type {
		case .N_ABS:
			symType = .function
			binding = isExternal ? .global : .local
		case .N_SECT:
			// Check if this looks like a function (in __TEXT,__text)
			symType = sym.n_sect == 1 ? .function : .data
			binding = isExternal ? .global : .local
		default:
			symType = .unknown
			binding = isExternal ? .external : .undefined
		}

		return Symbol(
			name: name,
			address: sym.n_value,
			size: 0,
			type: symType,
			binding: binding)
	}

	// MARK: - Thread State Parsing

	private func parseUnixThread(data: Data, offset: Int, cpuType: UInt32) throws -> UInt64 {
		// Skip cmd and cmdsize (8 bytes), then flavor and count (8 bytes)
		let stateOffset = offset + 16

		switch cpuType {
		case UInt32(bitPattern: CPU_TYPE_X86_64):
			// RIP is at offset 16*8 in x86_64 thread state
			if let rip = data.readUInt64LE(at: stateOffset + 16 * 8) {
				return rip
			}
		case UInt32(bitPattern: CPU_TYPE_ARM64):
			// PC is at offset 32*8 in ARM64 thread state
			if let pc = data.readUInt64LE(at: stateOffset + 32 * 8) {
				return pc
			}
		case UInt32(bitPattern: CPU_TYPE_X86):
			// EIP is at offset 10*4 in i386 thread state
			if let eip = data.readUInt32LE(at: stateOffset + 10 * 4) {
				return UInt64(eip)
			}
		default:
			break
		}

		return 0
	}

	// MARK: - Helpers

	private static func mapCPUType(_ cpuType: UInt32) -> Architecture {
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
