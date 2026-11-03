import ArgumentParser
import SwiftData

struct DeleteCommand<Model: FetchableModel>: AsyncParsableCommand {
	static var configuration: CommandConfiguration {
		CommandConfiguration(
			commandName: "delete",
			abstract: "Deletes the specified \(Model.plural) in the project.",
			subcommands: Model.subcommands)
	}

	@OptionGroup var aether: AetherOptions
	@OptionGroup var modelOptions: Model.FetchOptions
	@OptionGroup var fetchOptions: FetchOptions

	mutating func run() async throws {
		var descriptor = FetchDescriptor<Model>()
		Model.apply(modelOptions, to: &descriptor)
		fetchOptions.apply(to: &descriptor)
		descriptor.propertiesToFetch = []
		descriptor.relationshipKeyPathsForPrefetching = []

		let modelContext = aether.backgroundContext
		let models = try modelContext.fetch(descriptor)
		for model in models {
			modelContext.delete(model)
		}

		if !aether.dryRun {
			try modelContext.save()
		}
		
		print("Deleted \(models.count) \(Model.plural)")
	}
}
