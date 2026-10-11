//
//  Varnode.swift
//  Aether
//
//  Created by Christophe Bronner on 2026-06-10.
//

public struct Varnode: Hashable, Comparable, Sendable {
	public var offset: Offset
	public var size: UInt32
	public var space: AddressSpaceId

	@inlinable
	public init(at offset: Offset, in space: AddressSpaceId, size: some FixedWidthInteger) {
		self.offset = offset
		self.size = UInt32(size)
		self.space = space
	}

	@inlinable
	public static func < (lhs: borrowing Varnode, rhs: borrowing Varnode) -> Bool {
		guard lhs.space == rhs.space else { return lhs.space < rhs.space }
		guard lhs.offset == rhs.offset else { return lhs.offset < rhs.offset }
		// bigger varnodes come first
		return lhs.size > rhs.size
	}
}

public extension Varnode {
	@inlinable
	var address: Address2 {
		Address2(offset: offset, space: space)
	}

	@inlinable
	func advanced(by offset: some FixedWidthInteger) -> Varnode {
		Varnode(at: self.offset + Offset(offset), in: space, size: size)
	}

	@inlinable
	static func strides<let count: Int>(
		from offset: Offset,
		by stride: Offset,
		in space: AddressSpaceId,
		size: UInt32
	) -> InlineArray<count, Varnode> {
		InlineArray(first: Varnode(at: offset, in: space, size: size)) { previous in
			previous.advanced(by: stride)
		}
	}
}

//MARK: - Workaround for no InlineArray pattern

public extension Varnode {
	@inlinable
	static func stride(
		from offset: Offset,
		by stride: Offset,
		in space: AddressSpaceId,
		size: UInt32
	) -> (Varnode) {
		let names: [1 of Varnode] = Self.strides(from: offset, by: stride, in: space, size: size)
		return (names[0])
	}

	@inlinable @_disfavoredOverload
	static func stride(
		from offset: Offset,
		by stride: Offset,
		in space: AddressSpaceId,
		size: UInt32
	) -> (Varnode, Varnode) {
		let names: [2 of Varnode] = Self.strides(from: offset, by: stride, in: space, size: size)
		return (names[0], names[1])
	}

	@inlinable @_disfavoredOverload
	static func stride(
		from offset: Offset,
		by stride: Offset,
		in space: AddressSpaceId,
		size: UInt32
	) -> (Varnode, Varnode, Varnode) {
		let names: [3 of Varnode] = Self.strides(from: offset, by: stride, in: space, size: size)
		return (names[0], names[1], names[2])
	}

	@inlinable @_disfavoredOverload
	static func stride(
		from offset: Offset,
		by stride: Offset,
		in space: AddressSpaceId,
		size: UInt32
	) -> (Varnode, Varnode, Varnode, Varnode) {
		let names: [4 of Varnode] = Self.strides(from: offset, by: stride, in: space, size: size)
		return (names[0], names[1], names[2], names[3])
	}

	@inlinable @_disfavoredOverload
	static func stride(
		from offset: Offset,
		by stride: Offset,
		in space: AddressSpaceId,
		size: UInt32
	) -> (Varnode, Varnode, Varnode, Varnode, Varnode) {
		let names: [5 of Varnode] = Self.strides(from: offset, by: stride, in: space, size: size)
		return (names[0], names[1], names[2], names[3], names[4])
	}

	@inlinable @_disfavoredOverload
	static func stride(
		from offset: Offset,
		by stride: Offset,
		in space: AddressSpaceId,
		size: UInt32
	) -> (Varnode, Varnode, Varnode, Varnode, Varnode, Varnode) {
		let names: [6 of Varnode] = Self.strides(from: offset, by: stride, in: space, size: size)
		return (names[0], names[1], names[2], names[3], names[4], names[5])
	}

	@inlinable @_disfavoredOverload
	static func stride(
		from offset: Offset,
		by stride: Offset,
		in space: AddressSpaceId,
		size: UInt32
	) -> (Varnode, Varnode, Varnode, Varnode, Varnode, Varnode, Varnode) {
		let names: [7 of Varnode] = Self.strides(from: offset, by: stride, in: space, size: size)
		return (names[0], names[1], names[2], names[3], names[4], names[5], names[6])
	}

	@inlinable @_disfavoredOverload
	static func stride(
		from offset: Offset,
		by stride: Offset,
		in space: AddressSpaceId,
		size: UInt32
	) -> (Varnode, Varnode, Varnode, Varnode, Varnode, Varnode, Varnode, Varnode) {
		let names: [8 of Varnode] = Self.strides(from: offset, by: stride, in: space, size: size)
		return (names[0], names[1], names[2], names[3], names[4], names[5], names[6], names[7])
	}

	@inlinable @_disfavoredOverload
	static func stride(
		from offset: Offset,
		by stride: Offset,
		in space: AddressSpaceId,
		size: UInt32
	) -> (Varnode, Varnode, Varnode, Varnode, Varnode, Varnode, Varnode, Varnode, Varnode, Varnode, Varnode, Varnode, Varnode, Varnode, Varnode, Varnode) {
		let names: [16 of Varnode] = Self.strides(from: offset, by: stride, in: space, size: size)
		return (names[0], names[1], names[2], names[3], names[4], names[5], names[6], names[7], names[8], names[9], names[10], names[11], names[12], names[13], names[14], names[15])
	}

	@inlinable @_disfavoredOverload
	static func stride(
		from offset: Offset,
		by stride: Offset,
		in space: AddressSpaceId,
		size: UInt32
	) -> (Varnode, Varnode, Varnode, Varnode, Varnode, Varnode, Varnode, Varnode, Varnode, Varnode, Varnode, Varnode, Varnode, Varnode, Varnode, Varnode, Varnode, Varnode, Varnode, Varnode, Varnode) {
		let names: [21 of Varnode] = Self.strides(from: offset, by: stride, in: space, size: size)
		return (names[0], names[1], names[2], names[3], names[4], names[5], names[6], names[7], names[8], names[9], names[10], names[11], names[12], names[13], names[14], names[15], names[16], names[17], names[18], names[19], names[20])
	}

	@inlinable @_disfavoredOverload
	static func stride(
		from offset: Offset,
		by stride: Offset,
		in space: AddressSpaceId,
		size: UInt32
	) -> (Varnode, Varnode, Varnode, Varnode, Varnode, Varnode, Varnode, Varnode, Varnode, Varnode, Varnode, Varnode, Varnode, Varnode, Varnode, Varnode, Varnode, Varnode, Varnode, Varnode, Varnode, Varnode, Varnode, Varnode, Varnode, Varnode, Varnode, Varnode, Varnode, Varnode, Varnode, Varnode) {
		let names: [32 of Varnode] = Self.strides(from: offset, by: stride, in: space, size: size)
		return (names[0], names[1], names[2], names[3], names[4], names[5], names[6], names[7], names[8], names[9], names[10], names[11], names[12], names[13], names[14], names[15], names[16], names[17], names[18], names[19], names[20], names[21], names[22], names[23], names[24], names[25], names[26], names[27], names[28], names[29], names[30], names[31])
	}
}
