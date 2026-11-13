import ArgumentParser
import AetherKit
import Foundation
import SwiftData

struct BytesCommand: AsyncParsableCommand {
	static let configuration = CommandConfiguration(
		commandName: "bytes",
		abstract: "Print the file bytes at an address, as a hex dump or typed values.")

	@OptionGroup var aether: AetherOptions

	@Option(help: "Program to read from; required when the project holds several")
	var binary: String?

	@Argument(help: "Address to read at: decimal, 0x…, @…, off:<file offset> or a symbol name")
	var address: AddressArgument

	@Option(help: "Bytes to dump (default 64, max 4096), or values to read under --as (default 1, max 256)")
	var length: UInt64 = 0

	@Option(name: .customLong("as"), help: "Typed read instead of a hex dump: u8 u16 u32 u64 f32 f64 ptr cstr wstr")
	var read: ReadKind?

	mutating func run() async throws {
		let context = try aether.backgroundContext()
		let program = try requireProgram(named: binary, in: context)
		let address = try resolveAddress(address, named: program.name, in: context)
		guard let offset = fileOffset(of: address, in: program) else {
			throw ByteError.notInSegment(address: address, program: program.name)
		}

		if let kind = read {
			let values = length == 0 ? 1 : Int(length)
			guard values <= 256 else { throw ByteError.tooLong(asked: UInt64(values), max: 256) }
			print(header(address: address, offset: offset, program: program, tail: ["read=\(kind)", "count=\(values)"]))
			try dumpTyped(kind, address: address, offset: offset, values: values, in: program)
		} else {
			let bytes = length == 0 ? 64 : Int(length)
			guard bytes <= 4096 else { throw ByteError.tooLong(asked: UInt64(bytes), max: 4096) }
			let shown = min(bytes, max(0, program.data.count - Int(offset)))
			guard shown > 0 else {
				throw ByteError.noFileBytes(address: address, offset: offset, program: program.name)
			}
			print(header(address: address, offset: offset, program: program, tail: ["bytes=\(shown)"] + (shown < bytes ? ["asked=\(bytes)"] : [])))
			dumpHex(address: address, offset: offset, bytes: shown, in: program)
		}
	}

	/// The same `key=value` line `addr` prints, so a hexdump, a typed read and
	/// `addr` all agree about where they are in the file.
	private func header(address: UInt64, offset: UInt64, program: BinaryModel, tail: [String]) -> String {
		([
			"@\(hex(address))",
			"off=\(hex(offset))",
			"program=" + program.name,
			"segment=" + (program.segment(containing: address).map { $0.name } ?? "none"),
			"section=" + (program.section(containing: address).map { $0.fullName } ?? "none"),
		] + tail).joined(separator: " ")
	}

	/// 16-byte rows: address, hex, ASCII gutter. Written here rather than
	/// reusing AetherKit's `format(hex:)`, which shifts by `baseAddress` instead
	/// of the segment table and says nothing about the row it is on.
	private func dumpHex(address: UInt64, offset: UInt64, bytes: Int, in program: BinaryModel) {
		var index = 0
		while index < bytes {
			let rowWidth = min(16, bytes - index)
			var cells = ""
			var gutter = ""
			for column in 0..<rowWidth {
				let byte = program.data[Int(offset) + index + column]
				cells += String(format: "%02X ", byte)
				gutter += byte >= 0x20 && byte <= 0x7E ? String(Character(UnicodeScalar(byte))) : "."
			}
			if rowWidth < 16 {
				cells += String(repeating: " ", count: (16 - rowWidth) * 3)
			}
			print("\(hex(address + UInt64(index))):\(cells)|\(gutter)|")
			index += rowWidth
		}
	}

	/// Consecutive values continue after the previous one, which is the only way
	/// a string read composes: a `cstr` consumes its terminator.
	private func dumpTyped(_ kind: ReadKind, address: UInt64, offset: UInt64, values: Int, in program: BinaryModel) throws {
		var consumed = 0
		var done = 0
		for _ in 0..<values {
			let valueAddress = address + UInt64(consumed)
			guard let (text, width) = readValue(kind, at: Int(offset) + consumed, in: program) else {
				if done == 0 {
					throw ByteError.noFileBytes(address: address, offset: offset, program: program.name)
				}
				throw ByteError.stopped(address: valueAddress, program: program.name, values: values, done: done)
			}
			print("\(hex(valueAddress)) \(kind) = \(text)")
			done += 1
			guard width > 0 else { break }
			consumed += width
		}
	}

	private func readValue(_ kind: ReadKind, at offset: Int, in program: BinaryModel) -> (String, Int)? {
		if kind == .cstr || kind == .wstr {
			return readString(kind, at: offset, in: program)
		}
		let width = kind == .ptr ? (program.is64 ? 8 : 4) : kind.width
		guard offset >= 0, offset + width <= program.data.count else { return nil }

		// The program's own endianness decides the byte order; `unknown` does
		// not exist as a case, so little is the only fallback the schema allows.
		let bigEndian = program.endian == .big
		var value: UInt64 = 0
		for index in 0..<width {
			let shift = UInt64(bigEndian ? index : width - 1 - index) * 8
			value |= UInt64(program.data[offset + index]) << shift
		}

		switch kind {
		case .f32:
			return (String(Float(bitPattern: UInt32(value))), width)
		case .f64:
			return (String(Double(bitPattern: value)), width)
		default:
			return ("0x\(pad(value, digits: width * 2)) (\(value))", width)
		}
	}

	/// Strings have no width of their own: the terminator ends them, and an
	/// unterminated run is capped at 512 units rather than dumping the rest of
	/// the file, with `…` marking that the cap was what stopped it.
	private func readString(_ kind: ReadKind, at offset: Int, in program: BinaryModel) -> (String, Int)? {
		guard offset >= 0, offset < program.data.count else { return nil }
		var units: [UInt16] = []
		var index = offset
		var truncated = false

		if kind == .cstr {
			while index < program.data.count, program.data[index] != 0, units.count < 512 {
				units.append(UInt16(program.data[index]))
				index += 1
			}
			if index < program.data.count, program.data[index] == 0 {
				index += 1
			} else {
				truncated = true
			}
		} else {
			while index + 1 < program.data.count, units.count < 512 {
				let unit = u16(program.data, at: index, bigEndian: program.endian == .big)
				guard unit != 0 else { break }
				units.append(unit)
				index += 2
			}
			if index + 1 < program.data.count, u16(program.data, at: index, bigEndian: program.endian == .big) == 0 {
				index += 2
			} else {
				truncated = index < program.data.count
			}
		}

		let text: String
		if kind == .cstr {
			// A cstr only ever pushed single bytes, so the widening is lossless.
			let raw = units.map { UInt8($0 & 0xFF) }
			text = String(bytes: raw, encoding: .utf8) ?? raw.map { String(Character(UnicodeScalar($0))) }.joined()
		} else {
			// Transport only: the units are already in file order with the
			// program's endianness applied, so any fixed byte order decodes them.
			var transport = Data()
			for unit in units {
				transport.append(UInt8(unit >> 8))
				transport.append(UInt8(unit & 0xFF))
			}
			text = String(data: transport, encoding: .utf16BigEndian)
				?? units.compactMap { UnicodeScalar(UInt32($0)) }.map { String($0) }.joined()
		}
		return ("\"\(escape(text))\"" + (truncated ? " …" : ""), index - offset)
	}

	private func u16(_ data: Data, at offset: Int, bigEndian: Bool) -> UInt16 {
		if bigEndian {
			return (UInt16(data[offset]) << 8) | UInt16(data[offset + 1])
		}
		return UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
	}

	private func pad(_ value: UInt64, digits: Int) -> String {
		let text = String(value, radix: 16, uppercase: true)
		return String(repeating: "0", count: max(0, digits - text.count)) + text
	}

	/// The papergun entry 7 is about applies to anything a script reads: a byte
	/// inside a string may be a newline, which would break the one-row-per-line
	/// invariant in the middle of a field.
	private func escape(_ text: String) -> String {
		var out = ""
		for scalar in text.unicodeScalars {
			switch scalar.value {
			case 0x0A: out += "\\n"
			case 0x0D: out += "\\r"
			case 0x09: out += "\\t"
			case 0x22: out += "\\\""
			case 0x5C: out += "\\\\"
			default:
				if scalar.value >= 0x20 && scalar.value <= 0x7E {
					out += String(scalar)
				} else if scalar.value < 0x20 || scalar.value == 0x7F {
					out += "\\u{\(pad4(String(scalar.value, radix: 16, uppercase: true)))}"
				} else {
					out += String(scalar)
				}
			}
		}
		return out
	}

	private func pad4(_ digits: String) -> String {
		String(repeating: "0", count: max(0, 4 - digits.count)) + digits
	}
}

enum ReadKind: ExpressibleByArgument {
	case u8
	case u16
	case u32
	case u64
	case f32
	case f64
	case ptr
	case cstr
	case wstr

	init?(argument: String) {
		switch argument {
		case "u8": self = .u8
		case "u16": self = .u16
		case "u32": self = .u32
		case "u64": self = .u64
		case "f32": self = .f32
		case "f64": self = .f64
		case "ptr": self = .ptr
		case "cstr": self = .cstr
		case "wstr": self = .wstr
		default: return nil
		}
	}

	/// Fixed-width reads only; `-1` marks the two terminated kinds, which
	/// `readValue` sends to `readString` before this is consulted. `ptr` is
	/// 8 here and narrowed to 4 for a 32-bit program at the call site.
	var width: Int {
		switch self {
		case .u8: 1
		case .u16: 2
		case .u32, .f32: 4
		case .u64, .f64, .ptr: 8
		case .cstr, .wstr: -1
		}
	}
}

enum ByteError: LocalizedError {
	case notInSegment(address: UInt64, program: String)
	case noFileBytes(address: UInt64, offset: UInt64, program: String)
	case stopped(address: UInt64, program: String, values: Int, done: Int)
	case tooLong(asked: UInt64, max: UInt64)

	var errorDescription: String? {
		switch self {
		case .notInSegment(let address, let program):
			return "Virtual address @\(hex(address)) is not inside any segment of \(program)"
		case .noFileBytes(let address, let offset, let program):
			return "Nothing to read at @\(hex(address)): file offset \(hex(offset)) is past the end of \(program)'s file data"
		case .stopped(let address, let program, let values, let done):
			return "Read ran past the end of \(program)'s file data at @\(hex(address)): \(done) of \(values) values"
		case .tooLong(let asked, let max):
			return "Asked for \(asked), which is more than \(max)"
		}
	}
}
