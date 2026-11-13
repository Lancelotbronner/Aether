import ArgumentParser
import SwiftData

/// Everything this protocol creates, `fetch` can already read back, so the
/// row rendering comes from `FetchableModel` instead of being declared twice.
protocol InsertableModel: PersistentModel, FetchableModel {
	associatedtype InsertOptions: ParsableArguments

	static var singular: String { get }

	init(options: InsertOptions, using modelContext: ModelContext) async throws
}

struct InsertCommand<Model: InsertableModel>: AsyncParsableCommand {
	static var configuration: CommandConfiguration {
		CommandConfiguration(
			commandName: "insert",
			abstract: "Inserts a \(Model.singular) into the project.")
	}

	@OptionGroup var aether: AetherOptions
	@OptionGroup var modelOptions: Model.InsertOptions

	@Flag(help: "Emit the inserted row as a JSON object")
	var json = false

	mutating func run() async throws {
		let modelContext = try aether.backgroundContext()
		let model = try await Model(options: modelOptions, using: modelContext)
		modelContext.insert(model)

		if !aether.dryRun {
			try modelContext.save()
		}

		if json {
			print(jsonRow(model.fields()))
			return
		}
		print("Inserted \(model.describe())")
	}
}
