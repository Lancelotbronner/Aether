import Foundation

public struct IoCReport: Identifiable {
	public let id = UUID()
	public let urls: [String]
	public let ipAddresses: [String]
	public let domains: [String]
	public let emails: [String]
	public let filePaths: [String]
	public let registryKeys: [String]
	public let cryptoWallets: [String]
	public let mutexes: [String]
}

public extension IoCReport {
	var totalCount: Int {
		urls.count + ipAddresses.count + domains.count + emails.count +
		filePaths.count + registryKeys.count + cryptoWallets.count + mutexes.count
	}

	var isEmpty: Bool { totalCount == 0 }
}
