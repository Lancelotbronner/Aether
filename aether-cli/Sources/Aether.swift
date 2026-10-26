import ArgumentParser
import Foundation
import SwiftData

@main struct aether: AsyncParsableCommand {
	static let configuration = CommandConfiguration(
			abstract: "A utility for working with Aether projects.",
			subcommands: [
				ProgramCommand.self,
				SectionCommand.self,
				SegmentCommand.self,
				StringCommand.self,

				NewCommand.self,
				ImportCommand.self,
			])
}

struct AetherOptions: ParsableArguments {
	@Option(help: "The project file to open", completion: .file(extensions: ["aetherproj"]))
	var project: String

	lazy var projectURL: URL = {
		URL(filePath: project, directoryHint: .notDirectory)
	}()

	lazy var modelContainer: ModelContainer = {
		try! ModelContainer(for: .project, configurations: [
			ModelConfiguration(schema: .project, url: projectURL.appending(path: "StoreContent", directoryHint: .notDirectory))
		])
	}()

	@MainActor
	var mainContext: ModelContext {
		mutating get {
			modelContainer.mainContext
		}
	}

	var backgroundContext: ModelContext {
		mutating get {
			ModelContext(modelContainer)
		}
	}
}
