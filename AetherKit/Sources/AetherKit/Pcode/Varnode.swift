//
//  Varnode.swift
//  Aether
//
//  Created by Christophe Bronner on 2026-06-10.
//

public struct Varnode {
	public var address: Address
	public var size: UInt32
	public var space: AddressSpace

	@inlinable
	public init(at address: Address, in space: AddressSpace, size: some FixedWidthInteger) {
		self.address = address
		self.size = UInt32(size)
		self.space = space
	}
}

public extension Varnode {
	
}
