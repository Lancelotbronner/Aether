//
//  Disassembly.swift
//  Aether
//
//  Created by Christophe Bronner on 2026-06-12.
//

import AetherKit
nonisolated struct DisassemblyEntry: Identifiable {
	let address: UInt64
	let ty: DisassemblyTy
	var id: UInt64 { address }
}

extension DisassemblyEntry {
	func operands(in file: BinaryFile) -> String {
		switch ty {
		case .u8: file.load(UInt8.self, at: address).description
		case .u16: file.load(UInt16.self, at: address).description
		case .u32: file.load(UInt32.self, at: address).description
		case .u64: file.load(UInt64.self, at: address).description
		case .i8: file.load(Int8.self, at: address).description
		case .i16: file.load(Int16.self, at: address).description
		case .i32: file.load(Int32.self, at: address).description
		case .i64: file.load(Int64.self, at: address).description
		case .f32: file.load(Float32.self, at: address).description
		case .f64: file.load(Float64.self, at: address).description
		case .ascii: file.ascii(at: address).quoted
		case .unicode: file.unicode(at: address).quoted
		case let .instruction(_, operands):
			operands
		}
	}

	func mnemonic(in file: BinaryFile) -> String {
		switch ty {
		case .u8: "u8"
		case .u16: "u16"
		case .u32: "u32"
		case .u64: "u64"
		case .i8: "i8"
		case .i16: "i16"
		case .i32: "i32"
		case .i64: "i64"
		case .f32: "f32"
		case .f64: "f64"
		case .ascii: "ascii"
		case .unicode: "unicode"
		case let .instruction(mnemonic, _): mnemonic
		}
	}
}

enum DisassemblyTy {
	case u8, u16, u32, u64
	case i8, i16, i32, i64
	case f32, f64
	case ascii, unicode
	case instruction(mnemonic: String, operands: String)
	//TODO: struct, enum, address
}
