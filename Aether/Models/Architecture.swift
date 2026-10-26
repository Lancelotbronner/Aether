import Foundation
import AetherKit

extension Architecture {
	/// Instruction alignment in bytes
	var instructionAlignment: Int {
		switch self {
		case .x86_64, .i386:
			return 1  // Variable length instructions
		case .appleSilicon:
			return 4
		case .arm64, .arm64e:
			return 4  // Fixed 4-byte instructions
		case .armv7:
			return 2  // Thumb mode can be 2 or 4 bytes
		case .jvm:
			return 1  // Variable length bytecode
		case .unknown:
			return 1
		}
	}

	/// Pointer size in bytes
	var pointerSize: Int {
		switch self {
		case .x86_64, .arm64, .arm64e, .appleSilicon:
			return 8
		case .i386, .armv7:
			return 4
		case .jvm:
			return 4  // JVM references are 32-bit (compressed oops)
		case .unknown:
			return 8
		}
	}

	/// Stack pointer register name
	var stackPointerName: String {
		switch self {
		case .x86_64:
			return "rsp"
		case .i386:
			return "esp"
		case .arm64, .arm64e, .appleSilicon:
			return "sp"
		case .armv7:
			return "sp"
		case .jvm:
			return "stack"
		case .unknown:
			return "sp"
		}
	}

	/// Frame pointer register name
	var framePointerName: String {
		switch self {
		case .x86_64:
			return "rbp"
		case .i386:
			return "ebp"
		case .arm64, .arm64e, .appleSilicon:
			return "x29"
		case .armv7:
			return "r11"
		case .jvm:
			return "locals"
		case .unknown:
			return "fp"
		}
	}

	/// Return address register/location
	var returnAddressLocation: String {
		switch self {
		case .x86_64, .i386:
			return "[stack]"
		case .arm64, .arm64e, .appleSilicon:
			return "x30"
		case .armv7:
			return "lr"
		case .jvm:
			return "[jvm_stack]"
		case .unknown:
			return "unknown"
		}
	}

	/// Is this a 64-bit architecture?
	var is64Bit: Bool {
		switch self {
		case .x86_64, .arm64, .arm64e, .appleSilicon:
			return true
		case .i386, .armv7, .jvm, .unknown:
			return false
		}
	}

	/// General purpose registers
	var generalPurposeRegisters: [String] {
		switch self {
		case .x86_64:
			return ["rax", "rbx", "rcx", "rdx", "rsi", "rdi", "rbp", "rsp",
					"r8", "r9", "r10", "r11", "r12", "r13", "r14", "r15"]
		case .i386:
			return ["eax", "ebx", "ecx", "edx", "esi", "edi", "ebp", "esp"]
		case .arm64, .arm64e, .appleSilicon:
			return (0...30).map { "x\($0)" } + ["sp"]
		case .armv7:
			return (0...15).map { "r\($0)" }
		case .jvm:
			return ["stack", "locals"]  // JVM is stack-based
		case .unknown:
			return []
		}
	}

	/// Calling convention argument registers
	var argumentRegisters: [String] {
		switch self {
		case .x86_64:
			return ["rdi", "rsi", "rdx", "rcx", "r8", "r9"]  // System V AMD64 ABI
		case .i386:
			return []  // Arguments on stack
		case .arm64, .arm64e, .appleSilicon:
			return ["x0", "x1", "x2", "x3", "x4", "x5", "x6", "x7"]
		case .armv7:
			return ["r0", "r1", "r2", "r3"]
		case .jvm:
			return []  // Arguments passed via locals
		case .unknown:
			return []
		}
	}

	/// Return value register
	var returnValueRegister: String {
		switch self {
		case .x86_64:
			return "rax"
		case .i386:
			return "eax"
		case .arm64, .arm64e, .appleSilicon:
			return "x0"
		case .armv7:
			return "r0"
		case .jvm:
			return "stack[0]"
		case .unknown:
			return "unknown"
		}
	}
}
