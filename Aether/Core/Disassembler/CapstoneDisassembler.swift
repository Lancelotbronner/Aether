//
//  CapstoneDisassembler.swift
//  Aether
//
//  Created by Christophe Bronner on 2026-06-04.
//

import capstone
import CapstoneKit
import Foundation

nonisolated struct CapstoneDisassembler: DisassemblerPlugin, ~Copyable {
	let capstone: Capstone
	let arch: CapstoneArch
	var mode: CapstoneMode

	init?(for binary: BinaryFile) throws {
		guard let arch = binary.architecture.capstoneArch else { return nil }
		self.arch = arch
		self.mode = binary.architecture.capstoneMode
		capstone = try Capstone(arch: arch, mode: binary.architecture.capstoneMode)
		capstone.withDetailedInstructions(true)
	}

	init(_ arch: CapstoneArch, mode: CapstoneMode) throws {
		self.arch = arch
		self.mode = mode
		capstone = try Capstone(arch: arch, mode: mode)
		capstone.withDetailedInstructions(true)
	}

	mutating func disassemble(_ context: any DisassemblyContext) throws {
		while !context.bytes.isEmpty {
			defer { context.submit() }
			let disasmBox = try capstone.preprocess(context)
			let disasm = disasmBox.pointee

			var read = InlineArray<64, UInt16>(repeating: 0)
			var write = InlineArray<64, UInt16>(repeating: 0)
			var readp = read.mutableSpan
			var writep = write.mutableSpan
			try capstone.access(regsOf: disasm, read: &readp, write: &writep)
			context.instruction.readCount = disasm.detail.regs_read_count
			context.instruction.modifiedCount = disasm.detail.regs_write_count
			context.instruction.read = unsafeBitCast(disasm.detail.regs_read, to: DisassemblyInstruction.RegistersR.self)
			context.instruction.modified = unsafeBitCast(disasm.detail.regs_write, to: DisassemblyInstruction.RegistersW.self)

			// universal disassembly

			if capstone.instruction(disasm, in: .ret) || capstone.instruction(disasm, in: .iret) {
				context.instruction.kind = .ret
			}

			// arch-specific disassembly

			switch arch {
			case .aarch64:
				try disassemble(aarch64: disasm, in: context)
			case .x86:
				try disassemble(x86: disasm, in: context)
			default:
				break
			}
		}
	}

	private func disassemble(aarch64 disasm: CapstoneInstruction, in context: any DisassemblyContext) throws {
		let id = AArch64.InstructionId(rawValue: disasm.id)
		let operands = unsafeBitCast(disasm.detail.aarch64.operands, to: InlineArray<16, AArch64.Operand>.self)
		let lastOp = operands[max(0, Int(disasm.detail.aarch64.op_count)-1)]

	operands:
		for i in 0..<Int(disasm.detail.aarch64.op_count) {
			let cs = operands[i]
			var op: DisassemblyOperand {
				get { context.instruction.operands[i] }
				_modify { yield &context.instruction.operands[i] }
			}

			op.access = cs.access.toAether

			switch cs.type {
			case .AARCH64_OP_INVALID:
				break operands
			case .AARCH64_OP_REG:
				op.kind = .register(RegisterIndex(cs.reg))
			case .AARCH64_OP_IMM:
				op.kind = .constant(UInt64(bitPattern: cs.imm), [])
			case .AARCH64_OP_MEM, .AARCH64_OP_MEM_REG, .AARCH64_OP_MEM_IMM:
				op.kind = .memory(base: RegisterIndex(cs.mem.base), index: RegisterIndex(cs.mem.index), scale: 1, displacement: Int64(cs.mem.disp))
			default:
				op.kind = .other
			}
		}

		if capstone.instruction(disasm, in: .jump) {
			context.instruction.kind = .branch(.jmp, UInt64(bitPattern: lastOp.imm))
		}
		if capstone.instruction(disasm, in: .call) {
			context.instruction.kind = .call(UInt64(bitPattern: lastOp.imm))
		}

		switch id {
			//TODO: associate branching instructions
		default:
			break
		}
	}

	private func disassemble(x86 disasm: CapstoneInstruction, in context: any DisassemblyContext) throws {
		let id = X86.InstructionId(rawValue: disasm.id)
		let operands = unsafeBitCast(disasm.detail.x86.operands, to: InlineArray<8, X86.Operand>.self)

		let lastOpIndex = max(0, min(7, Int(disasm.detail.x86.op_count) - 1))
		let lastOp = operands[lastOpIndex]
		let targetBranch = UInt64(bitPattern: lastOp.imm)

	operands:
		for i in 0..<Int(disasm.detail.x86.op_count) {
			let cs = operands[i]
			var op: DisassemblyOperand {
				get { context.instruction.operands[i] }
				_modify { yield &context.instruction.operands[i] }
			}

			op.access = cs.access.toAether

			switch cs.type {
			case .invalid:
				break operands
			case .reg:
				op.kind = .register(RegisterIndex(cs.reg))
			case .imm:
				op.kind = .constant(UInt64(bitPattern: cs.imm), [])
			case .mem:
				op.kind = .memory(base: RegisterIndex(cs.mem.base), index: RegisterIndex(cs.mem.index), scale: 1, displacement: Int64(cs.mem.disp))
			}
		}

		if capstone.instruction(disasm, in: .jump) {
			context.instruction.kind = .branch(.jmp, targetBranch)
		}
		if capstone.instruction(disasm, in: .call) {
			context.instruction.kind = .call(targetBranch)
		}
		if let branch = id?.conditionalJump {
			context.instruction.kind = .branch(branch, targetBranch)
		}

		switch id {
		default:
			break
		}
	}
}

nonisolated extension Capstone {
	func preprocess(_ context: any DisassemblyContext) throws(CapstoneError) -> CapstoneInstructionBox {
		var tmp = context.bytes.span
		let disasm = try disassemble(&tmp, at: &context.nextAddress)
		context.bytes = context.bytes.dropFirst(context.bytes.count - tmp.count)

		context.instruction.assembly.mnemonic = withUnsafeBytes(of: disasm.pointee.mnemonic) {
			String(cString: $0.assumingMemoryBound(to: CChar.self).baseAddress!)
		}
		context.instruction.assembly.operands = withUnsafeBytes(of: disasm.pointee.op_str) {
			String(cString: $0.assumingMemoryBound(to: CChar.self).baseAddress!)
		}
//		result.instruction.length = UInt8(disasm.size)
		context.instruction.pcRegisterValue = disasm.pointee.address

		if disasm.pointee.illegal {
			context.instruction.flags.insert(.illegal)
		}

		guard disasm.pointee.unsafeMutableDetailPointer != nil else {
			throw CapstoneError.CS_ERR_DETAIL
		}

		return disasm
	}
}

nonisolated extension Architecture {
	var capstoneArch: CapstoneArch? {
		switch self {
		case .appleSilicon: .aarch64
		case .x86_64: .x86
		case .arm64: .aarch64
		case .arm64e: .aarch64
		case .i386: .x86
		case .armv7: .arm
		case .jvm: nil
		case .unknown: nil
		}
	}

	var capstoneMode: CapstoneMode {
		switch self {
		case .appleSilicon: [.CS_MODE_APPLE_PROPRIETARY]
		case .x86_64: [.CS_MODE_64]
		case .arm64: []
		case .arm64e: [.CS_MODE_V8]
		case .i386: [.CS_MODE_32]
		case .armv7: []
		case .jvm: []
		case .unknown: []
		}
	}
}

nonisolated extension AccessSet {
	var toAether: OperandAccess {
		var tmp: OperandAccess = []
		if contains(.read) { tmp.insert(.read) }
		if contains(.write) { tmp.insert(.write) }
		return tmp
	}
}
