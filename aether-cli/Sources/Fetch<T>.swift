import ArgumentParser
import SwiftData

protocol FetchableModel: PersistentModel {
	associatedtype FetchOptions: ParsableArguments = EmptyOptions

	static var plural: String { get }

	func describe() -> String

	static var subcommands: [any ParsableCommand.Type] { get }

	static func apply(_ options: FetchOptions, to descriptor: inout FetchDescriptor<Self>)
}

extension FetchableModel {
	static var subcommands: [any ParsableCommand.Type] { [] }
}

extension FetchableModel where FetchOptions == EmptyOptions {
	static func apply(_ options: FetchOptions, to descriptor: inout FetchDescriptor<Self>) {}
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

	mutating func run() async throws {
		var descriptor = FetchDescriptor<Model>()
		Model.apply(modelOptions, to: &descriptor)
		fetchOptions.apply(to: &descriptor)
		let models = try aether.backgroundContext.fetch(descriptor)
		print("Showing \(models.count) \(Model.plural):")
		for model in models {
			print(model.describe())
		}
	}
}
