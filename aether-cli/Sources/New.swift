import ArgumentParser
import AetherKit
import SwiftData
import Foundation

struct NewCommand: AsyncParsableCommand {
	static let configuration = CommandConfiguration(
		commandName: "new",
		abstract: "Creates an empty project at the specified location.")

	@Argument(help: "appends .aetherproj if missing")
	var path: String

	mutating func run() async throws {
		var url = URL(filePath: path, directoryHint: .notDirectory)

		if url.pathExtension != "aetherproj" {
			url = url.appendingPathExtension("aetherproj")
		}

		try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)

		let dataURL = url.appending(component: "StoreContent", directoryHint: .notDirectory)
		let modelContainer = try ModelContainer(for: .project, configurations: ModelConfiguration(schema: .project, url: dataURL))
		let modelContext = ModelContext(modelContainer)

		try modelContext.save()
		print("Successfully created \(url.lastPathComponent)")
	}
}
