import ArgumentParser
import AetherKit
import SwiftData
import Foundation

struct ImportCommand: AsyncParsableCommand {
	static let configuration = CommandConfiguration(
		commandName: "import",
		abstract: "Import and load an executable into a project.")

	@OptionGroup var aether: AetherOptions

	@Argument(help: "Path to a thin 64-bit Mach-O executable")
	var executablePath: String

	@Flag(help: "Parse structure only; skip the procedure detection pass")
	var noAnalyze = false

	@Flag(help: "Do not print the loader's parse narration")
	var quiet = false

	@Flag(help: "Print the imported program as a JSON object")
	var json = false

	@Flag(help: "Delete any program already stored under the file's name first, so re-parsing does not leave a second copy of it")
	var replace = false

	mutating func run() async throws {
		let modelContext = try aether.backgroundContext()
		let url = URL(filePath: executablePath, directoryHint: .notDirectory)

		// A replace is a delete and an import in one command, and the delete has
		// to come first: `#Unique<SymbolModel>([\.binary, \.address, \.identifier])`
		// is scoped per program, so re-parsing over the rows the old program left
		// behind is a unique-key clash rather than an in-place update. The rows
		// to remove are selected by a predicate on `name` rather than by reading
		// `name` back off every program, because that read pulls each program's
		// whole `data` blob out of external storage to decide a match.
		var replaced: Int?
		var replacedLine: String?
		if replace {
			let target = url.lastPathComponent
			var query = FetchDescriptor<BinaryModel>()
			query.predicate = #Predicate<BinaryModel> { $0.name == target }
			query.propertiesToFetch = []
			query.relationshipKeyPathsForPrefetching = []
			let doomed = try modelContext.fetch(query)
			if !doomed.isEmpty {
				// Asked before the rows go, as `delete` does, so the numbers
				// describe what this command is about to take with it.
				let cascade = BinaryModel.cascade(of: doomed, in: modelContext)
				for model in doomed {
					modelContext.delete(model)
				}
				replaced = doomed.count
				var line = "Deleted \(doomed.count) programs"
				if let clause = cascade.describe() {
					line += " — \(clause)"
				}
				replacedLine = line
			}
		}

		let binary = BinaryModel()
		binary.data = try Data(contentsOf: url, options: .mappedIfSafe)
		binary.fileURL = url
		binary.name = url.lastPathComponent
		modelContext.insert(binary)

		// Load first, save second: the loader validates the header, so a
		// non-Mach-O (or fat/32-bit) file throws before anything is
		// persisted and the document is left untouched. Saving before the
		// load would also lose the parsed segments/sections/symbols, since
		// nothing else in this path saves.
		let report = try await MachOLoader.load(binary, analyze: !noAnalyze)

		// Reached only once the parse succeeded: a file the loader rejects prints
		// nothing here, and because the single `save()` is still below, it also
		// leaves the replaced program exactly where it was.
		if let line = replacedLine, !json {
			print(line)
		}

		// `--json` is for a script, and the narration is not part of the
		// report: the program row is. Treat the flag as implying `--quiet`.
		if !quiet, !json {
			print(report.log)
		}

		if !aether.dryRun {
			try modelContext.save()
		}

		// The command that creates the row prints the row, which is the same
		// one `program fetch` prints: the store's own identifier repr was
		// never a fact a caller could use.
		if json {
			var row = binary.fields()
			// Only when the flag was asked for: a script that passed `--replace`
			// gets the count it cannot infer from a row that looks brand new,
			// and one that did not gets the same object as before.
			if replace {
				row.append(field("replaced", replaced ?? 0))
			}
			print(jsonRow(row))
		} else {
			print(binary.describe())
		}
	}
}
