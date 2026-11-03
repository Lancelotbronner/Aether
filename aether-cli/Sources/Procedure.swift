import ArgumentParser
import AetherKit
import Foundation
import SwiftData

struct ProcedureCommand: AsyncParsableCommand {
	static let configuration = CommandConfiguration(
		commandName: "procedure",
		abstract: "Work with procedures.",
		subcommands: [
			FetchCommand<ProcedureModel>.self,
			CountCommand<ProcedureModel>.self,
			DeleteCommand<ProcedureModel>.self,
			DetectCommand.self,
		])
}

extension ProcedureModel: FetchableModel {
	static let plural = "procedures"

	struct FetchOptions: ParsableArguments {
		@Option(help: "Only procedures whose symbol name contains this text")
		var name: String?
	}

	static func apply(_ options: FetchOptions, to descriptor: inout FetchDescriptor<ProcedureModel>) {
		descriptor.sortBy = [SortDescriptor(\ProcedureModel.symbol.address)]

		if let name = options.name, !name.isEmpty {
			descriptor.predicate = #Predicate<ProcedureModel> { $0.symbol.name.contains(name) }
		}
	}

	func describe() -> String {
		"\(symbol.name) @\(String(format: "%llX", symbol.address)) size=\(symbol.size) frame=\(stackSize)"
	}
}

struct DetectCommand: AsyncParsableCommand {
	static let configuration = CommandConfiguration(
		commandName: "detect",
		abstract: "Run the procedure detection pass over every binary in the project.")

	@OptionGroup var aether: AetherOptions

	mutating func run() async throws {
		let context = aether.backgroundContext
		for binary in try context.fetch(FetchDescriptor<BinaryModel>()) {
			let report = ProcedureDetector().detect(in: binary)
			print("\(binary.name): \(report.summary), \(binary.procedures.count) total procedures")
		}
		if !aether.dryRun {
			try context.save()
		}
	}
}
