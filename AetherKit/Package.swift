// swift-tools-version: 6.4

import PackageDescription

let package = Package(
	name: "AetherKit",
	platforms: [
		.macOS(.v27),
	],
	products: [
		.library(name: "AetherKit", targets: ["AetherKit"]),
	],
	dependencies: [
		.package(url: "https://github.com/tomasf/Zip.git", from: "2.1.1"),
	],
	targets: [
		.target(name: "CoreAether"),
		.testTarget(name: "CoreAetherTests", dependencies: ["CoreAether"]),

		.target(name: "AetherKit", dependencies: [
			.product(name: "Zip", package: "Zip"),
			"CoreAether",
		], swiftSettings: [
			.enableExperimentalFeature("Lifetimes"),
		]),
		.testTarget(name: "AetherTests", dependencies: ["AetherKit"]),
	],
	swiftLanguageModes: [.v6],
	cLanguageStandard: .c2x,
)
