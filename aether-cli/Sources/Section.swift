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
			DeleteCommand<SectionModel>.self,
		])
}

extension SectionModel: FetchableModel {
	static let plural = "sections"

	func describe() -> String {
		fullName
	}
}
