//
//  Pcode.swift
//  Aether
//
//  Created by Christophe Bronner on 2026-06-10.
//

/// Pseudo-instructions.
public enum Pcode {
	// Data
	case copy(CopyOp)
	case load(LoadOp)
	case store(StoreOp)
	// Branching
	case goto(GotoOp)
	case igoto(IndirectGotoOp)
	case branch(BranchOp)
	case call(GotoOp)
	case icall(IndirectGotoOp)
	case ret(IndirectGotoOp)
	// Logic
	case not(UnaryLogicOp)
	case and(BinaryLogicOp)
	case or(BinaryLogicOp)
	case xor(BinaryLogicOp)
	// Conversions
	case i2f(UnaryOp)
	case f2i(UnaryOp)
	// Integer Arithmetic
	case neg(UnaryOp)
	case add(BinaryOp)
	case sub(BinaryOp)
	case mul(BinaryOp)
	case udiv(BinaryOp)
	case sdiv(BinaryOp)
	case urem(BinaryOp)
	case srem(BinaryOp)
	case inot(UnaryOp)
	case ixor(BinaryOp)
	case iand(BinaryOp)
	case ior(BinaryOp)
	// Integer Comparisons
	case eq(CompareOp)
	case neq(CompareOp)
	case carry(CompareOp)
	case scarry(CompareOp)
	static func borrow(_ op: CompareOp) -> Pcode { .ult(op) }
	case sborrow(CompareOp)
	case ult(CompareOp)
	case slt(CompareOp)
	case ulte(CompareOp)
	case slte(CompareOp)
	case ulshift(BinaryOp)
	case urshift(BinaryOp)
	case slshift(BinaryOp)
	case srshift(BinaryOp)
	// Floating Point Arithmetic
	case fneg(UnaryOp)
	case fabs(UnaryOp)
	case fsqrt(UnaryOp)
	case ceil(UnaryOp)
	case floor(UnaryOp)
	case round(UnaryOp)
	case nan(UnaryOp)
	case fadd(BinaryOp)
	case fsub(BinaryOp)
	case fmul(BinaryOp)
	case fdiv(BinaryOp)
	// Floating Point Comparison
	case feq(CompareOp)
	case fneq(CompareOp)
	case flt(CompareOp)
	case flte(CompareOp)
	// Extend/Truncate
	case fmov(ExtendOp)
	case zext(ExtendOp)
	case sext(ExtendOp)
	case concat(ConcatOp)
}

/// Copies from an address to another. `*dst = *src`
public struct CopyOp {
	public var fromAddress: Address
	public var toAddress: Address
	public var size: UInt32
	public var fromSpace: AddressSpaceId
	public var toSpace: AddressSpaceId

	public var src: Varnode {
		Varnode(at: fromAddress, in: fromSpace, size: size)
	}

	public var dst: Varnode {
		Varnode(at: toAddress, in: toSpace, size: size)
	}
}

/// Loads from a pointer to another. `*dst = **src`
public struct LoadOp {
	public var ptrAddress: Address
	public var dstAddress: Address
	public var dataSize: UInt32
	public var ptrSize: UInt8
	public var ptrSpace: AddressSpaceId
	public var dstSpace: AddressSpaceId
	public var dataSpace: AddressSpaceId

	public var srcPtr: Varnode {
		Varnode(at: ptrAddress, in: ptrSpace, size: ptrSize)
	}

	public func src(at offset: Address) -> Varnode {
		Varnode(at: offset, in: dataSpace, size: dataSize)
	}

	public var dst: Varnode {
		Varnode(at: dstAddress, in: dstSpace, size: dataSize)
	}
}

/// Stores from a pointer to another. `**dst = *src`
public struct StoreOp {
	public var srcAddress: Address
	public var ptrAddress: Address
	public var dataSize: UInt32
	public var ptrSize: UInt8
	public var srcSpace: AddressSpaceId
	public var ptrSpace: AddressSpaceId
	public var dataSpace: AddressSpaceId

	public var dstPtr: Varnode {
		Varnode(at: ptrAddress, in: ptrSpace, size: ptrSize)
	}

	public func dst(at offset: Address) -> Varnode {
		Varnode(at: offset, in: dataSpace, size: dataSize)
	}

	public var src: Varnode {
		Varnode(at: srcAddress, in: srcSpace, size: dataSize)
	}
}

/// Absolute unconditional jump.
public struct GotoOp {
	public var address: Address
	/// The pseudo-instruction offset to jump to, allows jumping to the middle of an instruction's pcode representation.
	public var offset: UInt32
	public var space: AddressSpaceId

	public var toPcode: Pcode { .goto(self) }

	public var target: Varnode {
		Varnode(at: address, in: space, size: offset)
	}
}

public struct IndirectGotoOp {
	public var ptrAddress: Address
	/// The pseudo-instruction offset to jump to, allows jumping to the middle of an instruction's pcode representation.
	public var offset: UInt32
	public var ptrSize: UInt8
	public var ptrSpace: AddressSpaceId
	public var targetSpace: AddressSpaceId

	public var toPcode: Pcode { .igoto(self) }

	@inlinable
	public init(goto ptr: Varnode, in space: AddressSpaceId = .mem, at offset: UInt32 = 0) {
		ptrAddress = ptr.offset
		self.offset = offset
		ptrSize = UInt8(ptr.size)
		ptrSpace = ptr.space
		targetSpace = space
	}

	public var ptr: Varnode {
		Varnode(at: ptrAddress, in: ptrSpace, size: ptrSize)
	}

	public func target(at addr: Address) -> Varnode {
		Varnode(at: addr, in: targetSpace, size: offset)
	}
}

/// Conditional jump.
public struct BranchOp {
	public var targetAddress: Address
	/// The pseudo-instruction offset to jump to, allows jumping to the middle of an instruction's pcode representation.
	public var targetOffset: UInt32
	public var targetSpace: AddressSpaceId
	public var condAddress: Address
	public var condSpace: AddressSpaceId

	public var toPcode: Pcode { .branch(self) }

	public var target: Varnode {
		Varnode(at: targetAddress, in: targetSpace, size: targetOffset)
	}

	public var cond: Varnode {
		Varnode(at: condAddress, in: condSpace, size: 1)
	}
}

public struct ExtendOp {
	public var inAddress: Address
	public var outAddress: Address
	public var inSize: UInt32
	public var outSize: UInt32
	public var inSpace: AddressSpaceId
	public var outSpace: AddressSpaceId

	public var `in`: Varnode {
		Varnode(at: inAddress, in: inSpace, size: inSize)
	}

	public var out: Varnode {
		Varnode(at: outAddress, in: outSpace, size: outSize)
	}
}

public struct ConcatOp {
	public var lhsAddress: Address
	public var rhsAddress: Address
	public var outAddress: Address
	public var lhsSize: UInt32
	public var rhsSize: UInt32
	public var lhsSpace: AddressSpaceId
	public var rhsSpace: AddressSpaceId
	public var outSpace: AddressSpaceId

	public var lhs: Varnode {
		Varnode(at: lhsAddress, in: lhsSpace, size: lhsSize)
	}

	public var rhs: Varnode {
		Varnode(at: rhsAddress, in: rhsSpace, size: rhsSize)
	}

	public var out: Varnode {
		Varnode(at: outAddress, in: outSpace, size: lhsSize + rhsSize)
	}
}

public struct CompareOp {
	public var lhsAddress: Address
	public var rhsAddress: Address
	public var outAddress: Address
	public var size: UInt32
	public var lhsSpace: AddressSpaceId
	public var rhsSpace: AddressSpaceId
	public var outSpace: AddressSpaceId

	public var lhs: Varnode {
		Varnode(at: lhsAddress, in: lhsSpace, size: size)
	}

	public var rhs: Varnode {
		Varnode(at: rhsAddress, in: rhsSpace, size: size)
	}

	public var out: Varnode {
		Varnode(at: outAddress, in: outSpace, size: 1)
	}
}

public struct UnaryLogicOp {
	public var inAddress: Address
	public var outAddress: Address
	public var inSpace: AddressSpaceId
	public var outSpace: AddressSpaceId

	public var `in`: Varnode {
		Varnode(at: inAddress, in: inSpace, size: 1)
	}

	public var out: Varnode {
		Varnode(at: outAddress, in: outSpace, size: 1)
	}
}

public struct BinaryLogicOp {
	public var lhsAddress: Address
	public var rhsAddress: Address
	public var outAddress: Address
	public var lhsSpace: AddressSpaceId
	public var rhsSpace: AddressSpaceId
	public var outSpace: AddressSpaceId

	public var lhs: Varnode {
		Varnode(at: lhsAddress, in: lhsSpace, size: 1)
	}

	public var rhs: Varnode {
		Varnode(at: rhsAddress, in: rhsSpace, size: 1)
	}

	public var out: Varnode {
		Varnode(at: outAddress, in: outSpace, size: 1)
	}
}

public struct UnaryOp {
	public var inAddress: Address
	public var outAddress: Address
	public var size: UInt32
	public var inSpace: AddressSpaceId
	public var outSpace: AddressSpaceId

	public var `in`: Varnode {
		Varnode(at: inAddress, in: inSpace, size: size)
	}

	public var out: Varnode {
		Varnode(at: outAddress, in: outSpace, size: size)
	}
}

public struct BinaryOp {
	public var lhsAddress: Address
	public var rhsAddress: Address
	public var outAddress: Address
	public var size: UInt32
	public var lhsSpace: AddressSpaceId
	public var rhsSpace: AddressSpaceId
	public var outSpace: AddressSpaceId

	public var lhs: Varnode {
		Varnode(at: lhsAddress, in: lhsSpace, size: size)
	}

	public var rhs: Varnode {
		Varnode(at: rhsAddress, in: rhsSpace, size: size)
	}

	public var out: Varnode {
		Varnode(at: outAddress, in: outSpace, size: size)
	}
}
