import ArgumentParser
import AetherKit
import SwiftData

struct ProgramCommand: AsyncParsableCommand {
	static let configuration = CommandConfiguration(
		commandName: "program",
		abstract: "Work with programs.",
		subcommands: [
			Fetch<BinaryModel>.self,
			Count<BinaryModel>.self,
		],
		defaultSubcommand: Fetch<BinaryModel>.self)
}

extension BinaryModel: FetchableModel {
	static let plural = "programs"

	struct FetchOptions: ParsableArguments {

	}

	func describe() -> String {
		name
	}
}
