// swift-tools-version: 6.4

import PackageDescription

let package = Package(
	name: "aether",
	platforms: [
		.macOS(.v27),
	],
	dependencies: [
		.package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.8.2"),
		.package(path: "../AetherKit"),
	],
	targets: [
		.executableTarget(
			name: "aether",
			dependencies: [
				.product(name: "ArgumentParser", package: "swift-argument-parser"),
				.product(name: "AetherKit", package: "AetherKit"),
			],
			swiftSettings: [
				.enableUpcomingFeature("ApproachableConcurrency"),
			],
		),

	]
)
