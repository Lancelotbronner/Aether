import Foundation

struct IoCReport: Identifiable {
    let id = UUID()
    let urls: [String]
    let ipAddresses: [String]
    let domains: [String]
    let emails: [String]
    let filePaths: [String]
    let registryKeys: [String]
    let cryptoWallets: [String]
    let mutexes: [String]

    var totalCount: Int {
        urls.count + ipAddresses.count + domains.count + emails.count +
        filePaths.count + registryKeys.count + cryptoWallets.count + mutexes.count
    }

    var isEmpty: Bool { totalCount == 0 }
}

class IoCExtractor {
    func extract(from binary: BinaryFile) -> IoCReport {
        // Collect all printable strings from sections
        var allStrings: [String] = []
        for section in binary.sections {
            allStrings.append(contentsOf: extractPrintableStrings(from: section.data))
        }

        return IoCReport(
            urls: extractURLs(from: allStrings),
            ipAddresses: extractIPv4(from: allStrings),
            domains: extractDomains(from: allStrings),
            emails: extractEmails(from: allStrings),
            filePaths: extractFilePaths(from: allStrings),
            registryKeys: extractRegistryKeys(from: allStrings),
            cryptoWallets: extractCryptoWallets(from: allStrings),
            mutexes: extractMutexes(from: allStrings)
        )
    }

    private func extractPrintableStrings(from data: Data) -> [String] {
        var strings: [String] = []
        var current: [UInt8] = []

        for i in 0..<data.count {
            let byte = data[data.startIndex + i]
            if byte >= 0x20 && byte <= 0x7E {
                current.append(byte)
            } else {
                if current.count >= 6, let str = String(bytes: current, encoding: .utf8) {
                    strings.append(str)
                }
                current.removeAll()
            }
        }
        if current.count >= 6, let str = String(bytes: current, encoding: .utf8) {
            strings.append(str)
        }
        return strings
    }

    private func extractURLs(from strings: [String]) -> [String] {
        let pattern = #"https?://[a-zA-Z0-9\-._~:/?#\[\]@!$&'()*+,;=%]+"#
        return matchPattern(pattern, in: strings)
    }

    private func extractIPv4(from strings: [String]) -> [String] {
        let pattern = #"\b(?:(?:25[0-5]|2[0-4]\d|[01]?\d\d?)\.){3}(?:25[0-5]|2[0-4]\d|[01]?\d\d?)\b"#
        return matchPattern(pattern, in: strings).filter { ip in
            // Filter out common false positives
            !ip.hasPrefix("0.0.") && !ip.hasPrefix("255.255.") && ip != "127.0.0.1"
        }
    }

    private func extractDomains(from strings: [String]) -> [String] {
        let pattern = #"\b[a-zA-Z0-9](?:[a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z]{2,})+\b"#
        let results = matchPattern(pattern, in: strings)
        // Filter out common non-suspicious domains
        let safe = Set(["microsoft.com", "windows.com", "apple.com", "google.com", "github.com"])
        return results.filter { !safe.contains($0.lowercased()) }
    }

    private func extractEmails(from strings: [String]) -> [String] {
        let pattern = #"\b[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}\b"#
        return matchPattern(pattern, in: strings)
    }

    private func extractFilePaths(from strings: [String]) -> [String] {
        let windowsPattern = #"[A-Z]:\\(?:[^\\\/:*?"<>|\r\n]+\\)*[^\\\/:*?"<>|\r\n]*"#
        let unixPattern = #"/(?:usr|etc|tmp|var|home|opt|bin|sbin|dev|proc)/[^\s\x00]+"#
        return matchPattern(windowsPattern, in: strings) + matchPattern(unixPattern, in: strings)
    }

    private func extractRegistryKeys(from strings: [String]) -> [String] {
        let pattern = #"HKEY_(?:LOCAL_MACHINE|CURRENT_USER|CLASSES_ROOT|USERS|CURRENT_CONFIG)\\[^\s\x00]+"#
        return matchPattern(pattern, in: strings)
    }

    private func extractCryptoWallets(from strings: [String]) -> [String] {
        let btcPattern = #"\b[13][a-km-zA-HJ-NP-Z1-9]{25,34}\b"#
        let ethPattern = #"\b0x[0-9a-fA-F]{40}\b"#
        return matchPattern(btcPattern, in: strings) + matchPattern(ethPattern, in: strings)
    }

    private func extractMutexes(from strings: [String]) -> [String] {
        let pattern = #"(?:Global\\|Local\\)[^\s\x00]+"#
        return matchPattern(pattern, in: strings)
    }

    private func matchPattern(_ pattern: String, in strings: [String]) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        var results = Set<String>()

        for str in strings {
            let range = NSRange(str.startIndex..., in: str)
            let matches = regex.matches(in: str, range: range)
            for match in matches {
                if let matchRange = Range(match.range, in: str) {
                    results.insert(String(str[matchRange]))
                }
            }
        }

        return Array(results).sorted()
    }
}
