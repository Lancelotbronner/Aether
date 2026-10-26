import ArgumentParser
import AetherKit
import SwiftData

struct ProgramCommand: AsyncParsableCommand {
	static let configuration = CommandConfiguration(
		commandName: "program",
		abstract: "Work with programs.",
		subcommands: [Fetch<BinaryModel>.self],
		defaultSubcommand: Fetch<BinaryModel>.self)

	@OptionGroup var aether: AetherOptions
}

struct ProgramOptions: ParsableArguments {

}

extension BinaryModel: FetchableModel {
	static let plural = "programs"

	func describe() -> String {
		name
	}

	static func descriptor(using options: ProgramOptions) -> FetchDescriptor<BinaryModel> {
		FetchDescriptor()
	}
}

/*
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
	 var data = Data()

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
 */
