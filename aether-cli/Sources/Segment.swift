import ArgumentParser
import AetherKit
import SwiftData

struct SegmentCommand: AsyncParsableCommand {
	static let configuration = CommandConfiguration(
		commandName: "segment",
		abstract: "Work with segments.",
		subcommands: [
			FetchCommand<SegmentModel>.self,
			CountCommand<BinaryModel>.self,
		],
		defaultSubcommand: FetchCommand<SegmentModel>.self)
}

extension SegmentModel: FetchableModel {
	static let plural = "segments"

	struct FetchOptions: ParsableArguments {

	}

	func describe() -> String {
		name
	}
}
