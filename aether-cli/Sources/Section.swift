import ArgumentParser
import Foundation
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

	static func apply(_ options: EmptyOptions, to descriptor: inout FetchDescriptor<SectionModel>) {
		descriptor.sortBy = [SortDescriptor(\SectionModel.address)]
	}

	func describe() -> String {
		"\(fullName) @\(hex(address)) size=\(size) offset=\(hex(offset)) align=\(alignment) flags=\(hex(flags))"
			+ " executable=\(isExecutable) zerofill=\(isZeroFill) code=\(containsCode)"
			+ " segment=\(segmentName) program=\(binary.name)"
	}
}
