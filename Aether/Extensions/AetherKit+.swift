import AetherKit
import SwiftUI

extension BinaryFormat {
	var title: LocalizedStringKey {
		switch self {
		case .unknown: "Unknown"
		case .machO: "Mach-O"
		case .elf: "ELF"
		case .pe: "PE"
		case .java: "Java"
		}
	}
}

extension Architecture {
	var title: LocalizedStringKey {
		switch self {
		case .unknown: "Unknown"
		case .x86_64: "x86-64"
		case .appleSilicon: "Apple Silicon"
		case .arm64: "Arm64"
		case .arm64e: "Arm64e"
		case .i386: "i386"
		case .armv7: "ARMv7"
		case .jvm: "JVM"
		}
	}
}
