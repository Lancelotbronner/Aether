//
//  DisassemblerPlugin.swift
//  Aether
//
//  Created by Christophe Bronner on 2026-06-04.
//

import SwiftUI

nonisolated protocol DisassemblerPlugin : ~Copyable {
	init?(for binary: BinaryFile) throws

	/// Disassembles a single instruction.
	mutating func disassemble(_ context: any DisassemblyContext) throws
}

nonisolated protocol DisassemblyContext: AnyObject {
	var baseAddress: UInt64 { get }
	var code: Data { get }
	var nextAddress: UInt64 { get set }
	var mode: CpuMode { get set }
	var bytes: Data { get set }
	var instruction: DisassemblyInstruction { get set }

	/// Submits the difference between the previous submit and the current state, resets ``instruction``, all calls now affect the next instruction.
	func submit()
	func xref(to address: UInt64)
	func xref(from address: UInt64)
}
