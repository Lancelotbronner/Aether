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

		@Option(help: "Filter to a segment at an address (decimal; addresses print as hex)")
		var address: UInt64?

		@Option(help: "Filter to segments with these exact initial protection bits (decimal; 1 read, 2 write, 4 execute — printed as hex by fetch)")
		var protection: UInt32?
	}

	static func apply(_ options: FetchOptions, to descriptor: inout FetchDescriptor<SegmentModel>) {
		let binary = options.binary.flatMap { filter in
			#Predicate<SegmentModel> { $0.binary.name == filter }
		} ?? .true
		let name = options.name.flatMap { filter in
			#Predicate<SegmentModel> { $0.name.localizedStandardContains(filter) }
		} ?? .true
		let address = options.address.flatMap { filter in
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

	func describe() -> String {
		"\(name) @\(hex(address)) size=\(size) file=\(hex(fileOffset))+\(hex(fileSize))"
			+ " prot=\(protectionString) maxprot=\(hex(maxProtection)) initprot=\(hex(initProtection))"
			+ " sections=\(sections.count) program=\(binary.name)"
	}
}

extension SegmentModel: InsertableModel {
	static let singular = "segment"

	struct InsertOptions: ParsableArguments {
		@Argument(help: "Name of the program to add a segment to")
		var binary: String

		@Argument(help: "Segment name")
		var name: String

		@Argument(help: "Memory address of the segment (decimal; addresses print as hex)")
		var address: UInt64

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
		let address = options.address
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
