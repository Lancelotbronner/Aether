import Foundation
import SwiftData

public extension Array<any PersistentModel.Type> {
	static let project: [any PersistentModel.Type] = [
		BinaryModel.self,
		SegmentModel.self,
		SectionModel.self,
		SymbolModel.self,

		AnnotationModel.self,
		BookmarkModel.self,
	]
}

public extension Schema {
	static let project = Schema(.project)
}

@Model public final class BinaryModel {
	public var name = "Untitled"
	public var format = BinaryFormat.unknown
	public var endian = Endianness.little
	public var architecture = Architecture.unknown
	public var is64 = true
	public var fileURL: URL?

	public var entryPoint: UInt64 = 0
	public var stackSize: UInt64 = 0
	public var baseAddress: UInt64 = 0

	@Attribute(.externalStorage)
	public var data = Data()

	@Relationship(deleteRule: .cascade, inverse: \SegmentModel.binary)
	public var segments: [SegmentModel] = []

	@Relationship(deleteRule: .cascade, inverse: \SectionModel.binary)
	public var sections: [SectionModel] = []

	@Relationship(deleteRule: .cascade, inverse: \SymbolModel.binary)
	public var symbols: [SymbolModel] = []

	@Relationship(deleteRule: .cascade, inverse: \ProcedureModel.binary)
	public var procedures: [ProcedureModel] = []

	@Relationship(deleteRule: .cascade, inverse: \StringModel.binary)
	public var strings: [StringModel] = []

	@Relationship(deleteRule: .cascade, inverse: \CrossReferenceModel.binary)
	public var references: [CrossReferenceModel] = []

	@Relationship(deleteRule: .cascade, inverse: \AnnotationModel.binary)
	public var annotations: [AnnotationModel] = []

	@Relationship(deleteRule: .cascade, inverse: \BookmarkModel.binary)
	public var bookmarks: [BookmarkModel] = []

	public init() {}
}

public extension BinaryModel {
	func load<T: BitwiseCopyable>(_ type: T.Type, at address: UInt64) -> T {
		let byteOffset = Int(address - baseAddress)
		return data.bytes.unsafeLoadUnaligned(fromByteOffset: byteOffset, as: T.self)
	}

	func ascii(at address: UInt64, maxLength: Int = .max) -> String {
		String(cString: span(at: address), maxLength: maxLength, isKnownASCII: true)
	}

	func unicode(at address: UInt64, maxLength: Int = .max) -> String {
		String(cString: span(at: address), maxLength: maxLength)
	}

	@_lifetime(borrow self)
	func bytes(at address: UInt64) -> RawSpan {
		span(at: address).bytes
	}

	@_lifetime(borrow self)
	func span(at address: UInt64) -> Span<UInt8> {
		let lowerBound = Int(address - baseAddress)
		let span = data.span.extracting(lowerBound...)
		return _overrideLifetime(span, borrowing: self)
	}

	@_lifetime(borrow self)
	func bytes(in range: Range<UInt64>) -> RawSpan {
		span(in: range).bytes
	}

	/// The bytes backing `range`, clamped to the loaded data. Portions of the
	/// range that fall outside the file (e.g. addresses not backed by any
	/// segment) are dropped.
	@_lifetime(borrow self)
	func span(in range: Range<UInt64>) -> Span<UInt8> {
		let count = data.count
		guard range.lowerBound >= baseAddress else {
			let span = data.span.extracting(0..<0)
			return _overrideLifetime(span, borrowing: self)
		}
		let lowerBound = min(Int(range.lowerBound - baseAddress), count)
		let upperBound = min(lowerBound + range.count, count)
		let span = data.span.extracting(lowerBound..<upperBound)
		return _overrideLifetime(span, borrowing: self)
	}

	/// The file data backing `range`, or `nil` if the range is not fully
	/// contained in the loaded data (e.g. it references addresses outside any
	/// mapped segment).
	func data(in range: Range<UInt64>) -> Data? {
		guard range.lowerBound >= baseAddress else { return nil }
		let lowerBound = Int(range.lowerBound - baseAddress)
		let upperBound = lowerBound + range.count
		guard upperBound <= data.count else { return nil }
		return data[lowerBound..<upperBound]
	}

	func format(hex range: Range<UInt64>) -> String {
		let span = span(in: range)
		return span.indices
			.map { String(format: "%02X", span[$0]) }
			.joined(separator: " ")
	}

	static func hex(bytes: consuming Span<UInt8>) -> String {
		bytes.indices
			.map { String(format: "%02X", bytes[$0]) }
			.joined(separator: " ")
	}

	/// Find section containing address
	func section(containing address: UInt64) -> SectionModel? {
		sections.first { $0.contains(address: address) }
	}

	/// Find segment containing address
	func segment(containing address: UInt64) -> SegmentModel? {
		segments.first { $0.contains(address: address) }
	}

	/// Read `count` bytes at virtual `address`. The address is mapped to a
	/// file offset via `baseAddress` (like `data(in:)`); returns `nil` if
	/// the range is not fully contained in the loaded data.
	func read(at address: UInt64, count: Int) -> Data? {
		guard count >= 0 else { return nil }
		let start = data.startIndex
		return data(in: address..<(address + UInt64(count)))?.subdata(in: start..<start + count)
	}

	/// Read null-terminated string at virtual `address` (up to `maxLength`
	/// bytes). Returns `nil` if `address` is not backed by loaded data.
	func readString(at address: UInt64, maxLength: Int = 1024) -> String? {
		// Clamped view: the first byte is file-backed (data(in:) succeeded),
		// but the string may run to the end of the file without a terminator.
		guard let head = data(in: address..<(address + 1)) else { return nil }
		let end = min(head.count + maxLength - 1, data.count)
		let view = data[head.startIndex..<end]
		var i = view.startIndex
		while i < view.endIndex, view[i] != 0 {
			i = view.index(after: i)
		}
		return String(data: view[..<i], encoding: .utf8)
	}
}

/// Binary segment (e.g., `__TEXT`, `__DATA`)
@Model public final class SegmentModel {
	#Unique<SegmentModel>([\.binary, \.address])

	public var binary: BinaryModel
	public var name = "Untitled"
	public var address: UInt64 = 0
	public var size: UInt64 = 0
	public var fileOffset: UInt64 = 0
	public var fileSize: UInt64 = 0
	public var maxProtection: UInt32 = 0
	public var initProtection: UInt32 = 0

	@Relationship(deleteRule: .cascade, inverse: \SectionModel.segment)
	public var sections: [SectionModel] = []

	public init(in binary: BinaryModel) {
		self.binary = binary
	}
}

public extension SegmentModel {
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
@Model public final class SectionModel {
	#Unique<SectionModel>([\.binary, \.address])

	public var binary: BinaryModel
	public var segment: SegmentModel
	public var name = "Untitled"
	public var segmentName = "Untitled"
	public var address: UInt64 = 0
	public var size: UInt64 = 0
	public var offset: UInt32 = 0
	public var alignment: UInt32 = 0
	public var flags: UInt32 = 0

	public init(in segment: SegmentModel, of binary: BinaryModel) {
		self.segment = segment
		self.binary = binary
	}
}

public extension SectionModel {
	var addressRange: Range<UInt64> { address..<(address + size) }

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
@Model public final class SymbolModel {
	// Imports (N_UNDF) all share address 0, so uniqueness must include the
	// name or the whole import table collapses to one row.
	#Unique<SymbolModel>([\.binary, \.address, \.identifier])

	public var binary: BinaryModel
	public var identifier = ""
	public var name = ""
	public var address: UInt64 = 0
	public var size: UInt64 = 1
	public var type = SymbolType.unknown
	public var binding = SymbolBinding.undefined
	public var isImport = false
	public var isExport = false

	public init(in binary: BinaryModel) {
		self.binary = binary
	}
}

public extension SymbolModel {
	var addressRange: Range<UInt64> { address..<(address + size) }

	var isImported: Bool {
		binding == .external && address == 0
	}

	var isExported: Bool {
		binding == .global && address != 0
	}

	var isLocal: Bool {
		binding == .local
	}

	func refresh() {
		isImport = isImported
		isExport = isExported
		name = identifier
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
@Model public final class ProcedureModel {
	#Unique<ProcedureModel>([\.symbol])

	public var binary: BinaryModel
	public var symbol: SymbolModel
	public var demangled = ""

	// Analysis results

	@Relationship(deleteRule: .cascade, inverse: \BlockModel.procedure)
	public var blocks: [BlockModel] = []

	/// Procedures that call this function
	@Relationship(deleteRule: .nullify, inverse: \ProcedureModel.callees)
	public var callers: [ProcedureModel] = []

	/// Procedures this function calls (SwiftData keeps this in sync with
	/// `callers`, whose `inverse: \ProcedureModel.callees` is the only
	/// relationship declaration for this self-referential pair)
	public var callees: [ProcedureModel] = []

	// Metadata
	public var isThunk: Bool = false           // Simple jump to another function
	public var isLeaf: Bool = true             // Doesn't call other functions
	public var stackSize: Int = 0              // Stack frame size
	public var arguments: [FunctionArgument] = []
	public var localVariables: [LocalVariable] = []

	public init(is symbol: SymbolModel, in binary: BinaryModel) {
		self.binary = binary
		self.symbol = symbol
	}
}

public extension ProcedureModel {
	func contains(address: UInt64) -> Bool {
		let range = symbol.addressRange
		return range.contains(address)
	}

	var displayName: String {
		if symbol.name.isEmpty {
			return String(format: "sub_%llX", symbol.address)
		}
		// Strip leading underscore for display
		if symbol.name.hasPrefix("_") && !symbol.name.hasPrefix("__") {
			return String(symbol.name.dropFirst())
		}
		return symbol.name
	}

	/// Short display name for headers/UI - formats Java signatures nicely
	var shortDisplayName: String {
		if symbol.name.isEmpty {
			return String(format: "sub_%llX", symbol.address)
		}

		// Check if this looks like a Java method signature
		// Format: className.methodName(descriptor)returnType
		// Detect by: has parenthesis AND has at least 2 dot-separated parts before it
		if let parenIndex = symbol.name.firstIndex(of: "(") {
			let beforeParen = String(symbol.name[..<parenIndex])
			let parts = beforeParen.split(separator: ".")

			// If we have package.class.method format (2+ parts), it's likely Java
			if parts.count >= 2 {
				let className = String(parts[parts.count - 2])
				let methodName = String(parts[parts.count - 1])

				// Parse descriptor to get simple parameter types
				let afterParen = String(symbol.name[parenIndex...])
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
		if symbol.name.hasPrefix("_") && !symbol.name.hasPrefix("__") {
			return String(symbol.name.dropFirst())
		}

		return symbol.name
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
@Model public final class BlockModel {
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

	/// Addresses of predecessor blocks (kept in sync by SwiftData with
	/// `successors`, the only relationship declaration for this pair)
	var predecessors: [BlockModel] = []

	var size: UInt64 { endAddress - startAddress }
}

@Model public final class AnnotationModel {
	public var binary: BinaryModel
	public var kind = AnnotationKind.inline
	public var address: UInt64
	public var text: String

	public init(_ text: String, at address: UInt64, in binary: BinaryModel) {
		self.binary = binary
		self.address = address
		self.text = text
	}
}

public enum AnnotationKind: Int, Codable {
	case inline
	case trailing
}

/// String reference found in binary
@Model public final class StringModel {
	public var binary: BinaryModel
	public var address: UInt64
	public var encoding: StringEncoding

	public init(binary: BinaryModel, address: UInt64, encoding: StringEncoding, cached: String? = nil) {
		self.binary = binary
		self.address = address
		self.encoding = encoding
		self.cached = cached
	}

	@Transient public var cached: String?

	public var value: String {
		cached ?? "not loaded"
	}
}

/// Cross-reference
@Model public final class CrossReferenceModel {
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

@Model public final class BookmarkModel {
	public var binary: BinaryModel
	public var name: String
	public var address: UInt64
	public var summary = ""
	public var created = Date.now

	public init(_ name: String, at address: UInt64, in binary: BinaryModel) {
		self.name = name
		self.address = address
		self.binary = binary
	}
}
