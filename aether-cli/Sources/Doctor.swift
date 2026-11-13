import ArgumentParser
import AetherKit
import Foundation
import SwiftData

struct DoctorCommand: AsyncParsableCommand {
	static let configuration = CommandConfiguration(
		commandName: "doctor",
		abstract: "Report what a store actually holds, so a document written before the current passes ran can be told apart from an empty binary.")

	@OptionGroup var aether: AetherOptions

	@Flag(help: "Emit the report as JSON objects instead of the report lines")
	var json = false

	mutating func run() async throws {
		let context = try aether.backgroundContext()
		let programs = try context.fetch(FetchDescriptor<BinaryModel>())

		var counts: [RowField] = [
			field("project", aether.projectURL.path),
			field("store", aether.storeURL.path),
			field("programs", programs.count),
			field("segments", try context.fetchCount(FetchDescriptor<SegmentModel>())),
			field("sections", try context.fetchCount(FetchDescriptor<SectionModel>())),
			field("symbols", try context.fetchCount(FetchDescriptor<SymbolModel>())),
			field("procedures", try context.fetchCount(FetchDescriptor<ProcedureModel>())),
			field("annotations", try context.fetchCount(FetchDescriptor<AnnotationModel>())),
			field("bookmarks", try context.fetchCount(FetchDescriptor<BookmarkModel>())),
		]

		// Each program's containment is computed here rather than asked of a
		// descriptor: `BinaryModel.sections` / `.symbols` are public relationships,
		// and "is this row's address covered by a section of *this* program" is a
		// per-program question the predicate language cannot state.
		struct Diagnosis {
			let program: String
			let identity: [RowField]
			let sections: Int
			let inside: Int
			let atZero: Int
			let outside: [SymbolModel]
		}

		var rows: [Diagnosis] = []
		for program in programs {
			var inside = 0
			var atZero = 0
			var outside: [SymbolModel] = []
			for symbol in program.symbols {
				// A row at address 0 is an import: it has a name and no place, so
				// counting it as "outside a section" would flag every binary that
				// links anything.
				if symbol.address == 0 {
					atZero += 1
					continue
				}
				if program.section(containing: symbol.address) != nil {
					inside += 1
				} else {
					outside.append(symbol)
				}
			}
			rows.append(Diagnosis(
				program: program.name,
				identity: [
					field("format", program.format),
					field("endian", program.endian),
					field("architecture", program.architecture),
					field("bits", program.is64 ? 64 : 32),
					field("bytes", program.data.count),
					field("base", hex(program.baseAddress)),
					field("entry", hex(program.entryPoint)),
					field("file", program.fileURL?.path ?? "<not read from disk>"),
				],
				sections: program.sections.count,
				inside: inside,
				atZero: atZero,
				outside: outside
			))
		}

		if json {
			var objects = [jsonRow(counts)]
			for row in rows {
				objects.append(jsonRow([
					field("program", row.program),
					field("sections", row.sections),
				] + row.identity + [
					field("symbols", row.inside + row.atZero + row.outside.count),
					field("insideSections", row.inside),
					field("atZero", row.atZero),
					field("outsideSections", row.outside.count),
				]))
			}
			print(jsonRows(objects))
			return
		}

		print(render(counts))
		guard !programs.isEmpty else {
			print("the store holds no program — import one before asking anything else of it")
			return
		}
		for row in rows {
			print("\(row.program): \(render(row.identity))")
			print("\(row.program): \(row.inside + row.atZero + row.outside.count) symbols over \(row.sections) sections — \(row.inside) inside a section, \(row.atZero) at address 0, \(row.outside.count) outside one")
			guard !row.outside.isEmpty else { continue }
			print("outside one — a row with bytes no section accounts for:")
			for symbol in row.outside.prefix(5) {
				print("  \(symbol.describe())")
			}
			if row.outside.count > 5 {
				print("  … and \(row.outside.count - 5) more")
			}
		}
	}
}
