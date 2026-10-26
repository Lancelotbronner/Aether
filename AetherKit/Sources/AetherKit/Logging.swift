import Foundation
import OSLog

public extension Logger {
	static let app = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Aether", category: "App")
}

public extension Duration {
	/// Compact duration for log messages: `842 µs`, `842 ms`, or `1.204 s`.
	var logDescription: String {
		let components = self.components
		let seconds = Double(components.seconds) + Double(components.attoseconds) / 1e18
		if seconds >= 1 {
			return String(format: "%.3f s", seconds)
		}
		if seconds >= 0.001 {
			return String(format: "%.0f ms", seconds * 1_000)
		}
		return String(format: "%.0f µs", seconds * 1_000_000)
	}
}
