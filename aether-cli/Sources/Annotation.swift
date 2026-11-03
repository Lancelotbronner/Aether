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

		@Option(help: "Filter to an annotation at an address (decimal; addresses print as hex)")
		var address: UInt64?

		@Option(help: "Filter on kind (0 inline, 1 trailing)")
		var kind: AnnotationKind?
	}

	static func apply(_ options: FetchOptions, to descriptor: inout FetchDescriptor<AnnotationModel>) {
		let text = options.text.flatMap { filter in
			#Predicate<AnnotationModel> { $0.text.localizedStandardContains(filter) }
		} ?? .true
		let binary = options.binary.flatMap { filter in
			#Predicate<AnnotationModel> { $0.binary.name == filter }
		} ?? .true
		let address = options.address.flatMap { filter in
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

	func describe() -> String {
		"\(text) @\(hex(address)) kind=\(kind) program=\(binary.name)"
	}
}

extension AnnotationModel: InsertableModel {
	static let singular = "annotation"

	struct InsertOptions: ParsableArguments {
		@Argument(help: "Name of the program to annotate")
		var binary: String

		@Argument(help: "Address to annotate (decimal; addresses print as hex)")
		var address: UInt64

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

		self.init(options.text, at: options.address, in: binary)
		self.kind = options.kind
	}
}
