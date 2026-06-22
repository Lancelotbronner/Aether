//
//  Types.swift
//  AetherKit
//
//  Created by Christophe Bronner on 2026-06-20.
//

public struct Size<Value: UnsignedInteger & Sendable>: Sendable {
	public var bits: Value

	@inlinable
	public init(bits: Value) {
		self.bits = bits
	}
}

public extension Size {
	@inlinable
	var bytes: Value {
		bits / 8
	}

	@inlinable
	init(bytes: Value) {
		self.init(bits: bytes * 8)
	}
}

public struct ContiguousMask<Value: FixedWidthInteger & Sendable>: Sendable {
	public var bits: Value
	
	@inlinable
	public init(mask: Value) {
		self.bits = mask
	}

	@inlinable
	public init(_ range: some RangeExpression<Int>) {
		let indices = range.relative(to: 0..<Value.bitWidth)
		let max = ~Value.zero
		let mask = (max << indices.upperBound) ^ (max << indices.lowerBound)
		self.bits = mask
	}
}

public extension ContiguousMask {
	@inlinable
	var size: Int {
		bits.nonzeroBitCount
	}

	@inlinable
	var shift: Int {
		bits.leadingZeroBitCount
	}

	@inlinable
	func extract(from value: Value) -> Value {
		(value & bits) >> shift
	}
}
