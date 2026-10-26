import ArgumentParser
import AetherKit
import SwiftData
import Foundation

struct ImportCommand: AsyncParsableCommand {
	static let configuration = CommandConfiguration(
		commandName: "import",
		abstract: "Import and load an executable into an existing document.")

	@OptionGroup var aether: AetherOptions

	@Argument(help: "Path to a thin 64-bit Mach-O executable")
	var executablePath: String

	mutating func run() async throws {
		let modelContext = aether.backgroundContext
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
		try await MachOLoader.load(binary)
		try modelContext.save()

		print("Successfully imported as \(binary.persistentModelID).")
	}
}
