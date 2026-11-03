import Foundation
import SwiftData

public extension Array<any PersistentModel.Type> {
	static let project: [any PersistentModel.Type] = [
		BinaryModel.self,
		SegmentModel.self,
		SectionModel.self,
		SymbolModel.self,
		ProcedureModel.self,

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

	@Relationship(deleteRule: .cascade, inverse: \CrossReferenceModel.binary)
	public var references: [CrossReferenceModel] = []

	@Relationship(deleteRule: .cascade, inverse: \AnnotationModel.binary)
	public var annotations: [AnnotationModel] = []

	@Relationship(deleteRule: .cascade, inverse: \BookmarkModel.binary)
	public var bookmarks: [BookmarkModel] = []

	public init() {}
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

/// Represents a symbol in the binary.
///
/// The sole symbol representation: the former `StringModel` is merged in
/// (`type` set to a string encoding, decoded text in `stringValue`), and
/// data sections are symbolized per-element from their Mach-O section type
/// (see `MachOLoader.symbolize(in:)`), so the full memory map is a list of
/// symbols.
@Model public final class SymbolModel {
	// Imports (N_UNDF) all share address 0, so uniqueness must include the
	// name or the whole import table collapses to one row.
	#Unique<SymbolModel>([\.binary, \.address, \.identifier])

	public var binary: BinaryModel
	public var identifier = ""
	public var name = ""
	public var address: UInt64 = 0
	public var size: UInt64 = 1
	public var rawKind = 0
	public var rawType = 0
	public var rawBinding = 0
	public var isImport = false
	public var isExport = false

	public var stringValue = ""

	public init(in binary: BinaryModel) {
		self.binary = binary
	}

	public var kind: SymbolKind {
		get { SymbolKind(rawValue: rawKind) ?? .unknown }
		set { rawKind = newValue.rawValue }
	}

	public var type: SymbolType {
		get { SymbolType(rawValue: rawType) ?? .unknown }
		set { rawType = newValue.rawValue }
	}

	public var binding: SymbolBinding {
		get { SymbolBinding(rawValue: rawBinding) ?? .undefined }
		set { rawBinding = newValue.rawValue }
	}
}

/// Symbol type
public enum SymbolKind: Int, Codable {
	case unknown
	case function
	case data
	case section
}

public enum SymbolType: Int, Codable {
	case unknown
	case u8, u16, u32, u64, u128
	case ascii, utf8, utf16
	case ptr, function
}

/// Symbol binding/visibility
public enum SymbolBinding: Int, Codable {
	case undefined
	case local
	case global
	case weak
	case external
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

/// A basic block within a function (for CFG)
@Model public final class BlockModel {
	var procedure: ProcedureModel
	public var startAddress: UInt64 = 0
	public var endAddress: UInt64 = 0

	// Block type
	public var type = BasicBlockType.normal

	init(in procedure: ProcedureModel) {
		self.procedure = procedure
	}

	// CFG edges

	/// Addresses of successor blocks
	@Relationship(deleteRule: .nullify, inverse: \BlockModel.predecessors)
	public var successors: [BlockModel] = []

	/// Addresses of predecessor blocks (kept in sync by SwiftData with
	/// `successors`, the only relationship declaration for this pair)
	public var predecessors: [BlockModel] = []

	var size: UInt64 { endAddress - startAddress }
}

@Model public final class AnnotationModel {
	public var binary: BinaryModel
	public var rawKind = 0
	public var address: UInt64
	public var text: String

	public init(_ text: String, at address: UInt64, in binary: BinaryModel) {
		self.binary = binary
		self.address = address
		self.text = text
	}

	public var kind: AnnotationKind {
		get { AnnotationKind(rawValue: rawKind) ?? .inline }
		set { rawKind = newValue.rawValue }
	}
}

public enum AnnotationKind: Int, Codable, CaseIterable, Sendable {
	case inline
	case trailing
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
