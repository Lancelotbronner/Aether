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
			InsertCommand<BookmarkModel>.self,
		])
}

extension BookmarkModel: FetchableModel {
	static let plural = "bookmarks"

	struct FetchOptions: ParsableArguments {
		@Option(help: "Filters to a specific program")
		var binary: String?

		@Option(help: "Search within the bookmark name")
		var name: String?

		@Option(help: "Filter to a bookmark at an address (decimal; addresses print as hex)")
		var address: UInt64?

		@Option(help: "Search within the bookmark summary")
		var summary: String?
	}

	static func apply(_ options: FetchOptions, to descriptor: inout FetchDescriptor<BookmarkModel>) {
		let binary = options.binary.flatMap { filter in
			#Predicate<BookmarkModel> { $0.binary.name == filter }
		} ?? .true
		let name = options.name.flatMap { filter in
			#Predicate<BookmarkModel> { $0.name.localizedStandardContains(filter) }
		} ?? .true
		let address = options.address.flatMap { filter in
			#Predicate<BookmarkModel> { $0.address == filter }
		} ?? .true
		let summary = options.summary.flatMap { filter in
			#Predicate<BookmarkModel> { $0.summary.localizedStandardContains(filter) }
		} ?? .true
		descriptor.predicate = #Predicate<BookmarkModel> {
			binary.evaluate($0) && name.evaluate($0) && address.evaluate($0) && summary.evaluate($0)
		}
		descriptor.sortBy = [SortDescriptor(\BookmarkModel.address)]
	}

	func describe() -> String {
		"\(name) @\(hex(address)) created=\(created) summary=\(summary) program=\(binary.name)"
	}
}

extension BookmarkModel: InsertableModel {
	static let singular = "bookmark"

	struct InsertOptions: ParsableArguments {
		@Argument(help: "Name of the program to bookmark")
		var binary: String

		@Argument(help: "Bookmark name")
		var name: String

		@Argument(help: "Address to bookmark (decimal; addresses print as hex)")
		var address: UInt64

		@Option(help: "Note stored alongside the bookmark")
		var summary: String = ""
	}

	convenience init(options: InsertOptions, using modelContext: ModelContext) async throws {
		let binary = try requireBinary(named: options.binary, in: modelContext)

		self.init(options.name, at: options.address, in: binary)
		self.summary = options.summary
	}
}
