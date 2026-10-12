import Foundation
import SwiftData

extension Array<any PersistentModel.Type> {
	static let project: [any PersistentModel.Type] = [
		BinaryModel.self,
		SegmentModel.self,
		SectionModel.self,
		SymbolModel.self,

		AnnotationModel.self,
		BookmarkModel.self,
	]
}

extension Schema {
	static let project = Schema(.project)
}

@Model final class BinaryModel {
	var name = "Untitled"
	var format = BinaryFormat.unknown
	var endian = Endianness.little
	var architecture = Architecture.unknown
	var is64 = true
	var fileURL: URL?

	var entryPoint: UInt64 = 0
	var stackSize: UInt64 = 0
	var baseAddress: UInt64 = 0

	@Attribute(.externalStorage)
	var embedded = Data()

	@Relationship(deleteRule: .cascade, inverse: \SegmentModel.binary)
	var segments: [SegmentModel] = []

	@Relationship(deleteRule: .cascade, inverse: \SectionModel.binary)
	var sections: [SectionModel] = []

	@Relationship(deleteRule: .cascade, inverse: \SymbolModel.binary)
	var symbols: [SymbolModel] = []

	@Relationship(deleteRule: .cascade, inverse: \ProcedureModel.binary)
	var procedures: [ProcedureModel] = []

	@Relationship(deleteRule: .cascade, inverse: \StringModel.binary)
	var strings: [StringModel] = []

	@Relationship(deleteRule: .cascade, inverse: \CrossReferenceModel.binary)
	var references: [CrossReferenceModel] = []

	@Relationship(deleteRule: .cascade, inverse: \AnnotationModel.binary)
	var annotations: [AnnotationModel] = []

	@Relationship(deleteRule: .cascade, inverse: \BookmarkModel.binary)
	var bookmarks: [BookmarkModel] = []

	init() {}
}

/// Binary segment (e.g., `__TEXT`, `__DATA`)
@Model nonisolated final class SegmentModel {
	#Unique<SegmentModel>([\.binary, \.address])
	
	var binary: BinaryModel
	var name = "Untitled"
	var address: UInt64 = 0
	var size: UInt64 = 0
	var fileOffset: UInt64 = 0
	var fileSize: UInt64 = 0
	var maxProtection: UInt32 = 0
	var initProtection: UInt32 = 0

	@Relationship(deleteRule: .cascade, inverse: \SectionModel.segment)
	var sections: [SectionModel] = []

	init(in binary: BinaryModel) {
		self.binary = binary
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

/// Binary section (e.g., `__text`, `__data`)
@Model nonisolated final class SectionModel {
	#Unique<SectionModel>([\.binary, \.address])
	
	var binary: BinaryModel
	var segment: SegmentModel
	var name = "Untitled"
	var segmentName = "Untitled"
	var address: UInt64 = 0
	var size: UInt64 = 0
	var offset: UInt32 = 0
	var alignment: UInt32 = 0
	var flags: UInt32 = 0

	var addressRange: Range<UInt64> { address..<(address + size) }

	init(in segment: SegmentModel, of binary: BinaryModel) {
		self.segment = segment
		self.binary = binary
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
}

/// Represents a symbol in the binary
@Model nonisolated final class SymbolModel {
	var binary: BinaryModel
	var name = "Untitled"
	var address: UInt64 = 0
	var size: UInt64 = 0
	var type = SymbolType.unknown
	var binding = SymbolBinding.undefined

	var id: UInt64 { address }

	init(in binary: BinaryModel) {
		self.binary = binary
	}

	var isImport: Bool {
		binding == .external && address == 0
	}

	var isExport: Bool {
		binding == .global && address != 0
	}

	var isLocal: Bool {
		binding == .local
	}

	var displayName: String {
		// Demangle if needed
		if name.hasPrefix("_$s") || name.hasPrefix("$s") {
			return demangleSwift(name) ?? name
		} else if name.hasPrefix("__Z") || name.hasPrefix("_Z") {
			return demangleCPP(name) ?? name
		}
		return name.hasPrefix("_") ? String(name.dropFirst()) : name
	}

	/// Basic Swift demangling (simplified)
	private func demangleSwift(_ mangled: String) -> String? {
		// Use swift-demangle if available, otherwise return nil
		// This is a placeholder - real implementation would call swift-demangle
		return nil
	}

	/// Basic C++ demangling (simplified)
	private func demangleCPP(_ mangled: String) -> String? {
		// Use c++filt if available, otherwise return nil
		// This is a placeholder - real implementation would call c++filt
		return nil
	}
}

/// Represents an identified function in the binary
@Model nonisolated final class ProcedureModel {
	var binary: BinaryModel
	var name = "Untitled"
	var startAddress: UInt64 = 0
	var endAddress: UInt64 = 0
	var addressRange: Range<UInt64> { startAddress..<endAddress }
	var size: UInt64 { endAddress - startAddress }

	// Analysis results

	@Relationship(deleteRule: .cascade, inverse: \BlockModel.procedure)
	var blocks: [BlockModel] = []

	/// Procedures that call this function
	@Relationship(deleteRule: .nullify, inverse: \ProcedureModel.callees)
	var callers: [ProcedureModel] = []

	/// Procedures this function calls
//	@Relationship(deleteRule: .nullify, inverse: \ProcedureModel.callers)
	var callees: [ProcedureModel] = []

	// Metadata
	var isThunk: Bool = false           // Simple jump to another function
	var isLeaf: Bool = true             // Doesn't call other functions
	var stackSize: Int = 0              // Stack frame size
	var arguments: [FunctionArgument] = []
	var localVariables: [LocalVariable] = []

	init(in binary: BinaryModel) {
		self.binary = binary
	}

	func contains(address: UInt64) -> Bool {
		address >= startAddress && address < endAddress
	}

	var displayName: String {
		if name.isEmpty {
			return String(format: "sub_%llX", startAddress)
		}
		// Strip leading underscore for display
		if name.hasPrefix("_") && !name.hasPrefix("__") {
			return String(name.dropFirst())
		}
		return name
	}

	/// Short display name for headers/UI - formats Java signatures nicely
	var shortDisplayName: String {
		if name.isEmpty {
			return String(format: "sub_%llX", startAddress)
		}

		// Check if this looks like a Java method signature
		// Format: className.methodName(descriptor)returnType
		// Detect by: has parenthesis AND has at least 2 dot-separated parts before it
		if let parenIndex = name.firstIndex(of: "(") {
			let beforeParen = String(name[..<parenIndex])
			let parts = beforeParen.split(separator: ".")

			// If we have package.class.method format (2+ parts), it's likely Java
			if parts.count >= 2 {
				let className = String(parts[parts.count - 2])
				let methodName = String(parts[parts.count - 1])

				// Parse descriptor to get simple parameter types
				let afterParen = String(name[parenIndex...])
				let params = parseJavaParams(afterParen)

				if methodName == "<init>" {
					return "\(className)(\(params))"
				} else if methodName == "<clinit>" {
					return "\(className).<clinit>"
				} else {
					return "\(className).\(methodName)(\(params))"
				}
			}
		}

		// For native functions, strip underscore
		if name.hasPrefix("_") && !name.hasPrefix("__") {
			return String(name.dropFirst())
		}

		return name
	}

	/// Parse Java method descriptor to extract simple parameter types
	private func parseJavaParams(_ descriptor: String) -> String {
		guard let startIdx = descriptor.firstIndex(of: "("),
			  let endIdx = descriptor.firstIndex(of: ")") else {
			return ""
		}

		let paramsStr = String(descriptor[descriptor.index(after: startIdx)..<endIdx])
		if paramsStr.isEmpty { return "" }

		var params: [String] = []
		var idx = paramsStr.startIndex

		while idx < paramsStr.endIndex {
			let c = paramsStr[idx]
			switch c {
			case "B": params.append("byte"); idx = paramsStr.index(after: idx)
			case "C": params.append("char"); idx = paramsStr.index(after: idx)
			case "D": params.append("double"); idx = paramsStr.index(after: idx)
			case "F": params.append("float"); idx = paramsStr.index(after: idx)
			case "I": params.append("int"); idx = paramsStr.index(after: idx)
			case "J": params.append("long"); idx = paramsStr.index(after: idx)
			case "S": params.append("short"); idx = paramsStr.index(after: idx)
			case "Z": params.append("boolean"); idx = paramsStr.index(after: idx)
			case "[":
				// Array - skip to get base type
				idx = paramsStr.index(after: idx)
				continue
			case "L":
				// Object type - find the semicolon
				if let semiIdx = paramsStr[idx...].firstIndex(of: ";") {
					let fullType = String(paramsStr[paramsStr.index(after: idx)..<semiIdx])
					// Get simple class name
					let typeParts = fullType.split(separator: "/")
					params.append(String(typeParts.last ?? Substring(fullType)))
					idx = paramsStr.index(after: semiIdx)
				} else {
					idx = paramsStr.index(after: idx)
				}
			default:
				idx = paramsStr.index(after: idx)
			}
		}

		return params.joined(separator: ", ")
	}
}

/// A basic block within a function (for CFG)
@Model nonisolated final class BlockModel {
	var procedure: ProcedureModel
	var startAddress: UInt64 = 0
	var endAddress: UInt64 = 0

	// Block type
	var type = BasicBlockType.normal

	init(in procedure: ProcedureModel) {
		self.procedure = procedure
	}

	// CFG edges

	/// Addresses of successor blocks
	@Relationship(deleteRule: .nullify, inverse: \BlockModel.predecessors)
	var successors: [BlockModel] = []

	/// Addresses of predecessor blocks
//	@Relationship(deleteRule: .nullify, inverse: \BlockModel.successors)
	var predecessors: [BlockModel] = []

	var size: UInt64 { endAddress - startAddress }
}

@Model final class AnnotationModel {
	var binary: BinaryModel
	var kind = AnnotationKind.inline
	var address: UInt64
	var text: String

	init(_ text: String, at address: UInt64, in binary: BinaryModel) {
		self.binary = binary
		self.address = address
		self.text = text
	}
}

enum AnnotationKind: Int, Codable {
	case inline
	case trailing
}

/// String reference found in binary
@Model final class StringModel {
	var binary: BinaryModel
	var address: UInt64
	var encoding: StringEncoding

	init(binary: BinaryModel, address: UInt64, encoding: StringEncoding, cached: String? = nil) {
		self.binary = binary
		self.address = address
		self.encoding = encoding
		self.cached = cached
	}

	@Transient var cached: String?

	var value: String {
		cached ?? "not loaded"
	}
}

/// Cross-reference
@Model final class CrossReferenceModel {
	var binary: BinaryModel
	var fromAddress: UInt64
	var toAddress: UInt64
	var type: XRefType

	init(binary: BinaryModel, fromAddress: UInt64, toAddress: UInt64, type: XRefType) {
		self.binary = binary
		self.fromAddress = fromAddress
		self.toAddress = toAddress
		self.type = type
	}
}

@Model final class BookmarkModel {
	var binary: BinaryModel
	var name: String
	var address: UInt64
	var summary = ""
	var created = Date.now

	init(_ name: String, at address: UInt64, in binary: BinaryModel) {
		self.name = name
		self.address = address
		self.binary = binary
	}
}
