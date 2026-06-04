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

class EntropyAnalyzer {
    private let blockSize: Int

    init(blockSize: Int = 256) {
        self.blockSize = blockSize
    }

    func analyze(binary: BinaryFile) -> EntropyResult {
        let overallEntropy = shannonEntropy(binary.data)

        var sectionEntropies: [SectionEntropy] = []
        for section in binary.sections {
            guard !section.data.isEmpty else { continue }
            let ent = shannonEntropy(section.data)
            sectionEntropies.append(SectionEntropy(
                name: section.name,
                entropy: ent,
                size: section.data.count,
                isPacked: ent > 7.0,
                isEncrypted: ent > 7.5
            ))
        }

        let heatmap = generateHeatmap(data: binary.data)

        return EntropyResult(
            overallEntropy: overallEntropy,
            sectionEntropies: sectionEntropies,
            heatmap: heatmap
        )
    }

    func shannonEntropy(_ data: Data) -> Double {
        guard !data.isEmpty else { return 0.0 }

        var freq = [Int](repeating: 0, count: 256)
        for byte in data {
            freq[Int(byte)] += 1
        }

        let total = Double(data.count)
        var entropy = 0.0
        for count in freq {
            guard count > 0 else { continue }
            let p = Double(count) / total
            entropy -= p * log2(p)
        }
        return entropy
    }

    private func generateHeatmap(data: Data) -> [EntropyBlock] {
        var blocks: [EntropyBlock] = []
        var offset = 0
        while offset < data.count {
            let end = min(offset + blockSize, data.count)
            let blockData = data[data.startIndex + offset ..< data.startIndex + end]
            let ent = shannonEntropy(Data(blockData))
            blocks.append(EntropyBlock(offset: offset, entropy: ent))
            offset += blockSize
        }
        return blocks
    }
}
