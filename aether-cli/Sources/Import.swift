import ArgumentParser
import AetherKit
import SwiftData
import Foundation

struct ImportCommand: AsyncParsableCommand {
	static let configuration = CommandConfiguration(
		commandName: "import",
		abstract: "Import and load an executable into an existing document.")

	@OptionGroup var aether: AetherOptions

	@Argument
	var executablePath: String

	mutating func run() async throws {
		let modelContext = aether.backgroundContext
		let url = URL(filePath: executablePath, directoryHint: .notDirectory)

		let binary = BinaryModel()
		binary.data = try Data(contentsOf: url, options: .mappedIfSafe)
		binary.fileURL = url
		binary.name = url.lastPathComponent
		modelContext.insert(binary)
		try modelContext.save()

		print("Successfully imported as \(binary.persistentModelID).")

		try await MachOLoader.load(binary)
	}
}
