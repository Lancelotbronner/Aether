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
	targets: [
		.target(
			name: "AetherKit"
		),
	],
	swiftLanguageModes: [.v6]
)
