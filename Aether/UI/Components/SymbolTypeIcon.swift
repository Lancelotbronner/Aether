import Foundation
import AetherKit

// Consumed by `SymbolNavigator`.
extension SymbolType {
	var icon: String {
		switch self {
		case .function: return "f.square"
		case .ascii, .utf8, .utf16: return "text.quote"
		case .ptr: return "arrow.up.right.square"
		case .u8, .u16, .u32, .u64, .u128: return "d.square"
		case .unknown: return "questionmark.square"
		}
	}
}
