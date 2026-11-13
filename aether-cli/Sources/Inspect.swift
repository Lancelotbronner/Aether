import ArgumentParser
import AetherKit
import SwiftData
import Foundation

struct InspectCommand: AsyncParsableCommand {
	static let configuration = CommandConfiguration(
		commandName: "inspect",
		abstract: "Parse an executable in memory: no project, no store on disk.")

	@Argument(help: "Path to a thin 64-bit Mach-O executable", completion: .file())
	var executablePath: String

	@Flag(help: "Run procedure detection and list the procedures it finds")
	var analyze = false

	@Flag(help: "Print the loader's parse narration before the census")
	var log = false

	mutating func run() async throws {
		// The entry point of the store question: without `isStoredInMemoryOnly`
		// a `ModelContainer` opens the default on-disk store under
		// `~/Library/Application Support`, so an inspect run would create
		// rows in a document nobody asked for.
		let container = try ModelContainer(for: .project, configurations: [
			ModelConfiguration(schema: .project, isStoredInMemoryOnly: true)
		])
		let context = ModelContext(container)

		let url = URL(filePath: executablePath, directoryHint: .notDirectory)

		let binary = BinaryModel()
		binary.data = try Data(contentsOf: url, options: .mappedIfSafe)
		binary.fileURL = url
		binary.name = url.lastPathComponent
		context.insert(binary)

		let report = try await MachOLoader.load(binary, analyze: analyze)

		if log {
			print(report.log)
		}

		print(binary.describe())

		let segments = binary.segments.sorted { $0.address < $1.address }
		print("\(segments.count) segments:")
		for segment in segments {
			print("\t\(segment.describe())")
		}

		let sections = binary.sections.sorted { $0.address < $1.address }
		print("\(sections.count) sections:")
		for section in sections {
			print("\t\(section.describe())")
		}

		print("symbols (\(binary.symbols.count)):")
		print("\tkind [\(tally(binary.symbols.map { "\($0.kind)" }))]")
		print("\tbinding [\(tally(binary.symbols.map { "\($0.binding)" }))]")
		print("\ttype [\(tally(binary.symbols.map { "\($0.type)" }))]")
		print("\tstrings=\(binary.symbols.filter { $0.type.isString }.count)")

		print("procedures (\(report.procedures))" + (analyze ? ":" : ", detection skipped"))
		if analyze {
			for procedure in binary.procedures.sorted(by: { $0.symbol.address < $1.symbol.address }) {
				print("\t\(procedure.describe())")
			}
		}
	}
}

/// Alphabetically ordered `key=count` census over already-loaded rows. Not a
/// `#Predicate`: these are computed properties, which the query macro cannot
/// see, and inspect never needs to filter.
private func tally(_ values: [String]) -> String {
	var counts: [String: Int] = [:]
	for value in values {
		counts[value, default: 0] += 1
	}
	return counts.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: " ")
}
