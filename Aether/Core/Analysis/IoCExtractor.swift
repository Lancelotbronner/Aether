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
