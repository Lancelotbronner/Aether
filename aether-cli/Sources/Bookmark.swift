import ArgumentParser
import Foundation
import AetherKit
import SwiftData

struct BookmarkCommand: AsyncParsableCommand {
	static let configuration = CommandConfiguration(
		commandName: "bookmark",
		abstract: "Work with bookmarks.",
		subcommands: [
			FetchCommand<BookmarkModel>.self,
			CountCommand<BookmarkModel>.self,
			DeleteCommand<BookmarkModel>.self,
		])
}

extension BookmarkModel: FetchableModel {
	static let plural = "bookmarks"

	static func apply(_ options: EmptyOptions, to descriptor: inout FetchDescriptor<BookmarkModel>) {
		descriptor.sortBy = [SortDescriptor(\BookmarkModel.address)]
	}

	func describe() -> String {
		"\(name) @\(hex(address)) created=\(created) summary=\(summary) program=\(binary.name)"
	}
}
