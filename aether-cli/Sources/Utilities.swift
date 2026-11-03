import ArgumentParser

struct EmptyOptions: ParsableArguments {}

/// Upper-case hexadecimal, matching the way addresses print elsewhere.
func hex(_ value: some BinaryInteger) -> String {
	String(value, radix: 16, uppercase: true)
}

enum InsertError: Error {
	case unknownBinary(String)
}
