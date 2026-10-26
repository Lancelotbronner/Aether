import Foundation
import AetherKit

/// Protocol for binary file loaders
nonisolated protocol BinaryLoaderProtocol {
	func canLoad(data: Data) -> Bool
	func load(data: Data) throws -> BinaryFile
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
