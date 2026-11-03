import ArgumentParser
import AetherKit
import SwiftData
import Foundation

struct EmptyOptions: ParsableArguments {}

/// Upper-case hexadecimal, matching the way addresses print elsewhere.
func hex(_ value: some BinaryInteger) -> String {
	String(value, radix: 16, uppercase: true)
}

enum InsertError: Error {
	case unknownBinary(String)
	case unknownSegment(name: String, binary: String)
	case unknownSymbol(name: String, binary: String)
	case duplicate(kind: String, key: String)
}

/// Resolve the program a subcommand was told to operate on.
func requireBinary(named name: String, in modelContext: ModelContext) throws -> BinaryModel {
	var descriptor = FetchDescriptor<BinaryModel>()
	descriptor.predicate = #Predicate<BinaryModel> { $0.name == name }
	descriptor.fetchLimit = 1
	guard let binary = try modelContext.fetch(descriptor).first else {
		throw InsertError.unknownBinary(name)
	}
	return binary
}
