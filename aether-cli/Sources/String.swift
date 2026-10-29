import ArgumentParser
import AetherKit
import Foundation
import SwiftData

/// Strings are `SymbolModel` rows with a string `type` — fetched via an
/// in-memory filter (the generic `FetchCommand` can't express it).
struct StringCommand: AsyncParsableCommand {
	static let configuration = CommandConfiguration(
		commandName: "string",
		abstract: "Work with strings.",
		subcommands: [
			StringFetchCommand.self,
			StringCountCommand.self,
		],
		defaultSubcommand: StringFetchCommand.self)
}

struct StringFetchCommand: AsyncParsableCommand {
	static let configuration = CommandConfiguration(
		commandName: "fetch",
		abstract: "Fetches a list of strings from the project.")

	@OptionGroup var aether: AetherOptions

	@Option(help: "Maximum number of models to show")
	var limit: Int?

	@Option(help: "Skip this many models from the start of the result")
	var offset: Int?

	mutating func run() async throws {
		let strings = try aether.backgroundContext
			.fetch(FetchDescriptor<SymbolModel>())
			.filter { $0.type.isString }
			.sorted { $0.address < $1.address }
		print("Showing \(strings.count) strings:")
		for string in strings.dropFirst(max(0, offset ?? 0)).prefix(limit ?? .max) {
			print("\(string.stringValue) @\(string.address)")
		}
	}
}

struct StringCountCommand: AsyncParsableCommand {
	static let configuration = CommandConfiguration(
		commandName: "count",
		abstract: "Counts the strings in the project.")

	@OptionGroup var aether: AetherOptions

	mutating func run() async throws {
		let count = try aether.backgroundContext
			.fetch(FetchDescriptor<SymbolModel>())
			.filter { $0.type.isString }
			.count
		print(count)
	}
}
