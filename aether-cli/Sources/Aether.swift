import ArgumentParser
import Foundation
import SwiftData

@main struct aether: AsyncParsableCommand {
	static let configuration = CommandConfiguration(
			abstract: "A utility for working with Aether projects.",
			subcommands: [ProgramCommand.self],
			defaultSubcommand: ProgramCommand.self)

}

struct AetherOptions: ParsableArguments, Sendable {
	@Option(help: "The project file to open", completion: .file(extensions: ["aetherproj"]))
	var project: String

	lazy var projectURL: URL = {
		URL(filePath: project, directoryHint: .notDirectory)
	}()

	lazy var modelContainer: ModelContainer = {
		try! ModelContainer(for: .project, configurations: [
			ModelConfiguration(url: projectURL.appending(path: "StoreContent", directoryHint: .notDirectory))
		])
	}()

	@MainActor
	var modelContext: ModelContext {
		mutating get {
			modelContainer.mainContext
		}
	}
}
