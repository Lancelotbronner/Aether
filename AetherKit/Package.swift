// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
	name: "AetherKit",
	platforms: [
		.macOS(.v26),
	],
	products: [
		.library(name: "AetherKit", targets: [
			"AetherKit"
		]),
	],
	dependencies: [
		.package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.2.0"),
		.package(url: "https://github.com/Lancelotbronner/swift-case-accessors.git", from: "2.0.0"),
	],
	targets: [
		.target(
			name: "AetherKit"
		),
		.executableTarget(
			name: "sla2swift",
			dependencies: [
				.product(name: "ArgumentParser", package: "swift-argument-parser"),
				.product(name: "CaseAccessors", package: "swift-case-accessors"),
			]
		),
		.testTarget(
			name: "AetherTests",
			dependencies: ["AetherKit", "sla2swift"]
		),
	],
	swiftLanguageModes: [.v6]
)
