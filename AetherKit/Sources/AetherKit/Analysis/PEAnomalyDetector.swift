import Foundation

public struct PEAnomaly: Identifiable {
	public let id = UUID()
	public let title: String
	public let description: String
	public let severity: Severity

	public enum Severity: String, CaseIterable {
		case low = "Low"
		case medium = "Medium"
		case high = "High"
		case critical = "Critical"

		public var color: String {
			switch self {
			case .low: return "blue"
			case .medium: return "yellow"
			case .high: return "orange"
			case .critical: return "red"
			}
		}
	}
}
