import ArgumentParser
import AetherKit
import SwiftData

struct ProgramCommand: AsyncParsableCommand {
	static let configuration = CommandConfiguration(
		commandName: "program",
		abstract: "Work with programs.",
		subcommands: [
			FetchCommand<BinaryModel>.self,
			CountCommand<BinaryModel>.self,
		],
		defaultSubcommand: FetchCommand<BinaryModel>.self)
}

extension BinaryModel: FetchableModel {
	static let plural = "programs"

	struct FetchOptions: ParsableArguments {

	}

	func describe() -> String {
		"\(name)\n" + "id: \(persistentModelID)"
	}
}
