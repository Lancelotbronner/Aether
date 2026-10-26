/// Binary file format

import Foundation
public enum BinaryFormat: String, CaseIterable, Identifiable, Codable {
	case machO = "Mach-O"
	case elf = "ELF"
	case pe = "PE"
	case java = "Java"
	case unknown = "Unknown"
}

public extension BinaryFormat {
	var id: String { rawValue }

	/// File extension hints
	var commonExtensions: [String] {
		switch self {
		case .machO:
			return ["", "dylib", "bundle", "framework", "app"]
		case .elf:
			return ["", "so", "o"]
		case .pe:
			return ["exe", "dll", "sys"]
		case .java:
			return ["jar", "class", "war", "ear"]
		case .unknown:
			return []
		}
	}

	/// Magic bytes for format detection
	static func detect(from data: Data) -> BinaryFormat {
		guard data.count >= 4 else { return .unknown }

		let magic = data.readUInt32LE(at: 0)

		switch magic {
		case 0xFEEDFACE, 0xFEEDFACF:  // Mach-O 32/64
			return .machO
		case 0xBEBAFECA:  // Fat/Universal binary (little endian read)
			return .machO
		case 0xCAFEBABE:  // Could be Fat binary OR Java class file
						  // Check if it's a Java class by looking for valid version bytes
			if data.count >= 8 {
				// Java class files have minor/major version after magic
				let majorVersion = (UInt16(data[6]) << 8) | UInt16(data[7])
				// Java versions range from 45 (1.1) to ~65 (21)
				if majorVersion >= 45 && majorVersion <= 70 {
					return .java
				}
			}
			return .machO  // Otherwise it's a Fat binary
		case 0x464C457F:  // ELF magic (0x7F 'E' 'L' 'F')
			return .elf
		default:
			// Check for PE (MZ header)
			if data.count >= 2 {
				let mz = data.prefix(2)
				if mz[mz.startIndex] == 0x4D && mz[mz.startIndex + 1] == 0x5A {
					return .pe
				}
			}
			// Check for JAR/ZIP (PK header)
			if data.count >= 4 {
				if data[0] == 0x50 && data[1] == 0x4B && data[2] == 0x03 && data[3] == 0x04 {
					return .java
				}
			}
			return .unknown
		}
	}
}

/// Endianness
public enum Endianness: String, Codable {
	case little
	case big
}

public extension Endianness {
	/// Read UInt16 with this endianness
	func readUInt16(_ data: Data, at offset: Int) -> UInt16 {
		let bytes = data[offset..<(offset + 2)]
		switch self {
		case .little:
			return UInt16(bytes[bytes.startIndex]) | (UInt16(bytes[bytes.startIndex + 1]) << 8)
		case .big:
			return (UInt16(bytes[bytes.startIndex]) << 8) | UInt16(bytes[bytes.startIndex + 1])
		}
	}

	/// Read UInt32 with this endianness
	func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
		let bytes = data[offset..<(offset + 4)]
		switch self {
		case .little:
			return bytes.withUnsafeBytes { $0.load(as: UInt32.self) }
		case .big:
			return bytes.withUnsafeBytes { $0.load(as: UInt32.self).byteSwapped }
		}
	}

	/// Read UInt64 with this endianness
	func readUInt64(_ data: Data, at offset: Int) -> UInt64 {
		let bytes = data[offset..<(offset + 8)]
		switch self {
		case .little:
			return bytes.withUnsafeBytes { $0.load(as: UInt64.self) }
		case .big:
			return bytes.withUnsafeBytes { $0.load(as: UInt64.self).byteSwapped }
		}
	}
}

/// Supported CPU architectures
public enum Architecture: String, CaseIterable, Identifiable, Codable, Sendable {
	case x86_64 = "x86_64"
	case appleSilicon = "Apple Silicon"
	case arm64 = "ARM64"
	case arm64e = "ARM64e"
	case i386 = "i386"
	case armv7 = "ARMv7"
	case jvm = "JVM"
	case unknown = "Unknown"
}

public extension Architecture {
	var id: String { rawValue }
}

/// Symbol type
public enum SymbolType: String, Codable {
	case function = "Function"
	case data = "Data"
	case object = "Object"
	case section = "Section"
	case file = "File"
	case unknown = "Unknown"
}

/// Symbol binding/visibility
public enum SymbolBinding: String, Codable {
	case local = "Local"
	case global = "Global"
	case weak = "Weak"
	case external = "External"
	case undefined = "Undefined"
}

/// Function argument
public struct FunctionArgument: Codable, Identifiable {
	public var id = UUID()
	public var name: String
	public var type: String
	public var register: String?
	public var stackOffset: Int?
}

/// Local variable
public struct LocalVariable: Codable, Identifiable {
	public var id = UUID()
	public var name: String
	public var type: String
	public var stackOffset: Int
	public var size: Int
}

/// Type of basic block
public enum BasicBlockType: String, Codable {
	case entry = "Entry"
	case normal = "Normal"
	case exit = "Exit"
	case conditional = "Conditional"
	case loop = "Loop"
}

/// String encoding
public enum StringEncoding: String, Codable {
	case ascii = "ASCII"
	case utf8 = "UTF-8"
	case utf16 = "UTF-16"
	case utf32 = "UTF-32"
}

/// Type of cross-reference
public enum XRefType: String, Codable {
	case call = "Call"
	case jump = "Jump"
	case data = "Data"
	case string = "String"
}
