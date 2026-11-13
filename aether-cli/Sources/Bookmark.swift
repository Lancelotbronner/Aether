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

		@Option(help: "Filter to a bookmark at an address: decimal, 0x…, @…, off:<file offset> or a symbol name")
		var address: AddressArgument?

		@Option(help: "Search within the bookmark summary")
		var summary: String?
	}

	static func apply(_ options: FetchOptions, to descriptor: inout FetchDescriptor<BookmarkModel>, in modelContext: ModelContext) throws {
		let addressValue = try filterAddress(options.address, named: options.binary, in: modelContext)
		let binary = options.binary.flatMap { filter in
			#Predicate<BookmarkModel> { $0.binary.name == filter }
		} ?? .true
		let name = options.name.flatMap { filter in
			#Predicate<BookmarkModel> { $0.name.localizedStandardContains(filter) }
		} ?? .true
		let address = addressValue.flatMap { filter in
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

	func fields() -> [RowField] {
		[
			head("name", name),
			at(hex(address)),
			field("created", created),
			field("summary", summary),
			field("program", binary.name),
		]
	}
}

extension BookmarkModel: InsertableModel {
	static let singular = "bookmark"

	struct InsertOptions: ParsableArguments {
		@Argument(help: "Name of the program to bookmark")
		var binary: String

		@Argument(help: "Bookmark name")
		var name: String

		@Argument(help: "Address to bookmark: decimal, 0x…, @…, off:<file offset> or a symbol name")
		var address: AddressArgument

		@Option(help: "Note stored alongside the bookmark")
		var summary: String = ""
	}

	convenience init(options: InsertOptions, using modelContext: ModelContext) async throws {
		let binary = try requireBinary(named: options.binary, in: modelContext)
		let address = try resolveAddress(options.address, named: binary.name, in: modelContext)

		self.init(options.name, at: address, in: binary)
		self.summary = options.summary
	}
}
