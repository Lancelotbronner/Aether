//
//  Address.swift
//  AetherKit
//
//  Created by Christophe Bronner on 2026-06-10.
//

public typealias Address = UInt64
public typealias Offset = UInt64

public struct Address2: Hashable, Sendable {
	public var offset: Offset
	public var space: AddressSpaceId

	public init(offset: Offset, space: AddressSpaceId) {
		self.offset = offset
		self.space = space
	}
}

public struct AddressSpaceId: RawRepresentable, Hashable, Comparable, Sendable {
	public var rawValue: UInt8

	public init(rawValue: UInt8) {
		self.rawValue = rawValue
	}

	public init(_ kind: Kind, id: UInt8) {
		rawValue = (id & ~Kind.mask) | kind.rawValue
	}

	public static func < (lhs: borrowing AddressSpaceId, rhs: borrowing AddressSpaceId) -> Bool {
		lhs.rawValue < rhs.rawValue
	}
}

public extension AddressSpaceId {
	enum Kind: UInt8 {
		case special = 0x00
		case memory = 0x80
		case register = 0xC0

		static let mask: RawValue = 0xC0
	}

	var kind: Kind {
		Kind(rawValue: rawValue & Kind.mask)!
	}

	/// Special space to represent constants
	static let const = Self(.special, id: 0)
	static let stack = Self(.special, id: 1)

	static let mem = Self(.memory, id: 0)
	static let reg = Self(.register, id: 0)
}
