import Foundation

struct EntropyResult {
	let overallEntropy: Double
	let sectionEntropies: [SectionEntropy]
	let heatmap: [EntropyBlock]
}

struct SectionEntropy: Identifiable {
	let id = UUID()
	let name: String
	let entropy: Double
	let size: Int
	let isPacked: Bool
	let isEncrypted: Bool

	var assessment: String {
		if isEncrypted { return "Likely encrypted" }
		if isPacked { return "Likely packed" }
		if entropy > 6.5 { return "High entropy" }
		if entropy > 4.0 { return "Normal" }
		return "Low entropy"
	}
}

struct EntropyBlock: Identifiable {
	let id = UUID()
	let offset: Int
	let entropy: Double
}
