import Foundation
import AetherKit

/// A single disassembled instruction in the app's in-memory pipeline
/// (Task 12c: replaces the legacy `Models/Instruction.swift` `Instruction`).
///
/// Produced by the disassembly pipeline (`AetherDisassemblyContext.submit()`
/// and `DisassemblerEngine.disassembleJVM`), cached by `AppState`, and
/// consumed by the Decompiler, the disassembly/branch views, and the
/// Inspector. Bytes are never stored: vaddr → bytes goes through the
/// bounds-guarded `BinaryModel.data(in:)` (vaddr − baseAddress).
nonisolated struct DisassembledInstruction: Identifiable {
	var addressRange: Range<UInt64>
	var address: UInt64 { addressRange.lowerBound }
	var size: Int { addressRange.count }
	let mnemonic: String
	let operands: String
	let architecture: Architecture
	/// Offset of the start of this instruction in the pseudo-instruction list.
	var pcode: Range<Int>

	var id: UInt64 { addressRange.lowerBound }

	// Analysis metadata
	var comment: String?

	// Instruction classification
	let kind: InstructionKind
	var type: InstructionCategory { kind.type }
	var branchTarget: UInt64? { kind.branchTarget }

	init(_ result: DisassemblyInstruction, with bytes: Range<UInt64>, at address: UInt64, for arch: Architecture, pcode: Range<Int> = 0..<0) {
		addressRange = address..<(address + UInt64(bytes.count))
		mnemonic = result.assembly.mnemonic
		operands = result.assembly.operands
		architecture = arch
		kind = result.kind
		self.pcode = pcode
	}

	/// Full instruction string
	var text: String {
		if operands.isEmpty {
			return mnemonic
		}
		return "\(mnemonic) \(operands)"
	}

	/// Is this a control flow instruction?
	var isControlFlow: Bool {
		kind.isControlFlow
	}

	/// Is this a branch instruction?
	var isBranch: Bool {
		kind.isBranch
	}

	/// Does this instruction end a basic block?
	var endsBasicBlock: Bool {
		kind.isEndOfBlock
	}

	static func == (lhs: DisassembledInstruction, rhs: DisassembledInstruction) -> Bool {
		lhs.address == rhs.address
	}

	func hash(into hasher: inout Hasher) {
		hasher.combine(address)
	}
}

/// Classification of instruction types (Task 12c: renamed from the legacy
/// `InstructionType`; the dead `color: String` property was dropped).
nonisolated enum InstructionCategory: String, Codable {
	case move = "Move"
	case arithmetic = "Arithmetic"
	case logic = "Logic"
	case compare = "Compare"
	case jump = "Jump"
	case conditionalJump = "Conditional Jump"
	case call = "Call"
	case `return` = "Return"
	case push = "Push"
	case pop = "Pop"
	case load = "Load"
	case store = "Store"
	case nop = "NOP"
	case interrupt = "Interrupt"
	case syscall = "Syscall"
	case other = "Other"
}
