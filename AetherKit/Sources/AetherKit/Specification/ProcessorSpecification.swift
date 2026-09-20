//
//  ProcessorSpec.swift
//  AetherKit
//
//  Created by Christophe Bronner on 2026-06-20.
//

public final class ProcessorSpecification {
	public var name: String
	public var endian: Endian
	/// This specifies the byte alignment of instructions within their address space.
	/// It defaults to 1 or no alignment.
	///
	/// When disassembling an instruction at a particular address, the disassembler checks the alignment of the address against this value and can opt to flag an unaligned instruction as an error.
	public var alignment: UInt8 = 1
	public var spaces: [AddressSpaceId: AddressSpace] = [:]
	public var defaultSpace: AddressSpaceId?
	public var symbols: [Symbol] = []
	public var tokens: [Token] = []
	public var tables: [Table] = []
	public var rules: [Rule] = []

	init(name: String, endian: Endian) {
		self.name = name
		self.endian = endian
	}
}

public struct AddressSpace: Sendable {
	public var name: String
	public var id: AddressSpaceId
	/// The number of bytes needed to address any byte within the space, for example a 32-bit address space has size 4.
	public var size: Size<UInt8>
	/// The wordsize attribute can be used to specify the size of the memory location referred to with a single address.
	public var wordsize = Size<UInt8>(bits: 8)
}

public extension ProcessorSpecification {
	enum Endian {
		case big, little
	}

	struct Symbol {
		public var name: String
		public var address: Address2
		public var size: Size<UInt8>
	}

	struct Token: Sendable {
		public var name: String
		public var size: Size<UInt8>
	}

	struct Field: Sendable {
		public var name: String
		/// Identifier of the token.
		public var token: String
		public var mask: ContiguousMask<UInt8>
		/// Format of the field
		public var format: Format
		/// Semantic map of values
		public var values: [Int]?
	}

	enum Format: Sendable {
		case bit
		case integer(IntegerFormat)
		case symbols([Int])
		case names([String])

		public static func integer(_ sign: IntegerSignedness, _ radix: IntegerRadix) -> Format {
			.integer(IntegerFormat(signedness: sign, radix: radix))
		}
	}

	struct IntegerFormat: Sendable {
		var signedness: IntegerSignedness
		var radix: IntegerRadix
	}

	enum IntegerSignedness: Sendable {
		case signed, unsigned
	}

	enum IntegerRadix: Sendable {
		case binary, octal, decimal, hex
	}

	struct Context {
		public var name: String
		/// Identifier of the symbol from which this context comes from.
		public var symbol: UInt8
		public var offset: Size<UInt8>
		public var size: Size<UInt8>
		/// Format of the field
		public var format: Format
		/// Semantic map of values
		public var values: [Int]?
	}

	struct Table {
		public var name: String
	}

	struct Rule {
		public var table: String
		public var pattern = Pattern.always
		public var displayString = ""
	}

	enum Pattern {
		case always, never

		case all([Pattern])
		case any([Pattern])

		/// Only if a field is equal to a value.
		case where64(UInt8, UInt64)

		// Fetch from instruction encoding, mask & compare
		case u8(UInt8, UInt8)
		case u16(UInt16, UInt16)
		case u32(UInt32, UInt32)
		case u64(UInt64, UInt64)
	}
}

public extension ProcessorSpecification.Token {
	func field(_ name: String, at range: some RangeExpression<Int>, format: ProcessorSpecification.Format = .integer(.unsigned, .decimal)) -> ProcessorSpecification.Field {
		.init(name: name, token: name, mask: ContiguousMask(range), format: format)
	}
}
