import ArgumentParser
import SwiftData

struct CountCommand<Model: FetchableModel>: AsyncParsableCommand {
	static var configuration: CommandConfiguration {
		CommandConfiguration(
			commandName: "count",
			abstract: "Counts the \(Model.plural) in the project.",
			subcommands: Model.subcommands)
	}

	@OptionGroup var aether: AetherOptions
	@OptionGroup var options: Model.FetchOptions

	@Option(help: "Maximum number of models in the count")
	var limit: Int?

	@Option(help: "Skip this many models from the start of the result")
	var offset: Int?

	mutating func run() async throws {
		var descriptor = Model.descriptor(using: options)
		descriptor.fetchLimit = limit
		descriptor.fetchOffset = offset
		let count = try aether.backgroundContext.fetchCount(descriptor)
		print(count)
	}
}
