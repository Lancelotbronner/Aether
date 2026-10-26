import ArgumentParser
import AetherKit
import SwiftData

struct StringCommand: AsyncParsableCommand {
	static let configuration = CommandConfiguration(
		commandName: "string",
		abstract: "Work with strings.",
		subcommands: [
			Fetch<StringModel>.self,
			Count<BinaryModel>.self,
		],
		defaultSubcommand: Fetch<StringModel>.self)
}

extension StringModel: FetchableModel {
	static let plural = "strings"

	struct FetchOptions: ParsableArguments {

	}

	func describe() -> String {
		"\(value) @\(address)"
	}
}
