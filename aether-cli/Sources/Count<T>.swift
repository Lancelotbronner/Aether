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

	@Flag(help: "Emit the count as a JSON object")
	var json = false

	mutating func run() async throws {
		let context = aether.backgroundContext
		var descriptor = FetchDescriptor<Model>()
		try Model.apply(modelOptions, to: &descriptor, in: context)
		let count = try context.fetchCount(descriptor)
		if json {
			print(jsonRow([field("plural", Model.plural), field("count", count)]))
			return
		}
		print(count)
	}
}
