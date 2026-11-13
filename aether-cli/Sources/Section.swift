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
			InsertCommand<SectionModel>.self,
		])
}

extension SectionModel: FetchableModel {
	static let plural = "sections"

	struct FetchOptions: ParsableArguments {
		@Option(help: "Filters to a specific program")
		var binary: String?

		@Option(help: "Filters to a specific segment")
		var segment: String?

		@Option(help: "Search within the section name")
		var name: String?

		@Option(help: "Filter to a section at an address: decimal, 0x…, @…, off:<file offset> or a symbol name")
		var address: AddressArgument?

		@Option(help: "Filter to sections with these exact flag bits (decimal; printed as hex by fetch)")
		var flags: UInt32?
	}

	static func apply(_ options: FetchOptions, to descriptor: inout FetchDescriptor<SectionModel>, in modelContext: ModelContext) throws {
		let addressValue = try filterAddress(options.address, named: options.binary, in: modelContext)
		let binary = options.binary.flatMap { filter in
			#Predicate<SectionModel> { $0.binary.name == filter }
		} ?? .true
		let segment = options.segment.flatMap { filter in
			#Predicate<SectionModel> { $0.segment.name == filter }
		} ?? .true
		let name = options.name.flatMap { filter in
			#Predicate<SectionModel> { $0.name.localizedStandardContains(filter) }
		} ?? .true
		let address = addressValue.flatMap { filter in
			#Predicate<SectionModel> { $0.address == filter }
		} ?? .true
		let flags = options.flags.flatMap { filter in
			#Predicate<SectionModel> { $0.flags == filter }
		} ?? .true
		descriptor.predicate = #Predicate<SectionModel> {
			binary.evaluate($0) && segment.evaluate($0) && name.evaluate($0) && address.evaluate($0) && flags.evaluate($0)
		}
		descriptor.sortBy = [SortDescriptor(\SectionModel.address)]
	}

	func fields() -> [RowField] {
		[
			head("name", fullName),
			at(hex(address)),
			field("size", size),
			field("offset", hex(offset)),
			field("align", alignment),
			field("flags", hex(flags)),
			field("executable", isExecutable),
			field("zerofill", isZeroFill),
			field("code", containsCode),
			field("segment", segmentName),
			field("program", binary.name),
		]
	}
}

extension SectionModel: InsertableModel {
	static let singular = "section"

	struct InsertOptions: ParsableArguments {
		@Argument(help: "Name of the program to add a section to")
		var binary: String

		@Argument(help: "Name of the segment the section belongs to")
		var segment: String

		@Argument(help: "Section name")
		var name: String

		@Argument(help: "Address the section starts at: decimal, 0x…, @…, off:<file offset> or a symbol name")
		var address: AddressArgument

		@Option(help: "Size of the section in memory, in bytes (decimal)")
		var size: UInt64 = 0

		@Option(help: "Offset of the section inside the file (decimal)")
		var offset: UInt32 = 0

		@Option(help: "Section alignment, as a power of two (decimal)")
		var alignment: UInt32 = 0

		@Option(help: "Section flag bits (decimal)")
		var flags: UInt32 = 0
	}

	convenience init(options: InsertOptions, using modelContext: ModelContext) async throws {
		let binary = try requireBinary(named: options.binary, in: modelContext)
		let binaryName = binary.name
		let segmentName = options.segment
		var segmentQuery = FetchDescriptor<SegmentModel>()
		segmentQuery.predicate = #Predicate<SegmentModel> { $0.name == segmentName && $0.binary.name == binaryName }
		segmentQuery.fetchLimit = 1
		guard let segment = try modelContext.fetch(segmentQuery).first else {
			throw InsertError.unknownSegment(name: segmentName, binary: binaryName)
		}

		let address = try resolveAddress(options.address, named: binaryName, in: modelContext)
		var taken = FetchDescriptor<SectionModel>()
		taken.predicate = #Predicate<SectionModel> { $0.binary.name == binaryName && $0.address == address }
		taken.fetchLimit = 1
		if try modelContext.fetch(taken).first != nil {
			throw InsertError.duplicate(kind: "section", key: "\(binaryName) @\(hex(address))")
		}

		self.init(in: segment, of: binary)
		self.segmentName = segment.name
		self.name = options.name
		self.address = address
		self.size = options.size
		self.offset = options.offset
		self.alignment = options.alignment
		self.flags = options.flags
	}
}
