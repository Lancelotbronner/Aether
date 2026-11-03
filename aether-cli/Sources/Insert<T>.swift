import ArgumentParser
import SwiftData

protocol InsertableModel: PersistentModel {
	associatedtype InsertOptions: ParsableArguments

	static var singular: String { get }

	func describe() -> String

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

	mutating func run() async throws {
		let modelContext = aether.backgroundContext
		let model = try await Model(options: modelOptions, using: modelContext)
		modelContext.insert(model)

		if !aether.dryRun {
			try modelContext.save()
		}

		print("Inserted \(model)!")
	}
}
