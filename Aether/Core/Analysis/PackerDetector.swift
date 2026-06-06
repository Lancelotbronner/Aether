import Foundation

struct PackerResult: Identifiable {
    let id = UUID()
    let name: String
    let confidence: Double
    let details: String
}

nonisolated final class PackerDetector: Sendable {
    struct PackerSignature {
        let name: String
        let sectionNames: [String]
        let importFingerprint: [String]?
        let entryPointBytes: [UInt8]?
    }

    private let signatures: [PackerSignature] = [
        PackerSignature(
            name: "UPX",
            sectionNames: ["UPX0", "UPX1", "UPX2", ".UPX0", ".UPX1", ".UPX2"],
            importFingerprint: ["LoadLibraryA", "GetProcAddress"],
            entryPointBytes: nil
        ),
        PackerSignature(
            name: "VMProtect",
            sectionNames: [".vmp0", ".vmp1", ".vmp2"],
            importFingerprint: nil,
            entryPointBytes: nil
        ),
        PackerSignature(
            name: "Themida",
            sectionNames: [".themida", ".Themida"],
            importFingerprint: nil,
            entryPointBytes: nil
        ),
        PackerSignature(
            name: "ASPack",
            sectionNames: [".aspack", ".adata"],
            importFingerprint: nil,
            entryPointBytes: nil
        ),
        PackerSignature(
            name: "PECompact",
            sectionNames: [".pec1", ".pec2", "PEC2"],
            importFingerprint: nil,
            entryPointBytes: nil
        ),
        PackerSignature(
            name: "Petite",
            sectionNames: [".petite"],
            importFingerprint: nil,
            entryPointBytes: nil
        ),
        PackerSignature(
            name: "MPRESS",
            sectionNames: [".MPRESS1", ".MPRESS2"],
            importFingerprint: nil,
            entryPointBytes: nil
        ),
        PackerSignature(
            name: "Enigma Protector",
            sectionNames: [".enigma1", ".enigma2"],
            importFingerprint: nil,
            entryPointBytes: nil
        ),
    ]

    func detect(binary: BinaryFile) -> [PackerResult] {
        guard binary.format == .pe else { return [] }
        var results: [PackerResult] = []

        let sectionNames = Set(binary.sections.map { $0.name })
        let importNames = binary.symbols.filter { $0.binding == .external }.map { $0.name }

        for sig in signatures {
            var confidence = 0.0
            var details: [String] = []

            // Check section names
            let matchedSections = sig.sectionNames.filter { sectionNames.contains($0) }
            if !matchedSections.isEmpty {
                confidence += 0.7
                details.append("Matching sections: \(matchedSections.joined(separator: ", "))")
            }

            // Check import fingerprint
            if let impFp = sig.importFingerprint {
                let matchedImports = impFp.filter { expected in
                    importNames.contains(where: { $0.localizedCaseInsensitiveContains(expected) })
                }
                if matchedImports.count == impFp.count && importNames.count <= 5 {
                    confidence += 0.2
                    details.append("Import fingerprint match: \(matchedImports.joined(separator: ", "))")
                }
            }

            if confidence > 0 {
                results.append(PackerResult(
                    name: sig.name,
                    confidence: min(confidence, 1.0),
                    details: details.joined(separator: "; ")
                ))
            }
        }

        // Check for overlay data
        if let overlayResult = detectOverlay(binary: binary) {
            results.append(overlayResult)
        }

        return results
    }

    private func detectOverlay(binary: BinaryFile) -> PackerResult? {
        guard !binary.sections.isEmpty else { return nil }

        // Find the end of the last section's raw data
        var lastRawEnd: Int = 0
        for section in binary.sections {
            let end = Int(section.offset) + Int(section.size)
            if end > lastRawEnd {
                lastRawEnd = end
            }
        }

        let overlaySize = binary.data.count - lastRawEnd
        if overlaySize > 512 {
            return PackerResult(
                name: "Overlay Data",
                confidence: 0.5,
                details: "Found \(overlaySize) bytes of data after the last section. May contain appended payload or packer data."
            )
        }
        return nil
    }
}
