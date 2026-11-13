import ArgumentParser
import AetherKit
import Foundation
import SwiftData

struct HashCommand: AsyncParsableCommand {
	static let configuration = CommandConfiguration(
		commandName: "hash",
		abstract: "Digests a program: the whole file, the section bodies, and the section set itself.")

	@OptionGroup var aether: AetherOptions

	@Option(help: "Program to digest; without it every program in the project is digested")
	var binary: String?

	@Option(help: "Digest one scope only (file, body or layout) instead of all three")
	var scope: DigestScope?

	@Flag(help: "Print just the sha256 column, so the rows can be sorted or deduped")
	var digestOnly = false

	mutating func run() async throws {
		let context = try aether.backgroundContext()
		let programs = try context.fetch(FetchDescriptor<BinaryModel>(sortBy: [SortDescriptor(\BinaryModel.name)]))
		guard !programs.isEmpty else { throw AddressError.noProgram }
		var targets = programs
		if let name = binary {
			var matches: [BinaryModel] = []
			for model in programs where model.name == name {
				matches.append(model)
			}
			guard let only = matches.first else {
				throw HashError.noBinary(name: name, programs: programs.map { $0.name })
			}
			targets = [only]
		}
		let project = aether.projectURL.lastPathComponent
		if !digestOnly {
			print("Project: \(project)")
			print("Digests — one row per program and scope:")
		}
		for model in targets {
			for kind in DigestScope.allCases {
				if let only = scope, only != kind { continue }
				let bytes = model.digestInput(kind)
				if digestOnly {
					print(model.hash(.sha256, of: bytes))
				} else {
					print("program=\(model.name) scope=\(kind.rawValue) input=\(bytes.count) md5=\(model.hash(.md5, of: bytes)) sha256=\(model.hash(.sha256, of: bytes))")
				}
			}
		}
	}
}

extension DigestScope: ExpressibleByArgument {}

/// A `--binary` that names nothing. `requireBinary`'s `InsertError` prints
/// `unknownBinary("Nope")`, which is a leak of an internal error enum rather
/// than an answer, and a digest sweep is exactly the case where the reader
/// needs to know what the project does hold.
enum HashError: LocalizedError {
	case noBinary(name: String, programs: [String])

	var errorDescription: String? {
		switch self {
		case .noBinary(let name, let programs):
			return "No program named \(name) — this project has \(programs.joined(separator: ", "))"
		}
	}
}
