//
//  Size.swift
//  AetherKit
//
//  Created by Christophe Bronner on 2026-10-11.
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
