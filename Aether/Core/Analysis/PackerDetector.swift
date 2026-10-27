import Foundation
import AetherKit

struct PackerResult: Identifiable {
	let id = UUID()
	let name: String
	let confidence: Double
	let details: String
}
