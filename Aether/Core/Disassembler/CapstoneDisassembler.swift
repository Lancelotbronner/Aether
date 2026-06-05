//
//  CapstoneDisassembler.swift
//  Aether
//
//  Created by Christophe Bronner on 2026-06-04.
//

import capstone
import CapstoneKit
import Foundation

nonisolated struct CapstoneDisassembler2: DisassemblerPlugin, ~Copyable {
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
			let disasm = try capstone.preprocess(context)

			var read = InlineArray<64, UInt16>(repeating: 0)
			var write = InlineArray<64, UInt16>(repeating: 0)
			var readp = read.mutableSpan
			var writep = write.mutableSpan
			try capstone.access(regsOf: disasm, read: &readp, write: &writep)
			context.instruction.readCount = disasm.detail.regs_read_count
			context.instruction.modifiedCount = disasm.detail.regs_write_count
			context.instruction.read = unsafeBitCast(disasm.detail.regs_read, to: DisassemblyInstruction.RegistersR.self)
			context.instruction.modified = unsafeBitCast(disasm.detail.regs_write, to: DisassemblyInstruction.RegistersW.self)

			switch arch {
			case .aarch64:
				let id = AArch64.InstructionId(rawValue: disasm.id)
				let operands = unsafeBitCast(disasm.detail.aarch64.operands, to: InlineArray<16, AArch64.Operand>.self)
				let lastOp = operands[Int(disasm.detail.aarch64.op_count)-1]

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
				if capstone.instruction(disasm, in: .ret) || capstone.instruction(disasm, in: .iret) {
					context.instruction.kind = .ret
				}

				switch id {
					//TODO: associate branching instructions
				default:
					break
				}

			default:
				break
			}
		}
	}
}

nonisolated extension Capstone {
	func preprocess(_ context: any DisassemblyContext) throws(CapstoneError) -> CapstoneInstruction {
		var tmp = context.bytes.span
		let disasm = try disassemble(&tmp, at: &context.address)
		context.bytes = context.bytes.dropFirst(context.bytes.count - tmp.count)

		context.instruction.assembly.mnemonic = withUnsafeBytes(of: disasm.mnemonic) {
			String(cString: $0.assumingMemoryBound(to: CChar.self).baseAddress!)
		}
		context.instruction.assembly.operands = withUnsafeBytes(of: disasm.op_str) {
			String(cString: $0.assumingMemoryBound(to: CChar.self).baseAddress!)
		}
//		result.instruction.length = UInt8(disasm.size)
		context.instruction.pcRegisterValue = disasm.address

		if disasm.illegal {
			context.instruction.flags.insert(.illegal)
		}

		guard disasm.unsafeMutableDetailPointer != nil else {
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
		unsafeBitCast(self, to: OperandAccess.self)
	}
}
