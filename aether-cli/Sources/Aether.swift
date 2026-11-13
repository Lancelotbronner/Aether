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
			SymbolCommand.self,
			ProcedureCommand.self,
			AnnotationCommand.self,
			BookmarkCommand.self,

			ImportCommand.self,
			InspectCommand.self,
			AddrCommand.self,
			BytesCommand.self,
			FindCommand.self,
			HashCommand.self,
			DoctorCommand.self,
		])
}

/// How a store can fail to be usable, as opposed to what is inside it. Both
/// cases used to be invisible: a typo'd path became an empty store that reported
/// `Showing 0 models:` with exit 0, and a store written by an older model list
/// trapped out of `try!` with exit 133.
enum StoreError: LocalizedError {
	case missing(url: URL)
	case unopened(url: URL, reason: String)

	var errorDescription: String? {
		switch self {
		case .missing(let url):
			return "No project at \(url.path) — --existing does not create one"
		case .unopened(let url, let reason):
			return "Cannot open the store at \(url.path): \(reason) — a store written by an older model list is the usual cause"
		}
	}
}

struct AetherOptions: ParsableArguments {
	@Flag
	var dryRun = false

	@Flag(help: "Fail when the project does not exist instead of creating it: a typo'd path otherwise reads as a valid, empty document")
	var existing = false

	@Argument(help: "The project file to open, created if it does not exist", completion: .file(extensions: ["aetherproj"]))
	var project: String

	var projectURL: URL {
		URL(filePath: project, directoryHint: .notDirectory)
	}

	/// The SQLite store's own directory inside the bundle, named apart from
	/// `projectURL` so `doctor` can report what it is diagnosing.
	var storeURL: URL {
		projectURL.appending(path: "StoreContent", directoryHint: .notDirectory)
	}

	/// Opened rather than force-unwrapped: a store written by a model list this
	/// build cannot migrate used to trap out of `try!` — exit 133, which a script
	/// cannot tell apart from a resource kill — after SwiftData printed ~280 KB of
	/// CoreData schema dump on its own account. Nothing is cached here because a
	/// `ParsableArguments` group has to stay `Decodable`, and every command opens a
	/// store at most once.
	func modelContainer() throws -> ModelContainer {
		if existing, !FileManager.default.fileExists(atPath: projectURL.path) {
			throw StoreError.missing(url: projectURL)
		}
		do {
			return try ModelContainer(for: .project, configurations: [
				ModelConfiguration(schema: .project, url: storeURL)
			])
		} catch {
			throw StoreError.unopened(url: projectURL, reason: error.localizedDescription)
		}
	}

	@MainActor
	func mainContext() throws -> ModelContext {
		try modelContainer().mainContext
	}

	func backgroundContext() throws -> ModelContext {
		try ModelContext(modelContainer())
	}
}
