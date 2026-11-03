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
			DeleteCommand<BinaryModel>.self,
		],
		defaultSubcommand: FetchCommand<BinaryModel>.self)
}

extension BinaryModel: FetchableModel {
	static let plural = "programs"

	func describe() -> String {
		"\(name)\n" + "id: \(persistentModelID)"
	}
}
