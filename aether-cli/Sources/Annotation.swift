import ArgumentParser
import Foundation
import AetherKit
import SwiftData

struct AnnotationCommand: AsyncParsableCommand {
	static let configuration = CommandConfiguration(
		commandName: "annotation",
		abstract: "Work with annotations.",
		subcommands: [
			FetchCommand<AnnotationModel>.self,
			CountCommand<AnnotationModel>.self,
			DeleteCommand<AnnotationModel>.self,
		])
}

extension AnnotationModel: FetchableModel {
	static let plural = "annotations"

	static func apply(_ options: EmptyOptions, to descriptor: inout FetchDescriptor<AnnotationModel>) {
		descriptor.sortBy = [SortDescriptor(\AnnotationModel.address)]
	}

	func describe() -> String {
		"\(text) @\(hex(address)) kind=\(kind) program=\(binary.name)"
	}
}
