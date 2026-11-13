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
		let modelContext = try aether.backgroundContext()
		var descriptor = FetchDescriptor<Model>()
		try Model.apply(modelOptions, to: &descriptor, in: modelContext)
		// Only a page that was typed: `fetch` adds a 100-row default, and a
		// default reaching a delete would silently wipe a document 100 rows at a
		// time while reporting a smaller `Deleted N` each run.
		fetchOptions.apply(page: fetchOptions.limit, to: &descriptor)
		descriptor.propertiesToFetch = []
		descriptor.relationshipKeyPathsForPrefetching = []
		let models = try modelContext.fetch(descriptor)
		// Asked before the rows go, so `--dry-run` and a real delete report the
		// same numbers and a cascade much larger than `Deleted N` cannot be
		// missed after the fact.
		let cascade = Model.cascade(of: models, in: modelContext)
		for model in models {
			modelContext.delete(model)
		}

		if !aether.dryRun {
			try modelContext.save()
		}

		// The count line is what it always was; the clause says what else moved
		// with it, and what was left behind pointing at a row that is gone.
		let line = "Deleted \(models.count) \(Model.plural)"
		guard let clause = cascade.describe() else {
			print(line)
			return
		}
		print("\(line) — \(clause)")
	}
}
