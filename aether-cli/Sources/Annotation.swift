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

		@Option
		var address: UInt64?

		@Option
		var kind: AnnotationKind?
	}

	static func apply(_ options: FetchOptions, to descriptor: inout FetchDescriptor<AnnotationModel>) {
		let _text = options.text
		let text = #Predicate<AnnotationModel> { model in
			_text.flatMap { model.text.localizedStandardContains($0) } ?? true
		}
		let _binary = options.binary
		let binary = #Predicate<AnnotationModel> { model in
			_binary.flatMap { model.binary.name == $0 } ?? true
		}
		let _address = options.address
		let address = #Predicate<AnnotationModel> { model in
			_address.flatMap { model.address == $0 } ?? true
		}
		let _kind = options.kind
		let kind = #Predicate<AnnotationModel> { model in
			_kind.flatMap { model.rawKind == $0.rawValue } ?? true
		}
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
		@Argument
		var binary: String

		@Argument
		var address: UInt64

		@Argument
		var text: String

		@Option
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
