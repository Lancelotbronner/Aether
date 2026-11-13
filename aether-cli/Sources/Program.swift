import ArgumentParser
import AetherKit
import Foundation
import SwiftData

struct ProgramCommand: AsyncParsableCommand {
	static let configuration = CommandConfiguration(
		commandName: "program",
		abstract: "Work with programs.",
		subcommands: [
			FetchCommand<BinaryModel>.self,
			CountCommand<BinaryModel>.self,
			DeleteCommand<BinaryModel>.self,
		])
}

extension BinaryModel: FetchableModel {
	static let plural = "programs"

	struct FetchOptions: ParsableArguments {
		@Option(help: "Filter on the program name")
		var name: String?

		@Option(help: "Filter on the file format (0 unknown, 1 Mach-O, 2 ELF, 3 PE, 4 Java)")
		var format: BinaryFormat?

		@Option(help: "Filter on the architecture (0 unknown, 1 x86_64, 2 Apple Silicon, 3 ARM64, 4 ARM64e, 5 i386, 6 ARMv7, 7 JVM)")
		var architecture: Architecture?

		@Option(help: "Filter on the endianness (0 little, 1 big)")
		var endian: Endianness?
	}

	static func apply(_ options: FetchOptions, to descriptor: inout FetchDescriptor<BinaryModel>, in modelContext: ModelContext) throws {
		let name = options.name.flatMap { filter in
			#Predicate<BinaryModel> { $0.name.localizedStandardContains(filter) }
		} ?? .true
		let format = options.format.flatMap { filter in
			#Predicate<BinaryModel> { $0.format == filter }
		} ?? .true
		let architecture = options.architecture.flatMap { filter in
			#Predicate<BinaryModel> { $0.architecture == filter }
		} ?? .true
		let endian = options.endian.flatMap { filter in
			#Predicate<BinaryModel> { $0.endian == filter }
		} ?? .true
		descriptor.predicate = #Predicate<BinaryModel> {
			name.evaluate($0) && format.evaluate($0) && architecture.evaluate($0) && endian.evaluate($0)
		}
		descriptor.sortBy = [SortDescriptor(\BinaryModel.name)]
	}

	func fields() -> [RowField] {
		[
			head("name", name),
			head("format", format),
			head("architecture", architecture),
			head("endian", endian),
			head("bits", is64 ? "64-bit" : "32-bit"),
			head("bytes", data.count, unit: "bytes"),
			field("sha256", sha256),
			field("base", hex(baseAddress)),
			field("entry", hex(entryPoint)),
			field("stack", stackSize),
			field("file", fileURL?.path ?? "<not read from disk>"),
			field("segments", segments.count),
			field("sections", sections.count),
			field("symbols", symbols.count),
			field("procedures", procedures.count),
			field("references", references.count),
			field("annotations", annotations.count),
			field("bookmarks", bookmarks.count),
		]
	}
}
