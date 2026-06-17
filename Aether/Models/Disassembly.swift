//
//  Disassembly.swift
//  Aether
//
//  Created by Christophe Bronner on 2026-06-12.
//

import AetherKit

nonisolated struct Disassembly: RandomAccessCollection {
	struct Storage {
		var bytes: ContiguousArray<DisassembledByte>
		var count: Int
	}

	typealias Element = DisassembledByte
	typealias Index = Int
	typealias SubSequence = Slice<Disassembly>

	@Cow @usableFromInline
	var _storage: Storage

	public init(size: Int) {
		_storage = Storage(bytes: ContiguousArray(repeating: .undefined, count: size), count: size)
	}
}

nonisolated extension Disassembly {
	@inlinable @_transparent
	var startIndex: Int { _storage.bytes.startIndex }
	@inlinable @_transparent
	var endIndex: Int { _storage.bytes.endIndex }
	@inlinable @_transparent
	func index(before i: Int) -> Int { _storage.bytes.index(before: i) }
	@inlinable @_transparent
	func index(after i: Int) -> Int { _storage.bytes.index(after: i) }

	subscript(position: Int) -> DisassembledByte {
		@inlinable @_transparent
		get { _storage.bytes[position] }
		@inlinable
		set {
			_storage.count += diff(from: _storage.bytes[position], to: newValue)
			_storage.bytes[position] = newValue
		}
	}

	subscript(bounds: Range<Int>) -> Element? {
		@inlinable @_transparent
		get {
			guard _storage.bytes[bounds.dropFirst()].allSatisfy({ $0 == .next }) else { return nil }
			return _storage.bytes[bounds.lowerBound]
		}
		set {
			guard let newValue, !bounds.isEmpty else { return }
			self[bounds.lowerBound] = newValue
			for i in bounds.dropFirst() {
				self[i] = .next
			}
		}
	}

	subscript(bounds: some RangeExpression<Int>) -> Element? {
		get { self[bounds.relative(to: _storage.bytes)] }
		set { self[bounds.relative(to: _storage.bytes)] = newValue }
	}

	private func diff(from: Element, to: Element) -> Int {
		switch (from, to) {
		case (.next, .next): 0
		case (_, .next): -1
		case (.next, _): 1
		default: 0
		}
	}
}

nonisolated enum DisassembledByte: UInt8 {
	// Control
	case undefined = 0x00
	case next = 0x01
	case outside = 0x02
	case align = 0x04
	// Code
	/// Instruction to be disassembled.
	case code = 0x10
	/// Start of a procedure.
	case procedure = 0x11
	/// Thunks are their own procedures but for all intents and purposes they refer to another procedure.
	case thunk = 0x12
	// Integers
	case u8 = 0x20
	case u16 = 0x21
	case u32 = 0x22
	case u64 = 0x23
	case u128 = 0x24
	case u256 = 0x25
	case u512 = 0x26
	case u1024 = 0x27
	case i8 = 0x28
	case i16 = 0x29
	case i32 = 0x2a
	case i64 = 0x2b
	case i128 = 0x2c
	case i256 = 0x2d
	case i512 = 0x2e
	case i1024 = 0x2f
	// Floats
	case f32 = 0x30
	case f64 = 0x31
	// Strings
	case ascii = 0x40
	case unicode = 0x41
	// Types
	case `struct` = 0x50
	case `enum` = 0x51
}

/// An entry in the disassembly view.
nonisolated struct DisassembledEntry: Identifiable {
	let addressRange: Range<UInt64>
	let ty: DisassembledByte
	var address: UInt64 { addressRange.lowerBound }
	var size: Int { addressRange.count }
	var id: UInt64 { addressRange.lowerBound }
}

//extension DisassembledEntry {
//	func operands(in file: BinaryFile) -> String {
//		switch ty {
//		case .u8: file.load(UInt8.self, at: address).description
//		case .u16: file.load(UInt16.self, at: address).description
//		case .u32: file.load(UInt32.self, at: address).description
//		case .u64: file.load(UInt64.self, at: address).description
//		case .i8: file.load(Int8.self, at: address).description
//		case .i16: file.load(Int16.self, at: address).description
//		case .i32: file.load(Int32.self, at: address).description
//		case .i64: file.load(Int64.self, at: address).description
//		case .f32: file.load(Float32.self, at: address).description
//		case .f64: file.load(Float64.self, at: address).description
//		case .ascii: file.ascii(at: address).quoted
//		case .unicode: file.unicode(at: address).quoted
//		case let .code(_, operands):
//			operands
//		}
//	}
//
//	func mnemonic(in file: BinaryFile) -> String {
//		switch ty {
//		case .u8: "u8"
//		case .u16: "u16"
//		case .u32: "u32"
//		case .u64: "u64"
//		case .i8: "i8"
//		case .i16: "i16"
//		case .i32: "i32"
//		case .i64: "i64"
//		case .f32: "f32"
//		case .f64: "f64"
//		case .ascii: "ascii"
//		case .unicode: "unicode"
//		case let .code(mnemonic, _): mnemonic
//		}
//	}
//}

/// The kind of disassembly entry.
enum DisassemblyTy {
	case u8, u16, u32, u64
	case i8, i16, i32, i64
	case f32, f64
	case ascii, unicode
	case code(mnemonic: String, operands: String)
	//TODO: struct, enum, address
}
