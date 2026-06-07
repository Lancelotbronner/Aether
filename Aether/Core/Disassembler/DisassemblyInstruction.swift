//
//  DisassemblyInstruction.swift
//  Aether
//
//  Created by Christophe Bronner on 2026-06-04.
//

nonisolated struct DisassemblyInstruction {
	/// The kind of instruction this is
	var kind = InstructionKind.other
	/// Instruction mnemonic, with its optional condition.
	var assembly = InstructionAssembly()
	/// Condition to be met to execute instruction.
	var condition = DisassemblyCondition.never
	/// A field that you can use internally to keep information on the instruction.
	var userData: UInt64 = 0

	/// Information on the CPU state register after this instruction is executed.
	var eflags = EFlags()

	/// The value of the PC register at this address.
	/// For instance, on the Intel processor, it will be the address of the instruction + the length of the instruction.
	/// For the ARM processor, it will be the address of the instruction + 4 or 8, depending on various things.
	/// Anyway, it must reflects the exact value of the PC register if read from the instruction.
	var pcRegisterValue: UInt64 = 0

	/// Whether the instruction is known to halt.
	var halt = Halt.never

	/// If the next instruction is known to switch to a CPU mode.
	var mode: CpuMode?

	var readCount: UInt8 = 0
	var modifiedCount: UInt8 = 0
	/// The registers read by the instruction.
	var read = RegistersR(repeating: .init(rawValue: 0))
	/// The registers modified by the instruction.
	var modified = RegistersW(repeating: .init(rawValue: 0))

	/// Special instruction flags
	var flags: DisassemblyInstructionFlags = []

	/// The operands of the instruction.
	var operands = InlineArray<6, DisassemblyOperand>(repeating: .init())

	typealias RegistersR = InlineArray<20, RegisterIndex>
	typealias RegistersW = InlineArray<47, RegisterIndex>
}

nonisolated struct InstructionAssembly {
	var mnemonic = ""
	var condition = ""
	var operands = ""
}

/// Classification of instruction types
nonisolated enum InstructionKind: Equatable, Codable {
	case move
	case arithmetic
	case logic
	case compare
	/// This instruction is a kind of branch
	case branch(DisassemblyBranch, UInt64)
	/// Call a procedure
	case call(UInt64)
	/// Return from a procedure
	case ret
	case push
	case pop
	case load
	case store
	case nop
	case interrupt
	case syscall
	case other
}

nonisolated extension InstructionKind {
	var type: InstructionType {
		switch self {
		case .move: .move
		case .arithmetic: .arithmetic
		case .logic: .logic
		case .compare: .compare
		case .branch(.jmp, _): .jump
		case .branch: .conditionalJump
		case .call: .call
		case .ret: .return
		case .push: .push
		case .pop: .pop
		case .load: .load
		case .store: .store
		case .nop: .nop
		case .interrupt: .interrupt
		case .syscall: .syscall
		case .other: .other
		}
	}
	var isBranch: Bool {
		switch self {
		case .branch: true
		default: false
		}
	}

	var isLoad: Bool {
		switch self {
		case .load: true
		default: false
		}
	}

	var isStore: Bool {
		switch self {
		case .store: true
		default: false
		}
	}

	var branchTarget: UInt64? {
		switch self {
		case let .branch(_, target): target
		case let .call(target): target
		default: nil
		}
	}

	var isControlFlow: Bool {
		switch self {
		case .branch, .call, .ret: true
		default: false
		}
	}

	var isEndOfBlock: Bool {
		switch self {
		case .branch, .ret: true
		default: false
		}
	}
}

nonisolated enum Halt {
	case never, maybe, always
}

nonisolated enum DisassemblyBranch: Int8, Codable {
	/// Jump if not overflow
	case jno = -1
	/// Jump if not carry
	case jnc = -2
	/// Jump if not below
	static let jnb = Self.jnc
	/// Jump if not equal
	case jne = -3
	/// Jump if not above (CF = 1 or ZF = 1)
	case jna = -4
	/// Jump if below or equal (CF = 1 or ZF = 1)
	static let jbe = Self.jna
	/// Jump if not sign
	case jns = -5
	/// Jump if not parity
	case jnp = -6
	/// Jump if not less
	case jnl = -7
	/// Jump if not greater
	case jng = -8

	/// Jump unconditionally
	case jmp = 0

	/// Jump if overflow (OF=1)
	case jo = 1
	/// Jump if carry (CF=1)
	case jc = 2
	/// Jump if below (CF=1)
	static let jb = Self.jc
	/// Jump if equal (ZF=1)
	case je = 3
	/// Jump if above (CF=0 and ZF=0)
	case ja = 4
	/// Jump if above or equal (i.e. not greater)
	static let jae = Self.jnb
	/// Jump if sign (SF=1)
	case js = 5
	/// Jump if parity even (PF=1)
	case jp = 6
	/// Jump if less (SF != OF)
	case jl = 7
	/// Jump if greater (ZF=0 and SF=OF)
	case jg = 8
	/// Jump if lower or equal (i.e. not greater)
	static let jle = Self.jng
	/// Jump if greater or equal (i.e. not lower)
	static let jge = Self.jnl

	/// Jump if CX is zero
	case jcxz = 10
	/// Jump if ECX is zero
	case jecxz = 11
	/// Jump if RCX is zero
	case jrcxz = 12
}

nonisolated enum DisassemblyCondition: Int8 {
	case al
	case eq
	case ne
	case cs
	case cc
	case mi
	case pl
	case vs
	case vc
	case hi
	case ls
	case ge
	case lt
	case gt
	case le
	case never
}

nonisolated struct EFlagState: OptionSet {
	var rawValue: UInt8

	init(rawValue: UInt8) {
		self.rawValue = rawValue
	}
}

nonisolated extension EFlagState {
	//// The flag is tested
	static let tested = Self(rawValue: 0x01)
	//// The flag is modified
	static let modified = Self(rawValue: 0x02)
	//// The flag is reset
	static let reset = Self(rawValue: 0x04)
	//// The flag is set
	static let set = Self(rawValue: 0x08)
	//// Undefined behavior
	static let undefined = Self(rawValue: 0x10)
	//// Restore prior state
	static let prior = Self(rawValue: 0x20)
}

nonisolated struct EFlags {
	var of: EFlagState = []
	var sf: EFlagState = []
	var zf: EFlagState = []
	var af: EFlagState = []
	var pf: EFlagState = []
	var cf: EFlagState = []
	var tf: EFlagState = []
	var `if`: EFlagState = []
	var df: EFlagState = []
	var nt: EFlagState = []
	var rf: EFlagState = []
}

nonisolated struct DisassemblyInstructionFlags: OptionSet {
	var rawValue: UInt8

	init(rawValue: UInt8) {
		self.rawValue = rawValue
	}
}

nonisolated extension DisassemblyInstructionFlags {
	/// ARM specific. Set to 1 if 'S' flag.
	static let arm_s = Self(rawValue: 0x1)
	/// ARM specific: Set to 1 if writeback flag (!).
	static let arm_writeback = Self(rawValue: 0x2)
	/// ARM specific: Set to 1 if special flag (^).
	static let arm_special = Self(rawValue: 0x4)
	/// ARM specifig: Set to 1 if thumb instruction.
	static let arm_thumb = Self(rawValue: 0x8)
	/// The instruction may change the next instruction CPU mode.
	static let changeNextInstructionMode = Self(rawValue: 0x10)
	/// The instruction is illegal.
	static let illegal = Self(rawValue: 0x20)
}

nonisolated struct CpuMode: RawRepresentable {
	var rawValue: UInt8

	init(rawValue: UInt8) {
		self.rawValue = rawValue
	}
}

nonisolated struct RegisterClass: RawRepresentable {
	var rawValue: UInt8

	init(rawValue: UInt8) {
		self.rawValue = rawValue
	}
}

nonisolated struct RegisterIndex: RawRepresentable {
	var rawValue: UInt16

	init(rawValue: UInt16) {
		self.rawValue = rawValue
	}

	init(_ value: some FixedWidthInteger) {
		rawValue = UInt16(value)
	}

	init(_ value: some RawRepresentable<some FixedWidthInteger>) {
		rawValue = UInt16(value.rawValue)
	}

	static let invalid = Self(rawValue: 0)
}

/// The set of registers within a class.
nonisolated struct RegisterSet: OptionSet {
	var rawValue: UInt64

	init(rawValue: UInt64) {
		self.rawValue = rawValue
	}

	init(_ index: some FixedWidthInteger) {
		self.rawValue = UInt64(index)
	}
}

nonisolated public struct DisassemblyOperand {
	var description = ""
	var kind = DisassemblyOperandKind.none
	var access = OperandAccess.invalid
}

nonisolated enum DisassemblyOperandKind {
	/// Operand unused.
	case none
	/// An immediate operand.
	case constant(UInt64, ConstantFlags)
	/// Define a memory access in the form `[base + (index) * scale + displacement]`.
	/// - Parameters:
	///   - base: The base register
	///   - index: The index register
	///   - scale: The scale
	///   - displacement: The displacement
	case memory(base: RegisterIndex, index: RegisterIndex, scale: UInt8, displacement: Int64)
	/// A single register
	case register(RegisterIndex)
	/// A set of registers
	case registers(RegisterClass, RegisterSet)
	/// An unidentified type
	case other
}

nonisolated struct ConstantFlags: OptionSet {
	public var rawValue: UInt8

	public init(rawValue: UInt8) {
		self.rawValue = rawValue
	}
}

nonisolated extension ConstantFlags {
	/// This is an absolute value, such as for JMP address.
	static let absolute = Self(rawValue: 0x1)
	/// This is a relative value, such as for JMP address.
	static let relative = Self(rawValue: 0x2)
	/// This value is a float.
	static let floatingPoint = Self(rawValue: 0x4)
}

nonisolated struct OperandAccess: OptionSet {
	var rawValue: UInt8

	init(rawValue: UInt8) {
		self.rawValue = rawValue
	}
}

nonisolated extension OperandAccess {
	static let invalid: Self = []
	/// The operand is read.
	static let read = Self(rawValue: 0x1)
	/// The operand is written to.
	static let write = Self(rawValue: 0x2)
	/// The operand is read first, then modified.
	static let `inout`: Self = [.read, .write]
}
