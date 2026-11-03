import ArgumentParser
import AetherKit
import SwiftData

struct SymbolCommand: AsyncParsableCommand {
	static let configuration = CommandConfiguration(
		commandName: "symbol",
		abstract: "Work with symbol.",
		subcommands: [
			FetchCommand<SymbolModel>.self,
			CountCommand<SymbolModel>.self,
			DeleteCommand<SymbolModel>.self,
		])
}

extension SymbolModel: FetchableModel {
	static let plural = "symbols"

	func describe() -> String {
		name
	}
}
