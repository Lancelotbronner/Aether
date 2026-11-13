import ArgumentParser
import SwiftData

protocol FetchableModel: PersistentModel {
	associatedtype FetchOptions: ParsableArguments = EmptyOptions

	static var plural: String { get }

	func describe() -> String

	/// The row as fields rather than as text, which is what `--json` prints and
	/// what `describe()` renders. One source for both, so a field cannot be
	/// added to a row and forgotten in the other view.
	func fields() -> [RowField]

	static var subcommands: [any ParsableCommand.Type] { get }

	/// Filters are allowed to look things up in the document first — a name or
	/// a file offset only becomes a comparable address after that — which is
	/// why this gets a context and may fail.
	static func apply(_ options: FetchOptions, to descriptor: inout FetchDescriptor<Self>, in modelContext: ModelContext) throws
}

extension FetchableModel {
	static var subcommands: [any ParsableCommand.Type] { [] }

	func describe() -> String {
		fields().map { $0.text }.joined(separator: " ")
	}
}

extension FetchableModel where FetchOptions == EmptyOptions {
	static func apply(_ options: FetchOptions, to descriptor: inout FetchDescriptor<Self>, in modelContext: ModelContext) throws {}
}

struct FetchOptions: ParsableArguments {
	@Option(help: "Maximum number of models to show")
	var limit: Int?

	@Option(help: "Skip this many models from the start of the result")
	var offset: Int?

	func apply(to descriptor: inout FetchDescriptor<some PersistentModel>) {
		descriptor.fetchLimit = limit
		descriptor.fetchOffset = offset
	}
}

struct FetchCommand<Model: FetchableModel>: AsyncParsableCommand {
	static var configuration: CommandConfiguration {
		CommandConfiguration(
			commandName: "fetch",
			abstract: "Fetches a list of \(Model.plural) from the project.",
			subcommands: Model.subcommands)
	}

	@OptionGroup var aether: AetherOptions
	@OptionGroup var modelOptions: Model.FetchOptions
	@OptionGroup var fetchOptions: FetchOptions

	@Flag(help: "Emit the rows as a JSON array of objects keyed by the field names of the text rows")
	var json = false

	mutating func run() async throws {
		let context = aether.backgroundContext
		var descriptor = FetchDescriptor<Model>()
		try Model.apply(modelOptions, to: &descriptor, in: context)
		let count = try context.fetchCount(descriptor)
		fetchOptions.apply(to: &descriptor)
		let models = try context.fetch(descriptor)
		if json {
			print(jsonRows(models.map { jsonRow($0.fields()) }))
			return
		}
		let offset = fetchOptions.offset ?? 0
		print("Showing \(models.count) (\(offset)-\(offset + models.count)) of \(count) \(Model.plural):")
		for model in models {
			print(model.describe())
		}
	}
}
