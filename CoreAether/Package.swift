// swift-tools-version: 6.4

import PackageDescription

let package = Package(
	name: "CoreAether",
	products: [
		.library(name: "CoreAether", targets: ["CoreAether"]),
	],
	targets: [
		.target(
			name: "CoreAether",
		),
	],
	swiftLanguageModes: [.v6],
	cLanguageStandard: .c2x
)
