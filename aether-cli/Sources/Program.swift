import ArgumentParser
import AetherKit
import SwiftData

struct ProgramCommand: AsyncParsableCommand {
	static let configuration = CommandConfiguration(
		commandName: "program",
		abstract: "Work with programs.",
		subcommands: [
			FetchCommand<BinaryModel>.self,
			CountCommand<BinaryModel>.self,
			DeleteCommand<BinaryModel>.self,
		])
}

extension BinaryModel: FetchableModel {
	static let plural = "programs"

	func describe() -> String {
		"\(name) \(format.rawValue) \(architecture.rawValue) \(endian.rawValue) \(is64 ? "64-bit" : "32-bit") \(data.count) bytes base=\(hex(baseAddress)) entry=\(hex(entryPoint)) stack=\(stackSize) file=\(fileURL?.path ?? "<not read from disk>") segments=\(segments.count) sections=\(sections.count) symbols=\(symbols.count) procedures=\(procedures.count) references=\(references.count) annotations=\(annotations.count) bookmarks=\(bookmarks.count)"
	}
}
