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

	@Flag(help: "Exit non-zero when the report finds a problem: a symbol row with bytes no section accounts for, or symbol rows that carry no kind or type at all")
	var strict = false

	mutating func run() async throws {
		let context = try aether.backgroundContext()
		let programs = try context.fetch(FetchDescriptor<BinaryModel>())

		let counts: [RowField] = [
			field("project", aether.projectURL.path),
			field("store", aether.storeURL.path),
			field("cli", cliVersion),
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
			let kinds: String
			let types: String
			let bindings: String
			let untyped: Bool
		}

		var rows: [Diagnosis] = []
		for program in programs {
			var inside = 0
			var atZero = 0
			var outside: [SymbolModel] = []
			// The histograms ride along in the walk the containment check already
			// does: `doctor` visits every symbol of every program here for a
			// reason no predicate can state, so a distribution costs no query.
			var kinds: [SymbolKind: Int] = [:]
			var types: [SymbolType: Int] = [:]
			var bindings: [SymbolBinding: Int] = [:]
			for symbol in program.symbols {
				kinds[symbol.kind, default: 0] += 1
				types[symbol.type, default: 0] += 1
				bindings[symbol.binding, default: 0] += 1
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
			let symbols = inside + atZero + outside.count
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
				outside: outside,
				kinds: histogram(kinds),
				types: histogram(types),
				bindings: histogram(bindings),
				// The tell for "this store predates typed symbolization" that is
				// reachable without SwiftData's own migration dump: the older
				// fixture documented in CLI.md stored `rawType` 0 on all 26 of
				// its rows, which is the only shape where every row is unknown
				// in both axes at once.
				untyped: symbols > 0
					&& (kinds[SymbolKind.unknown] ?? 0) == symbols
					&& (types[SymbolType.unknown] ?? 0) == symbols
			))
		}

		// Each problem the report can see is counted once, so `--strict` is a
		// verdict on the lines above rather than a second diagnosis.
		var problems = 0
		for row in rows {
			problems += row.outside.count
			if row.untyped {
				problems += 1
			}
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
					field("kinds", row.kinds),
					field("types", row.types),
					field("bindings", row.bindings),
					field("untyped", row.untyped),
				]))
			}
			print(jsonRows(objects))
			// `ExitCode` is the one error ArgumentParser exits on without printing
			// another line, which is what makes the exit status the only thing
			// `--json` has to add: the counts are already in the objects.
			if strict, problems > 0 {
				throw ExitCode(1)
			}
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
			if !row.outside.isEmpty {
				print("outside one — a row with bytes no section accounts for:")
				for symbol in row.outside.prefix(5) {
					print("  \(symbol.describe())")
				}
				if row.outside.count > 5 {
					print("  … and \(row.outside.count - 5) more")
				}
			}
			// A program with no symbol rows would print three empty histograms,
			// so the line belongs to the rows rather than to the program.
			if !row.kinds.isEmpty {
				print("\(row.program): kinds \(row.kinds) — types \(row.types) — bindings \(row.bindings)")
			}
			if row.untyped {
				print("\(row.program): every symbol row is kind=unknown type=unknown — the shape a store written before typed symbolization has, and what makes a census of non-zero rows look like a clean store")
			}
		}
		if strict, problems > 0 {
			throw ExitCode(1)
		}
	}
}

/// A distribution over the rows `doctor` already walked, printed in the enum's
/// own case order with zero counts dropped, so the line reads in the order the
/// help strings number the raw values.
private func histogram<T: CaseIterable & Hashable>(_ counts: [T: Int]) -> String {
	var parts: [String] = []
	for kind in T.allCases {
		guard let count = counts[kind], count > 0 else { continue }
		parts.append("\(kind):\(count)")
	}
	return parts.joined(separator: " ")
}
