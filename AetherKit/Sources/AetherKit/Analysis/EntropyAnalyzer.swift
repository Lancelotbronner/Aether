import Foundation

public struct EntropyResult {
	public let overallEntropy: Double
	public let sectionEntropies: [SectionEntropy]
	public let heatmap: [EntropyBlock]
}

public struct SectionEntropy: Identifiable {
	public let id = UUID()
	public let name: String
	public let entropy: Double
	public let size: Int
	public let isPacked: Bool
	public let isEncrypted: Bool

	public var assessment: String {
		if isEncrypted { return "Likely encrypted" }
		if isPacked { return "Likely packed" }
		if entropy > 6.5 { return "High entropy" }
		if entropy > 4.0 { return "Normal" }
		return "Low entropy"
	}
}

public struct EntropyBlock: Identifiable {
	public let id = UUID()
	public let offset: Int
	public let entropy: Double
}
