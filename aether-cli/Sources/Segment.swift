import ArgumentParser
import AetherKit
import SwiftData
import Foundation

struct SegmentCommand: AsyncParsableCommand {
	static let configuration = CommandConfiguration(
		commandName: "segment",
		abstract: "Work with segments.",
		subcommands: [
			FetchCommand<SegmentModel>.self,
			CountCommand<SegmentModel>.self,
			DeleteCommand<SegmentModel>.self,
			InsertCommand<SegmentModel>.self,
		])
}

extension SegmentModel: FetchableModel {
	static let plural = "segments"

	struct FetchOptions: ParsableArguments {
		@Option(help: "Filters to a specific program")
		var binary: String?

		@Option(help: "Search within the segment name")
		var name: String?

		@Option(help: "Filter to a segment at an address: decimal, 0x…, @…, off:<file offset> or a symbol name")
		var address: AddressArgument?

		@Option(help: "Filter to segments with these exact initial protection bits (decimal; 1 read, 2 write, 4 execute — printed as hex by fetch)")
		var protection: UInt32?
	}

	static func apply(_ options: FetchOptions, to descriptor: inout FetchDescriptor<SegmentModel>, in modelContext: ModelContext) throws {
		let addressValue = try filterAddress(options.address, named: options.binary, in: modelContext)
		let binary = options.binary.flatMap { filter in
			#Predicate<SegmentModel> { $0.binary.name == filter }
		} ?? .true
		let name = options.name.flatMap { filter in
			#Predicate<SegmentModel> { $0.name.localizedStandardContains(filter) }
		} ?? .true
		let address = addressValue.flatMap { filter in
			#Predicate<SegmentModel> { $0.address == filter }
		} ?? .true
		let protection = options.protection.flatMap { filter in
			#Predicate<SegmentModel> { $0.initProtection == filter }
		} ?? .true
		descriptor.predicate = #Predicate<SegmentModel> {
			binary.evaluate($0) && name.evaluate($0) && address.evaluate($0) && protection.evaluate($0)
		}
		descriptor.sortBy = [SortDescriptor(\SegmentModel.address)]
	}

	func fields() -> [RowField] {
		[
			head("name", name),
			at(hex(address)),
			field("size", size),
			field("file", "\(hex(fileOffset))+\(hex(fileSize))"),
			field("prot", protectionString),
			field("maxprot", hex(maxProtection)),
			field("initprot", hex(initProtection)),
			field("sections", sections.count),
			field("program", binary.name),
		]
	}
}

extension SegmentModel: InsertableModel {
	static let singular = "segment"

	struct InsertOptions: ParsableArguments {
		@Argument(help: "Name of the program to add a segment to")
		var binary: String

		@Argument(help: "Segment name")
		var name: String

		@Argument(help: "Address the segment starts at: decimal, 0x…, @…, off:<file offset> or a symbol name")
		var address: AddressArgument

		@Option(help: "Size of the segment in memory, in bytes (decimal)")
		var size: UInt64 = 0

		@Option(help: "Offset of the segment inside the file (decimal)")
		var fileOffset: UInt64 = 0

		@Option(help: "Number of file bytes backing the segment (decimal)")
		var fileSize: UInt64 = 0

		@Option(help: "Maximum protection bits (1 read, 2 write, 4 execute)")
		var maxProtection: UInt32 = 0

		@Option(help: "Initial protection bits (1 read, 2 write, 4 execute)")
		var initProtection: UInt32 = 0
	}

	convenience init(options: InsertOptions, using modelContext: ModelContext) async throws {
		let binary = try requireBinary(named: options.binary, in: modelContext)
		let binaryName = binary.name
		let address = try resolveAddress(options.address, named: binaryName, in: modelContext)
		var taken = FetchDescriptor<SegmentModel>()
		taken.predicate = #Predicate<SegmentModel> { $0.binary.name == binaryName && $0.address == address }
		taken.fetchLimit = 1
		if try modelContext.fetch(taken).first != nil {
			throw InsertError.duplicate(kind: "segment", key: "\(binaryName) @\(hex(address))")
		}

		self.init(in: binary)
		self.name = options.name
		self.address = address
		self.size = options.size
		self.fileOffset = options.fileOffset
		self.fileSize = options.fileSize
		self.maxProtection = options.maxProtection
		self.initProtection = options.initProtection
	}
}
