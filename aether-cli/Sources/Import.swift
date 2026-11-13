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

	mutating func run() async throws {
		let modelContext = try aether.backgroundContext()
		let url = URL(filePath: executablePath, directoryHint: .notDirectory)

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
			print(jsonRow(binary.fields()))
		} else {
			print(binary.describe())
		}
	}
}
