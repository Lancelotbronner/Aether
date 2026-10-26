import ArgumentParser
import SwiftData

protocol FetchableModel: PersistentModel {
	associatedtype FetchOptions: ParsableArguments

	static var plural: String { get }

	func describe() -> String

	static var subcommands: [any ParsableCommand.Type] { get }

	static func descriptor(using options: FetchOptions) -> FetchDescriptor<Self>
}

extension FetchableModel {
	static var subcommands: [any ParsableCommand.Type] { [] }

	static func descriptor(using options: FetchOptions) -> FetchDescriptor<Self> {
		FetchDescriptor()
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
	@OptionGroup var options: Model.FetchOptions

	@Option
	var limit: Int?

	@Option
	var offset: Int?

	mutating func run() async throws {
		var descriptor = Model.descriptor(using: options)
		descriptor.fetchLimit = limit
		descriptor.fetchOffset = offset
		let models = try aether.backgroundContext.fetch(descriptor)
		print("Showing \(models.count) models:")
		for model in models {
			print(model.describe())
		}
	}
}
