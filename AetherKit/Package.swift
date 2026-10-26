// swift-tools-version: 6.3

import PackageDescription

let package = Package(
	name: "AetherKit",
	platforms: [
		.macOS(.v26),
	],
	products: [
		.library(name: "AetherKit", targets: ["AetherKit"]),
	],
	targets: [
		.target(name: "AetherKit", swiftSettings: [
			.enableExperimentalFeature("Lifetimes"),
		]),
		.testTarget(name: "AetherTests", dependencies: ["AetherKit"]),
	],
	swiftLanguageModes: [.v6]
)
