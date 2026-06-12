import Foundation

/// Protocol for binary file loaders
nonisolated protocol BinaryLoaderProtocol {
	func canLoad(data: Data) -> Bool
	func load(data: Data) throws -> BinaryFile
}

/// Errors that can occur during binary loading
enum BinaryLoaderError: Error, LocalizedError {
	case fileNotFound(URL)
	case unsupportedFormat
	case invalidHeader
	case corruptedFile(String)
	case unsupportedArchitecture(String)
	case readError(String)

	var errorDescription: String? {
		switch self {
		case .fileNotFound(let url):
			return "File not found: \(url.path)"
		case .unsupportedFormat:
			return "Unsupported binary format"
		case .invalidHeader:
			return "Invalid file header"
		case .corruptedFile(let reason):
			return "Corrupted file: \(reason)"
		case .unsupportedArchitecture(let arch):
			return "Unsupported architecture: \(arch)"
		case .readError(let reason):
			return "Read error: \(reason)"
		}
	}
}

/// Main binary loader that delegates to format-specific loaders
nonisolated final class BinaryLoader {
	private let loaders: [BinaryLoaderProtocol]

	init() {
		self.loaders = [
			JARLoader(),  // Check JAR/class first (CAFEBABE conflicts with fat binary)
			MachOLoader(),
			ELFLoader(),
			PELoader()
		]
	}

	/// Load a binary file from URL (synchronous, call from background)
	func load(from url: URL) throws -> BinaryFile {
		guard FileManager.default.fileExists(atPath: url.path) else {
			throw BinaryLoaderError.fileNotFound(url)
		}

		let data = try Data(contentsOf: url)
		return try load(from: data)
	}

	func load(from data: Data) throws -> BinaryFile {
		for loader in loaders {
			if loader.canLoad(data: data) {
				return try loader.load(data: data)
			}
		}

		throw BinaryLoaderError.unsupportedFormat
	}

	/// Detect binary format without loading
	func detectFormat(from url: URL) throws -> BinaryFormat {
		let data = try Data(contentsOf: url, options: .mappedIfSafe)
		return BinaryFormat.detect(from: data)
	}
}

// MARK: - Data Extensions for Binary Reading

nonisolated extension Data {
	func readUInt8(at offset: Int) -> UInt8? {
		guard indices.contains(offset) else { return nil }
		return self[startIndex + offset]
	}

	func readUInt16LE(at offset: Int) -> UInt16? {
		guard offset >= 0, offset + 2 <= count else { return nil }
		return bytes.unsafeLoadUnaligned(fromByteOffset: offset, as: UInt16.self)
	}

	func readUInt16BE(at offset: Int) -> UInt16? {
		readUInt16LE(at: offset)?.byteSwapped
	}

	func readUInt32LE(at offset: Int) -> UInt32? {
		guard offset >= 0, offset + 4 <= count else { return nil }
		return bytes.unsafeLoadUnaligned(fromByteOffset: offset, as: UInt32.self)
	}

	func readUInt32BE(at offset: Int) -> UInt32? {
		readUInt32LE(at: offset)?.byteSwapped
	}

	func readUInt64LE(at offset: Int) -> UInt64? {
		guard offset >= 0, offset + 8 <= count else { return nil }
		return bytes.unsafeLoadUnaligned(fromByteOffset: offset, as: UInt64.self)
	}

	func readUInt64BE(at offset: Int) -> UInt64? {
		readUInt64LE(at: offset)?.byteSwapped
	}

	func readInt32LE(at offset: Int) -> Int32? {
		guard let unsigned = readUInt32LE(at: offset) else { return nil }
		return Int32(bitPattern: unsigned)
	}

	func readInt32BE(at offset: Int) -> Int32? {
		guard let unsigned = readUInt32BE(at: offset) else { return nil }
		return Int32(bitPattern: unsigned)
	}

	func readInt64BE(at offset: Int) -> Int64? {
		guard let unsigned = readUInt64BE(at: offset) else { return nil }
		return Int64(bitPattern: unsigned)
	}

	func readCString(at offset: Int) -> String? {
		guard offset >= 0, offset < count else { return nil }
		return bytes.extracting(droppingFirst: offset).withUnsafeBytes {
			String(cString: $0.bindMemory(to: CChar.self).baseAddress!)
		}
	}

	func subdata(offset: Int, count: Int) -> Data? {
		guard offset >= 0, offset + count <= self.count else { return nil }
		return self[startIndex + offset ..< startIndex + offset + count]
	}
}
