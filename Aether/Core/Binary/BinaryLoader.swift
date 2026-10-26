import Foundation
import AetherKit

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
	case invalidMagic(String)
	case unsupportedBinary(String)
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
		case .invalidMagic(let magic):
			return "Not a Mach-O binary (magic \(magic))"
		case .unsupportedBinary(let reason):
			return "Unsupported binary: \(reason)"
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

		// Memory-map when possible so large binaries are not copied from disk
		let data = try Data(contentsOf: url, options: .mappedIfSafe)
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
