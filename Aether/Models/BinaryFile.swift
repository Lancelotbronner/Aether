import Foundation
import Combine

/// Represents a loaded binary file
@Observable
nonisolated final class BinaryFile: Identifiable {
	let format: BinaryFormat
	let architecture: Architecture
	let endianness: Endianness
	let is64Bit: Bool

	// File metadata
	let fileSize: Int
	let entryPoint: UInt64
	let baseAddress: UInt64

	// Sections and segments
	var sections: [Section]
	var segments: [Segment]

	// Symbols
	var symbols: [Symbol]

	// Raw data
	let data: Data

	init(
		format: BinaryFormat,
		architecture: Architecture,
		endianness: Endianness,
		is64Bit: Bool,
		fileSize: Int,
		entryPoint: UInt64,
		baseAddress: UInt64,
		sections: [Section],
		segments: [Segment],
		symbols: [Symbol],
		data: Data
	) {
		self.format = format
		self.architecture = architecture
		self.endianness = endianness
		self.is64Bit = is64Bit
		self.fileSize = fileSize
		self.entryPoint = entryPoint
		self.baseAddress = baseAddress
		self.sections = sections
		self.segments = segments
		self.symbols = symbols
		self.data = data
	}

	var name: String {
		"Unnamed"
	}

	/// Find section containing address
	func section(containing address: UInt64) -> Section? {
		sections.first { $0.contains(address: address) }
	}

	/// Find segment containing address
	func segment(containing address: UInt64) -> Segment? {
		segments.first { $0.contains(address: address) }
	}

	func read(at address: UInt64, count: Int) -> Data? {
		data[address..<(address + UInt64(count))]
	}

	/// Read null-terminated string at address
	func readString(at address: UInt64, maxLength: Int = 1024) -> String? {
		var r = Int(address)
		while data[r] != 0 {
			r += 1
		}
		return String(data: data[address..<UInt64(r)], encoding: .utf8)
	}
}

/// Binary segment (e.g., __TEXT, __DATA)
@Observable
nonisolated final class Segment: Identifiable, Sendable {
	let name: String
	let address: UInt64
	let size: UInt64
	let fileOffset: UInt64
	let fileSize: UInt64
	let maxProtection: UInt32
	let initProtection: UInt32

	init(name: String, address: UInt64, size: UInt64, fileOffset: UInt64, fileSize: UInt64, maxProtection: UInt32, initProtection: UInt32) {
		self.name = name
		self.address = address
		self.size = size
		self.fileOffset = fileOffset
		self.fileSize = fileSize
		self.maxProtection = maxProtection
		self.initProtection = initProtection
	}

	var isReadable: Bool { initProtection & 1 != 0 }
	var isWritable: Bool { initProtection & 2 != 0 }
	var isExecutable: Bool { initProtection & 4 != 0 }

	func contains(address addr: UInt64) -> Bool {
		addr >= address && addr < (address + size)
	}

	var protectionString: String {
		var result = ""
		result += isReadable ? "r" : "-"
		result += isWritable ? "w" : "-"
		result += isExecutable ? "x" : "-"
		return result
	}
}

/// Binary section (e.g., __text, __data)
@Observable
nonisolated final class Section: Identifiable, Hashable, Sendable {
	let name: String
	let segmentName: String
	let address: UInt64
	let size: UInt64
	let offset: UInt32
	let alignment: UInt32
	let flags: UInt32
	let data: Data

	init(name: String, segmentName: String, address: UInt64, size: UInt64, offset: UInt32, alignment: UInt32, flags: UInt32, data: Data) {
		self.name = name
		self.segmentName = segmentName
		self.address = address
		self.size = size
		self.offset = offset
		self.alignment = alignment
		self.flags = flags
		self.data = data
	}

	var fullName: String { "\(segmentName),\(name)" }

	var isExecutable: Bool {
		// Mach-O: S_ATTR_PURE_INSTRUCTIONS or S_ATTR_SOME_INSTRUCTIONS
		// PE: IMAGE_SCN_MEM_EXECUTE (0x20000000) or IMAGE_SCN_CNT_CODE (0x20)
		flags & 0x80000000 != 0 || flags & 0x00000400 != 0 ||
		flags & 0x20000000 != 0 || flags & 0x00000020 != 0
	}

	var isZeroFill: Bool {
		// S_ZEROFILL
		(flags & 0xFF) == 1
	}

	var containsCode: Bool {
		isExecutable || name == "__text" || name == ".text" || name == ".code"
	}

	func contains(address addr: UInt64) -> Bool {
		addr >= address && addr < (address + size)
	}

	static func == (lhs: Section, rhs: Section) -> Bool {
		lhs === rhs
	}

	func hash(into hasher: inout Hasher) {
		hasher.combine(ObjectIdentifier(self))
	}
}
