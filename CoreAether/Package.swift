// swift-tools-version: 6.4

import PackageDescription

let package = Package(
	name: "CoreAether",
	products: [
		.library(name: "CoreAether", targets: ["CoreAether", "CoreAetherKit"]),
	],
	targets: [
		.target(
			name: "CoreAether",
		),
		.target(
			name: "CoreAetherKit",
			dependencies: ["CoreAether"],
			swiftSettings: [
				.enableExperimentalFeature("Lifetimes"),
			]
		),
		.testTarget(name: "Tests", dependencies: ["CoreAetherKit"]),
	],
	swiftLanguageModes: [.v6],
	cLanguageStandard: .c2x
)
