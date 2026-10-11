import Foundation
import AetherKit
import capstone

nonisolated final class AetherDisassemblyContext: DisassemblyContext {
	let architecture: Architecture
	let baseAddress: UInt64
	let code: Data
	private var currentAddress: UInt64
	var nextAddress: UInt64
	var mode = CpuMode(rawValue: 0)
	var remainingByteRange: Range<Int>
	var lastInstructionByteRange: Range<Int>
	var instruction = DisassemblyInstruction()
	var xrefsTo: [UInt64] = []
	var xrefsFrom: [UInt64] = []
	var submitted: [Instruction] = []
	/// Pseudo-instructions.
	var pcode: [Pcode] = []
	var pcodeIndex = 0

	init(for data: Data, at address: UInt64, for architecture: Architecture) {
		self.code = data
		baseAddress = address
		currentAddress = address
		nextAddress = address
		remainingByteRange = data.indices
		lastInstructionByteRange = data.indices.prefix(0)
		submitted.reserveCapacity(data.count)
		self.architecture = architecture
	}

	func submit() {
		let bytes = UInt64(lastInstructionByteRange.lowerBound)..<UInt64(remainingByteRange.lowerBound)
		let next = Instruction(instruction, with: bytes, at: currentAddress, for: architecture, pcode: pcodeIndex..<pcode.count)
		submitted.append(next)

		//TODO: register xrefs

		xrefsTo.removeAll(keepingCapacity: true)
		xrefsFrom.removeAll(keepingCapacity: true)
		instruction = DisassemblyInstruction()
		lastInstructionByteRange = remainingByteRange
		currentAddress = nextAddress
		pcodeIndex = pcode.count
	}

	func submit(_ instr: Pcode) {
		pcode.append(instr)
	}

	func xref(to address: UInt64) {
		xrefsTo.append(address)
	}

	func xref(from address: UInt64) {
		xrefsFrom.append(address)
	}
}

struct DisassemblyResult {
	var instructions: [Instruction]
	var pcode: [Pcode]
}

actor DisassemblerEngine {
	static var capstone: [CapstoneArch: Rc<CapstoneDisassembler>] = [:]

	/// Disassemble binary data
	func disassemble(
		data: Data,
		address: UInt64,
		architecture: Architecture
	) -> DisassemblyResult {
		if let arch = architecture.capstoneArch {
			if !Self.capstone.keys.contains(arch) {
				Self.capstone[arch] = Rc(try! CapstoneDisassembler(arch, mode: architecture.capstoneMode))
			}
			let capstone = Self.capstone[arch]!
			let context = AetherDisassemblyContext(for: data, at: address, for: architecture)
			do {
				try capstone.wrappedValue.disassemble(context)
			} catch {
				context.instruction.assembly.mnemonic = "error"
				context.instruction.assembly.operands = String(describing: error)
			}
			return DisassemblyResult(instructions: context.submitted, pcode: context.pcode)
		}
		let instructions: [Instruction]
		switch architecture {
		case .jvm:
			instructions = disassembleJVM(data: data, address: address)
		default:
			instructions = []
		}
		return DisassemblyResult(instructions: instructions, pcode: [])
	}
}
