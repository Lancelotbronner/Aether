//
//  x86.swift
//  Aether
//
//  Created by Christophe Bronner on 2026-06-07.
//

import capstone

nonisolated extension X86.InstructionId {
	var conditionalJump: DisassemblyBranch? {
		switch self {
		case .X86_INS_JA: .ja
		case .X86_INS_JB: .jb
		case .X86_INS_JE: .je
		case .X86_INS_JG: .jg
		case .X86_INS_JL: .jl
		case .X86_INS_JO: .jo
		case .X86_INS_JP: .jp
		case .X86_INS_JS: .js
		case .X86_INS_JAE: .jae
		case .X86_INS_JBE: .jbe
		case .X86_INS_JGE: .jge
		case .X86_INS_JLE: .jle
		case .X86_INS_JMP: .jmp
		case .X86_INS_JNE: .jne
		case .X86_INS_JNO: .jno
		case .X86_INS_JNP: .jnp
		case .X86_INS_JNS: .jns
		case .X86_INS_JCXZ: .jcxz
		case .X86_INS_JECXZ: .jecxz
		case .X86_INS_JRCXZ: .jrcxz
			//TODO: Support long jumps
		case .X86_INS_LJMP: nil
		default: nil
		}
	}
}
