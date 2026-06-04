import Foundation

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

class PEAnomalyDetector {
    private let entropyAnalyzer = EntropyAnalyzer()

    private let suspiciousSectionNames: Set<String> = [
        ".UPX0", ".UPX1", ".UPX2",
        ".vmp0", ".vmp1", ".vmp2",
        ".themida", ".Themida",
        ".aspack", ".adata",
        ".nsp0", ".nsp1",
        ".enigma1", ".enigma2",
        ".petite",
        ".yP", ".y0da",
        ".perplex",
        ".packed"
    ]

    func analyze(binary: BinaryFile) -> [PEAnomaly] {
        guard binary.format == .pe else { return [] }
        var anomalies: [PEAnomaly] = []

        anomalies.append(contentsOf: checkSectionNames(binary: binary))
        anomalies.append(contentsOf: checkSectionEntropy(binary: binary))
        anomalies.append(contentsOf: checkSizeMismatch(binary: binary))
        anomalies.append(contentsOf: checkEntryPoint(binary: binary))
        anomalies.append(contentsOf: checkImportTable(binary: binary))
        anomalies.append(contentsOf: checkTLSCallbacks(binary: binary))
        anomalies.append(contentsOf: checkResourceSize(binary: binary))

        return anomalies
    }

    private func checkSectionNames(binary: BinaryFile) -> [PEAnomaly] {
        var anomalies: [PEAnomaly] = []
        for section in binary.sections {
            if suspiciousSectionNames.contains(section.name) {
                anomalies.append(PEAnomaly(
                    title: "Suspicious section name: \(section.name)",
                    description: "Section '\(section.name)' is commonly associated with packers/protectors.",
                    severity: .high
                ))
            }
            // Check for non-printable section names
            if section.name.unicodeScalars.contains(where: { !$0.properties.isPatternSyntax && ($0.value < 0x20 || $0.value > 0x7E) && $0.value != 0 }) {
                anomalies.append(PEAnomaly(
                    title: "Non-printable section name",
                    description: "Section has non-printable characters in its name, which is unusual.",
                    severity: .medium
                ))
            }
        }
        return anomalies
    }

    private func checkSectionEntropy(binary: BinaryFile) -> [PEAnomaly] {
        var anomalies: [PEAnomaly] = []
        for section in binary.sections {
            guard !section.data.isEmpty else { continue }
            let entropy = entropyAnalyzer.shannonEntropy(section.data)

            if section.containsCode && entropy > 7.0 {
                anomalies.append(PEAnomaly(
                    title: "High entropy in code section '\(section.name)'",
                    description: String(format: "Entropy: %.2f (normal code: ~6.0-6.5). Suggests packing or encryption.", entropy),
                    severity: .high
                ))
            } else if !section.containsCode && entropy > 7.5 {
                anomalies.append(PEAnomaly(
                    title: "Very high entropy in '\(section.name)'",
                    description: String(format: "Entropy: %.2f. Likely encrypted or compressed data.", entropy),
                    severity: .medium
                ))
            }
        }
        return anomalies
    }

    private func checkSizeMismatch(binary: BinaryFile) -> [PEAnomaly] {
        var anomalies: [PEAnomaly] = []
        for section in binary.sections {
            let virtualSize = section.size
            let rawSize = UInt64(section.data.count)
            if virtualSize > rawSize * 10 && rawSize > 0 && virtualSize > 0x1000 {
                anomalies.append(PEAnomaly(
                    title: "Size mismatch in '\(section.name)'",
                    description: "VirtualSize (\(virtualSize)) >> RawDataSize (\(rawSize)). Typical of unpacking stubs.",
                    severity: .high
                ))
            }
        }
        return anomalies
    }

    private func checkEntryPoint(binary: BinaryFile) -> [PEAnomaly] {
        var anomalies: [PEAnomaly] = []
        let ep = binary.entryPoint

        let textSection = binary.sections.first { $0.name == ".text" }
        if let text = textSection {
            if !text.contains(address: ep) {
                // Entry point outside .text
                if let epSection = binary.sections.first(where: { $0.contains(address: ep) }) {
                    anomalies.append(PEAnomaly(
                        title: "Entry point outside .text",
                        description: "Entry point (0x\(String(ep, radix: 16))) is in '\(epSection.name)' instead of .text.",
                        severity: .high
                    ))
                    // Check if the section is writable
                    if let seg = binary.segments.first(where: { $0.name == epSection.name }), seg.isWritable {
                        anomalies.append(PEAnomaly(
                            title: "Entry point in writable section",
                            description: "Entry point is in a writable section, which is suspicious.",
                            severity: .critical
                        ))
                    }
                } else {
                    anomalies.append(PEAnomaly(
                        title: "Entry point outside all sections",
                        description: "Entry point (0x\(String(ep, radix: 16))) does not belong to any section.",
                        severity: .critical
                    ))
                }
            }
        }
        return anomalies
    }

    private func checkImportTable(binary: BinaryFile) -> [PEAnomaly] {
        let imports = binary.symbols.filter { $0.binding == .external }
        if imports.isEmpty {
            return [PEAnomaly(
                title: "No import table",
                description: "Binary has no imports. APIs may be resolved dynamically at runtime (common in malware/packers).",
                severity: .high
            )]
        }

        // Check for very few imports (typical of packed binaries)
        if imports.count <= 3 {
            let importNames = imports.map { $0.name.lowercased() }
            let packerImports = ["loadlibrarya", "getprocaddress", "virtualprotect", "loadlibraryw"]
            let matchCount = importNames.filter { name in
                packerImports.contains(where: { name.contains($0) })
            }.count
            if matchCount >= 2 {
                return [PEAnomaly(
                    title: "Minimal import table (packer signature)",
                    description: "Only \(imports.count) imports, including LoadLibrary/GetProcAddress. Typical of packed binaries.",
                    severity: .high
                )]
            }
        }
        return []
    }

    private func checkTLSCallbacks(binary: BinaryFile) -> [PEAnomaly] {
        // Check for TLS directory presence by looking at data
        // TLS callbacks execute before main() and are used by anti-debug techniques
        let data = binary.data
        guard data.count > 0x3C + 4 else { return [] }
        guard let peOffset = data.readUInt32LE(at: 0x3C),
              Int(peOffset) + 4 <= data.count else { return [] }

        let coffOffset = Int(peOffset) + 4
        guard coffOffset + 20 <= data.count,
              let optHeaderSize = data.readUInt16LE(at: coffOffset + 16) else { return [] }

        let optHeaderOffset = coffOffset + 20
        guard let magic = data.readUInt16LE(at: optHeaderOffset) else { return [] }
        let is64 = magic == 0x20B

        let ddOffset = is64 ? optHeaderOffset + 112 : optHeaderOffset + 96
        guard let nrva = data.readUInt32LE(at: is64 ? optHeaderOffset + 108 : optHeaderOffset + 92),
              nrva > 9 else { return [] }

        // TLS is data directory index 9
        let tlsOffset = ddOffset + 9 * 8
        guard tlsOffset + 8 <= data.count,
              let tlsVA = data.readUInt32LE(at: tlsOffset),
              let tlsSize = data.readUInt32LE(at: tlsOffset + 4) else { return [] }

        if tlsVA > 0 && tlsSize > 0 {
            return [PEAnomaly(
                title: "TLS callbacks present",
                description: "TLS directory found. TLS callbacks execute before main() and are commonly used for anti-debugging.",
                severity: .medium
            )]
        }
        return []
    }

    private func checkResourceSize(binary: BinaryFile) -> [PEAnomaly] {
        let rsrc = binary.sections.first { $0.name == ".rsrc" }
        let text = binary.sections.first { $0.name == ".text" }

        if let r = rsrc, let t = text, r.size > t.size * 3 && r.size > 0x10000 {
            return [PEAnomaly(
                title: "Large resource section",
                description: "Resource section (\(r.size) bytes) is much larger than code section (\(t.size) bytes). May contain embedded payloads.",
                severity: .medium
            )]
        }
        return []
    }
}
