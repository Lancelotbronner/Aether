import Foundation

public struct PackerResult: Identifiable {
	public let id = UUID()
	public let name: String
	public let confidence: Double
	public let details: String
}
