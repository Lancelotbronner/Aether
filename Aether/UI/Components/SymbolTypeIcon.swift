import Foundation
import AetherKit

// Task 12c: re-homed from the deleted `Models/Symbol.swift` (the legacy
// `Symbol` struct is gone; `SymbolModel` is the stored row). Consumed by
// `SymbolNavigator` and `AetherToolbar`.
extension SymbolType {
	var icon: String {
		switch self {
		case .function: return "f.square"
		case .data: return "d.square"
		case .object: return "cube"
		case .section: return "square.stack"
		case .file: return "doc"
		case .unknown: return "questionmark.square"
		}
	}
}
