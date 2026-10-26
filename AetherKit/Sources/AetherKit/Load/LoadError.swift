import Foundation

/// Errors that can occur during binary loading
public enum BinaryLoaderError: Error, LocalizedError {
	case fileNotFound(URL)
	case unsupportedFormat
	case invalidHeader
	case invalidMagic(String)
	case unsupportedBinary(String)
	case corruptedFile(String)
	case unsupportedArchitecture(String)
	case readError(String)

	public var errorDescription: String? {
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
