//
//  Context.swift
//  AetherKit
//
//  Created by Christophe Bronner on 2026-06-21.
//

public struct ContextVariable: Sendable {
	public let from: Varnode
	public let mask: ContiguousMask<UInt64>

	@inlinable
	public init(_ field: some RangeExpression<Int>, of from: Varnode) {
		self.from = from
		mask = ContiguousMask(field)
	}
}

public extension Varnode {
	func context(_ range: some RangeExpression<Int>) -> ContextVariable {
		ContextVariable(range, of: self)
	}
}
