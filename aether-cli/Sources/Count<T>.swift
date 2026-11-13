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


	mutating func run() async throws {
		let context = aether.backgroundContext
		var descriptor = FetchDescriptor<Model>()
		try Model.apply(modelOptions, to: &descriptor, in: context)
		let count = try context.fetchCount(descriptor)
		print(count)
	}
}
