//
//  JavaDisassembler.swift
//  Aether
//
//  Created by Christophe Bronner on 2026-10-11.
//

import Foundation

extension DisassemblerEngine {
	func disassembleJVM(data: Data, address: UInt64) -> [Instruction] {
		var instructions: [Instruction] = []
		var offset = 0
		var currentAddress = address

		while offset < data.count {
			let opcode = data[offset]
			let (mnemonic, operandSize, operands, type, target) = decodeJVMInstruction(
				opcode: opcode,
				data: data,
				offset: offset,
				address: currentAddress
			)

			let size = 1 + operandSize
			let endOffset = min(offset + size, data.count)
			let byteOffsets = UInt64(offset)..<UInt64(endOffset)

			var result = DisassemblyInstruction()
			if let target {
				result.kind = .branch(.jmp, target)
			}
			let instruction = Instruction(
				result,
				with: byteOffsets, at: address, for: .jvm)
			//                Instruction(
			//					address: currentAddress,
			//                size: size,
			//                bytes: bytes,
			//                mnemonic: mnemonic,
			//                operands: operands,
			//                architecture: .jvm,
			//                type: type
			//            )

			instructions.append(instruction)
			offset += size
			currentAddress += UInt64(size)
		}

		return instructions
	}

	private func decodeJVMInstruction(opcode: UInt8, data: Data, offset: Int, address: UInt64) -> (String, Int, String, InstructionType, UInt64?) {
		switch opcode {
			// Constants
		case 0x00: return ("nop", 0, "", .nop, nil)
		case 0x01: return ("aconst_null", 0, "", .move, nil)
		case 0x02: return ("iconst_m1", 0, "", .move, nil)
		case 0x03: return ("iconst_0", 0, "", .move, nil)
		case 0x04: return ("iconst_1", 0, "", .move, nil)
		case 0x05: return ("iconst_2", 0, "", .move, nil)
		case 0x06: return ("iconst_3", 0, "", .move, nil)
		case 0x07: return ("iconst_4", 0, "", .move, nil)
		case 0x08: return ("iconst_5", 0, "", .move, nil)
		case 0x09: return ("lconst_0", 0, "", .move, nil)
		case 0x0A: return ("lconst_1", 0, "", .move, nil)
		case 0x0B: return ("fconst_0", 0, "", .move, nil)
		case 0x0C: return ("fconst_1", 0, "", .move, nil)
		case 0x0D: return ("fconst_2", 0, "", .move, nil)
		case 0x0E: return ("dconst_0", 0, "", .move, nil)
		case 0x0F: return ("dconst_1", 0, "", .move, nil)

			// Push byte/short
		case 0x10:
			let value = offset + 1 < data.count ? Int8(bitPattern: data[offset + 1]) : 0
			return ("bipush", 1, "\(value)", .push, nil)
		case 0x11:
			let value = offset + 2 < data.count ? Int16(bigEndian: Int16(data[offset + 1]) << 8 | Int16(data[offset + 2])) : 0
			return ("sipush", 2, "\(value)", .push, nil)

			// Load constant
		case 0x12:
			let index = offset + 1 < data.count ? data[offset + 1] : 0
			return ("ldc", 1, "#\(index)", .load, nil)
		case 0x13:
			let index = offset + 2 < data.count ? (UInt16(data[offset + 1]) << 8) | UInt16(data[offset + 2]) : 0
			return ("ldc_w", 2, "#\(index)", .load, nil)
		case 0x14:
			let index = offset + 2 < data.count ? (UInt16(data[offset + 1]) << 8) | UInt16(data[offset + 2]) : 0
			return ("ldc2_w", 2, "#\(index)", .load, nil)

			// Loads
		case 0x15:
			let index = offset + 1 < data.count ? data[offset + 1] : 0
			return ("iload", 1, "\(index)", .load, nil)
		case 0x16:
			let index = offset + 1 < data.count ? data[offset + 1] : 0
			return ("lload", 1, "\(index)", .load, nil)
		case 0x17:
			let index = offset + 1 < data.count ? data[offset + 1] : 0
			return ("fload", 1, "\(index)", .load, nil)
		case 0x18:
			let index = offset + 1 < data.count ? data[offset + 1] : 0
			return ("dload", 1, "\(index)", .load, nil)
		case 0x19:
			let index = offset + 1 < data.count ? data[offset + 1] : 0
			return ("aload", 1, "\(index)", .load, nil)

			// Quick loads (0-3)
		case 0x1A: return ("iload_0", 0, "", .load, nil)
		case 0x1B: return ("iload_1", 0, "", .load, nil)
		case 0x1C: return ("iload_2", 0, "", .load, nil)
		case 0x1D: return ("iload_3", 0, "", .load, nil)
		case 0x1E: return ("lload_0", 0, "", .load, nil)
		case 0x1F: return ("lload_1", 0, "", .load, nil)
		case 0x20: return ("lload_2", 0, "", .load, nil)
		case 0x21: return ("lload_3", 0, "", .load, nil)
		case 0x22: return ("fload_0", 0, "", .load, nil)
		case 0x23: return ("fload_1", 0, "", .load, nil)
		case 0x24: return ("fload_2", 0, "", .load, nil)
		case 0x25: return ("fload_3", 0, "", .load, nil)
		case 0x26: return ("dload_0", 0, "", .load, nil)
		case 0x27: return ("dload_1", 0, "", .load, nil)
		case 0x28: return ("dload_2", 0, "", .load, nil)
		case 0x29: return ("dload_3", 0, "", .load, nil)
		case 0x2A: return ("aload_0", 0, "", .load, nil)
		case 0x2B: return ("aload_1", 0, "", .load, nil)
		case 0x2C: return ("aload_2", 0, "", .load, nil)
		case 0x2D: return ("aload_3", 0, "", .load, nil)

			// Array loads
		case 0x2E: return ("iaload", 0, "", .load, nil)
		case 0x2F: return ("laload", 0, "", .load, nil)
		case 0x30: return ("faload", 0, "", .load, nil)
		case 0x31: return ("daload", 0, "", .load, nil)
		case 0x32: return ("aaload", 0, "", .load, nil)
		case 0x33: return ("baload", 0, "", .load, nil)
		case 0x34: return ("caload", 0, "", .load, nil)
		case 0x35: return ("saload", 0, "", .load, nil)

			// Stores
		case 0x36:
			let index = offset + 1 < data.count ? data[offset + 1] : 0
			return ("istore", 1, "\(index)", .store, nil)
		case 0x37:
			let index = offset + 1 < data.count ? data[offset + 1] : 0
			return ("lstore", 1, "\(index)", .store, nil)
		case 0x38:
			let index = offset + 1 < data.count ? data[offset + 1] : 0
			return ("fstore", 1, "\(index)", .store, nil)
		case 0x39:
			let index = offset + 1 < data.count ? data[offset + 1] : 0
			return ("dstore", 1, "\(index)", .store, nil)
		case 0x3A:
			let index = offset + 1 < data.count ? data[offset + 1] : 0
			return ("astore", 1, "\(index)", .store, nil)

			// Quick stores (0-3)
		case 0x3B: return ("istore_0", 0, "", .store, nil)
		case 0x3C: return ("istore_1", 0, "", .store, nil)
		case 0x3D: return ("istore_2", 0, "", .store, nil)
		case 0x3E: return ("istore_3", 0, "", .store, nil)
		case 0x3F: return ("lstore_0", 0, "", .store, nil)
		case 0x40: return ("lstore_1", 0, "", .store, nil)
		case 0x41: return ("lstore_2", 0, "", .store, nil)
		case 0x42: return ("lstore_3", 0, "", .store, nil)
		case 0x43: return ("fstore_0", 0, "", .store, nil)
		case 0x44: return ("fstore_1", 0, "", .store, nil)
		case 0x45: return ("fstore_2", 0, "", .store, nil)
		case 0x46: return ("fstore_3", 0, "", .store, nil)
		case 0x47: return ("dstore_0", 0, "", .store, nil)
		case 0x48: return ("dstore_1", 0, "", .store, nil)
		case 0x49: return ("dstore_2", 0, "", .store, nil)
		case 0x4A: return ("dstore_3", 0, "", .store, nil)
		case 0x4B: return ("astore_0", 0, "", .store, nil)
		case 0x4C: return ("astore_1", 0, "", .store, nil)
		case 0x4D: return ("astore_2", 0, "", .store, nil)
		case 0x4E: return ("astore_3", 0, "", .store, nil)

			// Array stores
		case 0x4F: return ("iastore", 0, "", .store, nil)
		case 0x50: return ("lastore", 0, "", .store, nil)
		case 0x51: return ("fastore", 0, "", .store, nil)
		case 0x52: return ("dastore", 0, "", .store, nil)
		case 0x53: return ("aastore", 0, "", .store, nil)
		case 0x54: return ("bastore", 0, "", .store, nil)
		case 0x55: return ("castore", 0, "", .store, nil)
		case 0x56: return ("sastore", 0, "", .store, nil)

			// Stack operations
		case 0x57: return ("pop", 0, "", .pop, nil)
		case 0x58: return ("pop2", 0, "", .pop, nil)
		case 0x59: return ("dup", 0, "", .push, nil)
		case 0x5A: return ("dup_x1", 0, "", .push, nil)
		case 0x5B: return ("dup_x2", 0, "", .push, nil)
		case 0x5C: return ("dup2", 0, "", .push, nil)
		case 0x5D: return ("dup2_x1", 0, "", .push, nil)
		case 0x5E: return ("dup2_x2", 0, "", .push, nil)
		case 0x5F: return ("swap", 0, "", .other, nil)

			// Arithmetic
		case 0x60: return ("iadd", 0, "", .arithmetic, nil)
		case 0x61: return ("ladd", 0, "", .arithmetic, nil)
		case 0x62: return ("fadd", 0, "", .arithmetic, nil)
		case 0x63: return ("dadd", 0, "", .arithmetic, nil)
		case 0x64: return ("isub", 0, "", .arithmetic, nil)
		case 0x65: return ("lsub", 0, "", .arithmetic, nil)
		case 0x66: return ("fsub", 0, "", .arithmetic, nil)
		case 0x67: return ("dsub", 0, "", .arithmetic, nil)
		case 0x68: return ("imul", 0, "", .arithmetic, nil)
		case 0x69: return ("lmul", 0, "", .arithmetic, nil)
		case 0x6A: return ("fmul", 0, "", .arithmetic, nil)
		case 0x6B: return ("dmul", 0, "", .arithmetic, nil)
		case 0x6C: return ("idiv", 0, "", .arithmetic, nil)
		case 0x6D: return ("ldiv", 0, "", .arithmetic, nil)
		case 0x6E: return ("fdiv", 0, "", .arithmetic, nil)
		case 0x6F: return ("ddiv", 0, "", .arithmetic, nil)
		case 0x70: return ("irem", 0, "", .arithmetic, nil)
		case 0x71: return ("lrem", 0, "", .arithmetic, nil)
		case 0x72: return ("frem", 0, "", .arithmetic, nil)
		case 0x73: return ("drem", 0, "", .arithmetic, nil)
		case 0x74: return ("ineg", 0, "", .arithmetic, nil)
		case 0x75: return ("lneg", 0, "", .arithmetic, nil)
		case 0x76: return ("fneg", 0, "", .arithmetic, nil)
		case 0x77: return ("dneg", 0, "", .arithmetic, nil)

			// Shifts
		case 0x78: return ("ishl", 0, "", .logic, nil)
		case 0x79: return ("lshl", 0, "", .logic, nil)
		case 0x7A: return ("ishr", 0, "", .logic, nil)
		case 0x7B: return ("lshr", 0, "", .logic, nil)
		case 0x7C: return ("iushr", 0, "", .logic, nil)
		case 0x7D: return ("lushr", 0, "", .logic, nil)

			// Logic
		case 0x7E: return ("iand", 0, "", .logic, nil)
		case 0x7F: return ("land", 0, "", .logic, nil)
		case 0x80: return ("ior", 0, "", .logic, nil)
		case 0x81: return ("lor", 0, "", .logic, nil)
		case 0x82: return ("ixor", 0, "", .logic, nil)
		case 0x83: return ("lxor", 0, "", .logic, nil)

			// Increment
		case 0x84:
			let index = offset + 1 < data.count ? data[offset + 1] : 0
			let value = offset + 2 < data.count ? Int8(bitPattern: data[offset + 2]) : 0
			return ("iinc", 2, "\(index), \(value)", .arithmetic, nil)

			// Conversions
		case 0x85: return ("i2l", 0, "", .other, nil)
		case 0x86: return ("i2f", 0, "", .other, nil)
		case 0x87: return ("i2d", 0, "", .other, nil)
		case 0x88: return ("l2i", 0, "", .other, nil)
		case 0x89: return ("l2f", 0, "", .other, nil)
		case 0x8A: return ("l2d", 0, "", .other, nil)
		case 0x8B: return ("f2i", 0, "", .other, nil)
		case 0x8C: return ("f2l", 0, "", .other, nil)
		case 0x8D: return ("f2d", 0, "", .other, nil)
		case 0x8E: return ("d2i", 0, "", .other, nil)
		case 0x8F: return ("d2l", 0, "", .other, nil)
		case 0x90: return ("d2f", 0, "", .other, nil)
		case 0x91: return ("i2b", 0, "", .other, nil)
		case 0x92: return ("i2c", 0, "", .other, nil)
		case 0x93: return ("i2s", 0, "", .other, nil)

			// Comparisons
		case 0x94: return ("lcmp", 0, "", .compare, nil)
		case 0x95: return ("fcmpl", 0, "", .compare, nil)
		case 0x96: return ("fcmpg", 0, "", .compare, nil)
		case 0x97: return ("dcmpl", 0, "", .compare, nil)
		case 0x98: return ("dcmpg", 0, "", .compare, nil)

			// Conditional branches
		case 0x99:
			let branchOffset = offset + 2 < data.count ? Int16(bigEndian: Int16(data[offset + 1]) << 8 | Int16(data[offset + 2])) : 0
			let target = UInt64(Int64(address) + Int64(branchOffset))
			return ("ifeq", 2, formatAddress(target), .conditionalJump, target)
		case 0x9A:
			let branchOffset = offset + 2 < data.count ? Int16(bigEndian: Int16(data[offset + 1]) << 8 | Int16(data[offset + 2])) : 0
			let target = UInt64(Int64(address) + Int64(branchOffset))
			return ("ifne", 2, formatAddress(target), .conditionalJump, target)
		case 0x9B:
			let branchOffset = offset + 2 < data.count ? Int16(bigEndian: Int16(data[offset + 1]) << 8 | Int16(data[offset + 2])) : 0
			let target = UInt64(Int64(address) + Int64(branchOffset))
			return ("iflt", 2, formatAddress(target), .conditionalJump, target)
		case 0x9C:
			let branchOffset = offset + 2 < data.count ? Int16(bigEndian: Int16(data[offset + 1]) << 8 | Int16(data[offset + 2])) : 0
			let target = UInt64(Int64(address) + Int64(branchOffset))
			return ("ifge", 2, formatAddress(target), .conditionalJump, target)
		case 0x9D:
			let branchOffset = offset + 2 < data.count ? Int16(bigEndian: Int16(data[offset + 1]) << 8 | Int16(data[offset + 2])) : 0
			let target = UInt64(Int64(address) + Int64(branchOffset))
			return ("ifgt", 2, formatAddress(target), .conditionalJump, target)
		case 0x9E:
			let branchOffset = offset + 2 < data.count ? Int16(bigEndian: Int16(data[offset + 1]) << 8 | Int16(data[offset + 2])) : 0
			let target = UInt64(Int64(address) + Int64(branchOffset))
			return ("ifle", 2, formatAddress(target), .conditionalJump, target)
		case 0x9F:
			let branchOffset = offset + 2 < data.count ? Int16(bigEndian: Int16(data[offset + 1]) << 8 | Int16(data[offset + 2])) : 0
			let target = UInt64(Int64(address) + Int64(branchOffset))
			return ("if_icmpeq", 2, formatAddress(target), .conditionalJump, target)
		case 0xA0:
			let branchOffset = offset + 2 < data.count ? Int16(bigEndian: Int16(data[offset + 1]) << 8 | Int16(data[offset + 2])) : 0
			let target = UInt64(Int64(address) + Int64(branchOffset))
			return ("if_icmpne", 2, formatAddress(target), .conditionalJump, target)
		case 0xA1:
			let branchOffset = offset + 2 < data.count ? Int16(bigEndian: Int16(data[offset + 1]) << 8 | Int16(data[offset + 2])) : 0
			let target = UInt64(Int64(address) + Int64(branchOffset))
			return ("if_icmplt", 2, formatAddress(target), .conditionalJump, target)
		case 0xA2:
			let branchOffset = offset + 2 < data.count ? Int16(bigEndian: Int16(data[offset + 1]) << 8 | Int16(data[offset + 2])) : 0
			let target = UInt64(Int64(address) + Int64(branchOffset))
			return ("if_icmpge", 2, formatAddress(target), .conditionalJump, target)
		case 0xA3:
			let branchOffset = offset + 2 < data.count ? Int16(bigEndian: Int16(data[offset + 1]) << 8 | Int16(data[offset + 2])) : 0
			let target = UInt64(Int64(address) + Int64(branchOffset))
			return ("if_icmpgt", 2, formatAddress(target), .conditionalJump, target)
		case 0xA4:
			let branchOffset = offset + 2 < data.count ? Int16(bigEndian: Int16(data[offset + 1]) << 8 | Int16(data[offset + 2])) : 0
			let target = UInt64(Int64(address) + Int64(branchOffset))
			return ("if_icmple", 2, formatAddress(target), .conditionalJump, target)
		case 0xA5:
			let branchOffset = offset + 2 < data.count ? Int16(bigEndian: Int16(data[offset + 1]) << 8 | Int16(data[offset + 2])) : 0
			let target = UInt64(Int64(address) + Int64(branchOffset))
			return ("if_acmpeq", 2, formatAddress(target), .conditionalJump, target)
		case 0xA6:
			let branchOffset = offset + 2 < data.count ? Int16(bigEndian: Int16(data[offset + 1]) << 8 | Int16(data[offset + 2])) : 0
			let target = UInt64(Int64(address) + Int64(branchOffset))
			return ("if_acmpne", 2, formatAddress(target), .conditionalJump, target)

			// Unconditional branches
		case 0xA7:
			let branchOffset = offset + 2 < data.count ? Int16(bigEndian: Int16(data[offset + 1]) << 8 | Int16(data[offset + 2])) : 0
			let target = UInt64(Int64(address) + Int64(branchOffset))
			return ("goto", 2, formatAddress(target), .jump, target)
		case 0xA8:
			let branchOffset = offset + 2 < data.count ? Int16(bigEndian: Int16(data[offset + 1]) << 8 | Int16(data[offset + 2])) : 0
			let target = UInt64(Int64(address) + Int64(branchOffset))
			return ("jsr", 2, formatAddress(target), .call, target)
		case 0xA9:
			let index = offset + 1 < data.count ? data[offset + 1] : 0
			return ("ret", 1, "\(index)", .return, nil)

			// Switch statements
		case 0xAA: return ("tableswitch", 0, "", .jump, nil)  // Variable length
		case 0xAB: return ("lookupswitch", 0, "", .jump, nil)  // Variable length

			// Returns
		case 0xAC: return ("ireturn", 0, "", .return, nil)
		case 0xAD: return ("lreturn", 0, "", .return, nil)
		case 0xAE: return ("freturn", 0, "", .return, nil)
		case 0xAF: return ("dreturn", 0, "", .return, nil)
		case 0xB0: return ("areturn", 0, "", .return, nil)
		case 0xB1: return ("return", 0, "", .return, nil)

			// Field access
		case 0xB2:
			let index = offset + 2 < data.count ? (UInt16(data[offset + 1]) << 8) | UInt16(data[offset + 2]) : 0
			return ("getstatic", 2, "#\(index)", .load, nil)
		case 0xB3:
			let index = offset + 2 < data.count ? (UInt16(data[offset + 1]) << 8) | UInt16(data[offset + 2]) : 0
			return ("putstatic", 2, "#\(index)", .store, nil)
		case 0xB4:
			let index = offset + 2 < data.count ? (UInt16(data[offset + 1]) << 8) | UInt16(data[offset + 2]) : 0
			return ("getfield", 2, "#\(index)", .load, nil)
		case 0xB5:
			let index = offset + 2 < data.count ? (UInt16(data[offset + 1]) << 8) | UInt16(data[offset + 2]) : 0
			return ("putfield", 2, "#\(index)", .store, nil)

			// Method invocation
		case 0xB6:
			let index = offset + 2 < data.count ? (UInt16(data[offset + 1]) << 8) | UInt16(data[offset + 2]) : 0
			return ("invokevirtual", 2, "#\(index)", .call, nil)
		case 0xB7:
			let index = offset + 2 < data.count ? (UInt16(data[offset + 1]) << 8) | UInt16(data[offset + 2]) : 0
			return ("invokespecial", 2, "#\(index)", .call, nil)
		case 0xB8:
			let index = offset + 2 < data.count ? (UInt16(data[offset + 1]) << 8) | UInt16(data[offset + 2]) : 0
			return ("invokestatic", 2, "#\(index)", .call, nil)
		case 0xB9:
			let index = offset + 2 < data.count ? (UInt16(data[offset + 1]) << 8) | UInt16(data[offset + 2]) : 0
			return ("invokeinterface", 4, "#\(index)", .call, nil)
		case 0xBA:
			let index = offset + 2 < data.count ? (UInt16(data[offset + 1]) << 8) | UInt16(data[offset + 2]) : 0
			return ("invokedynamic", 4, "#\(index)", .call, nil)

			// Object creation
		case 0xBB:
			let index = offset + 2 < data.count ? (UInt16(data[offset + 1]) << 8) | UInt16(data[offset + 2]) : 0
			return ("new", 2, "#\(index)", .other, nil)
		case 0xBC:
			let atype = offset + 1 < data.count ? data[offset + 1] : 0
			let typeName: String
			switch atype {
			case 4: typeName = "boolean"
			case 5: typeName = "char"
			case 6: typeName = "float"
			case 7: typeName = "double"
			case 8: typeName = "byte"
			case 9: typeName = "short"
			case 10: typeName = "int"
			case 11: typeName = "long"
			default: typeName = "\(atype)"
			}
			return ("newarray", 1, typeName, .other, nil)
		case 0xBD:
			let index = offset + 2 < data.count ? (UInt16(data[offset + 1]) << 8) | UInt16(data[offset + 2]) : 0
			return ("anewarray", 2, "#\(index)", .other, nil)
		case 0xBE: return ("arraylength", 0, "", .other, nil)

			// Exceptions
		case 0xBF: return ("athrow", 0, "", .other, nil)

			// Type checking
		case 0xC0:
			let index = offset + 2 < data.count ? (UInt16(data[offset + 1]) << 8) | UInt16(data[offset + 2]) : 0
			return ("checkcast", 2, "#\(index)", .other, nil)
		case 0xC1:
			let index = offset + 2 < data.count ? (UInt16(data[offset + 1]) << 8) | UInt16(data[offset + 2]) : 0
			return ("instanceof", 2, "#\(index)", .compare, nil)

			// Synchronization
		case 0xC2: return ("monitorenter", 0, "", .other, nil)
		case 0xC3: return ("monitorexit", 0, "", .other, nil)

			// Wide prefix
		case 0xC4: return ("wide", 0, "", .other, nil)

			// Multidimensional array
		case 0xC5:
			let index = offset + 2 < data.count ? (UInt16(data[offset + 1]) << 8) | UInt16(data[offset + 2]) : 0
			let dimensions = offset + 3 < data.count ? data[offset + 3] : 0
			return ("multianewarray", 3, "#\(index), \(dimensions)", .other, nil)

			// Null checks
		case 0xC6:
			let branchOffset = offset + 2 < data.count ? Int16(bigEndian: Int16(data[offset + 1]) << 8 | Int16(data[offset + 2])) : 0
			let target = UInt64(Int64(address) + Int64(branchOffset))
			return ("ifnull", 2, formatAddress(target), .conditionalJump, target)
		case 0xC7:
			let branchOffset = offset + 2 < data.count ? Int16(bigEndian: Int16(data[offset + 1]) << 8 | Int16(data[offset + 2])) : 0
			let target = UInt64(Int64(address) + Int64(branchOffset))
			return ("ifnonnull", 2, formatAddress(target), .conditionalJump, target)

			// Wide branches
		case 0xC8:
			var branchOffset: Int32 = 0
			if offset + 4 < data.count {
				branchOffset = Int32(data[offset + 1]) << 24 | Int32(data[offset + 2]) << 16 | Int32(data[offset + 3]) << 8 | Int32(data[offset + 4])
			}
			let target = UInt64(Int64(address) + Int64(branchOffset))
			return ("goto_w", 4, formatAddress(target), .jump, target)
		case 0xC9:
			var branchOffset: Int32 = 0
			if offset + 4 < data.count {
				branchOffset = Int32(data[offset + 1]) << 24 | Int32(data[offset + 2]) << 16 | Int32(data[offset + 3]) << 8 | Int32(data[offset + 4])
			}
			let target = UInt64(Int64(address) + Int64(branchOffset))
			return ("jsr_w", 4, formatAddress(target), .call, target)

			// Breakpoint and reserved
		case 0xCA: return ("breakpoint", 0, "", .interrupt, nil)
		case 0xFE: return ("impdep1", 0, "", .other, nil)
		case 0xFF: return ("impdep2", 0, "", .other, nil)

		default:
			return (String(format: ".byte 0x%02X", opcode), 0, "", .other, nil)
		}
	}

	private func formatAddress(_ addr: UInt64) -> String {
		return String(format: "0x%llX", addr)
	}
}
