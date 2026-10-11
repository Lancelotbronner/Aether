//
//  Context.swift
//  AetherKit
//
//  Created by Christophe Bronner on 2026-06-21.
//

public struct ContextVariable: Sendable {
	public let from: Varnode
	public let mask: ContiguousMask<UInt64>
	public let flow: Bool

	@inlinable
	public init(
		_ field: some RangeExpression<Int>,
		of from: Varnode,
		flow: Bool,
	) {
		self.from = from
		mask = ContiguousMask(field)
		self.flow = flow
	}
}

public extension Varnode {
	func context(
		_ range: some RangeExpression<Int>,
		flow: Bool = true
	) -> ContextVariable {
		ContextVariable(range, of: self, flow: flow)
	}
}
