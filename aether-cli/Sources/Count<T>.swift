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
	@OptionGroup var modelOptions: Model.FetchOptions
	@OptionGroup var fetchOption: FetchOptions


	mutating func run() async throws {
		var descriptor = FetchDescriptor<Model>()
		Model.apply(modelOptions, to: &descriptor)
		fetchOption.apply(to: &descriptor)
		let count = try aether.backgroundContext.fetchCount(descriptor)
		print(count)
	}
}
