import ArgumentParser
import AetherKit
import SwiftData

struct StringCommand: AsyncParsableCommand {
	static let configuration = CommandConfiguration(
		commandName: "string",
		abstract: "Work with strings.",
		subcommands: [
			FetchCommand<StringModel>.self,
			CountCommand<BinaryModel>.self,
		],
		defaultSubcommand: FetchCommand<StringModel>.self)
}

extension StringModel: FetchableModel {
	static let plural = "strings"

	struct FetchOptions: ParsableArguments {

	}

	func describe() -> String {
		"\(value) @\(address)"
	}
}
