import ArgumentParser
import AetherKit
import SwiftData

struct SegmentCommand: AsyncParsableCommand {
	static let configuration = CommandConfiguration(
		commandName: "segment",
		abstract: "Work with segments.",
		subcommands: [
			FetchCommand<SegmentModel>.self,
			CountCommand<SegmentModel>.self,
			DeleteCommand<SegmentModel>.self,
		])
}

extension SegmentModel: FetchableModel {
	static let plural = "segments"

	func describe() -> String {
		"\(name) @\(hex(address)) size=\(size) file=\(hex(fileOffset))+\(hex(fileSize))"
			+ " prot=\(protectionString) maxprot=\(hex(maxProtection)) initprot=\(hex(initProtection))"
			+ " sections=\(sections.count) program=\(binary.name)"
	}
}
