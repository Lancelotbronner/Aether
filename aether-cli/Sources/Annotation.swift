import ArgumentParser
import Foundation
import AetherKit
import SwiftData

struct AnnotationCommand: AsyncParsableCommand {
	static let configuration = CommandConfiguration(
		commandName: "annotation",
		abstract: "Work with annotations.",
		subcommands: [
			FetchCommand<AnnotationModel>.self,
			CountCommand<AnnotationModel>.self,
			DeleteCommand<AnnotationModel>.self,
			InsertCommand<AnnotationModel>.self,
		])
}

extension AnnotationModel: FetchableModel {
	static let plural = "annotations"

	struct FetchOptions: ParsableArguments {
		@Option(help: "Search within the text")
		var text: String?

		@Option(help: "Filters to a specific binary")
		var binary: String?

		@Option(help: "Filter to an annotation at an address: decimal, 0x…, @…, off:<file offset> or a symbol name")
		var address: AddressArgument?

		@Option(help: "Filter on kind (0 inline, 1 trailing)")
		var kind: AnnotationKind?
	}

	static func apply(_ options: FetchOptions, to descriptor: inout FetchDescriptor<AnnotationModel>, in modelContext: ModelContext) throws {
		let addressValue = try filterAddress(options.address, named: options.binary, in: modelContext)
		let text = options.text.flatMap { filter in
			#Predicate<AnnotationModel> { $0.text.localizedStandardContains(filter) }
		} ?? .true
		let binary = options.binary.flatMap { filter in
			#Predicate<AnnotationModel> { $0.binary.name == filter }
		} ?? .true
		let address = addressValue.flatMap { filter in
			#Predicate<AnnotationModel> { $0.address == filter }
		} ?? .true
		let kind = options.kind.flatMap { filter in
			#Predicate<AnnotationModel> { $0.rawKind == filter.rawValue }
		} ?? .true
		descriptor.predicate = #Predicate<AnnotationModel> {
			text.evaluate($0) && binary.evaluate($0) && address.evaluate($0) && kind.evaluate($0)
		}
		descriptor.sortBy = [SortDescriptor(\AnnotationModel.address)]
	}

	func fields() -> [RowField] {
		[
			head("text", text),
			at(hex(address)),
			field("kind", kind),
			field("program", binary.name),
		]
	}
}

extension AnnotationModel: InsertableModel {
	static let singular = "annotation"

	struct InsertOptions: ParsableArguments {
		@Argument(help: "Name of the program to annotate")
		var binary: String

		@Argument(help: "Address to annotate: decimal, 0x…, @…, off:<file offset> or a symbol name")
		var address: AddressArgument

		@Argument(help: "Annotation text")
		var text: String

		@Option(help: "Kind of annotation (0 inline, 1 trailing)")
		var kind = AnnotationKind.inline
	}

	convenience init(options: InsertOptions, using modelContext: ModelContext) async throws {
		let binaryName = options.binary
		var descriptor = FetchDescriptor<BinaryModel>()
		descriptor.predicate = #Predicate<BinaryModel> { $0.name == binaryName }
		descriptor.fetchLimit = 1
		guard let binary = try modelContext.fetch(descriptor).first else {
			throw InsertError.unknownBinary(binaryName)
		}

		let address = try resolveAddress(options.address, named: binaryName, in: modelContext)
		self.init(options.text, at: address, in: binary)
		self.kind = options.kind
	}
}
