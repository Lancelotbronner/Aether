//
//  DisassemblerContext.swift
//  CoreAether
//
//  Created by Christophe Bronner on 2026-06-28.
//

protocol Disassembler {
	var assembly: String { get set }
	mutating func instruction() throws(DisassemblyError)
}

public final class DisassemblerContext {
	var instructions: [Instruction] = []
	var pcode: [Int] = []

	func next(using disassembler: some Disassembler) {
		// only if data is not empty
		disassembler.assembly = ""
		try disassembler.instruction()
		// if error is invalid instruction, skip 1 byte and try again
	}
}

struct Instruction {
	let assembly: String
	let pcode: Range<Int>
}
