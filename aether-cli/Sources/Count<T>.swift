import ArgumentParser
import SwiftData

struct Count<Model: FetchableModel>: AsyncParsableCommand {
	static var configuration: CommandConfiguration {
		CommandConfiguration(
			commandName: "fetch",
			abstract: "Fetches a list of \(Model.plural) from the project.",
			subcommands: Model.subcommands)
	}

	@OptionGroup var aether: AetherOptions
	@OptionGroup var options: Model.FetchOptions

	@Option
	var limit: Int?

	@Option
	var offset: Int?

	@MainActor
	mutating func run() async throws {
		var descriptor = Model.descriptor(using: options)
		descriptor.fetchLimit = limit
		descriptor.fetchOffset = offset
		let count = try aether.modelContext.fetchCount(descriptor)
		print(count)
	}
}
