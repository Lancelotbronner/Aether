import ArgumentParser
import AetherKit
import SwiftData

struct SectionCommand: AsyncParsableCommand {
	static let configuration = CommandConfiguration(
		commandName: "section",
		abstract: "Work with sections.",
		subcommands: [
			FetchCommand<SectionModel>.self,
			CountCommand<SectionModel>.self,
		],
		defaultSubcommand: FetchCommand<SectionModel>.self)
}

extension SectionModel: FetchableModel {
	static let plural = "sections"

	struct FetchOptions: ParsableArguments {

	}

	func describe() -> String {
		fullName
	}
}
