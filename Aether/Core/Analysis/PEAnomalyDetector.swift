import Foundation
import AetherKit

struct PEAnomaly: Identifiable {
	let id = UUID()
	let title: String
	let description: String
	let severity: Severity

	enum Severity: String, CaseIterable {
		case low = "Low"
		case medium = "Medium"
		case high = "High"
		case critical = "Critical"

		var color: String {
			switch self {
			case .low: return "blue"
			case .medium: return "yellow"
			case .high: return "orange"
			case .critical: return "red"
			}
		}
	}
}
