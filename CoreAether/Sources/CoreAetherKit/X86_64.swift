import CoreAether

struct X86_64 : ~Escapable {
	var register = x86_64_register()
	var context = x86_64_context()
	var assembly = ""
	var data: RawSpan
	let context: DisassemblerContext

	@_lifetime(copy data)
	init(
		_ data: RawSpan,
		context: DisassemblerContext
	) {
		self.data = data
		self.context = context
	}

	mutating func token<T: BitwiseCopyable>(_ type: T.Type = T.self) throws(DisassemblyError) -> T {
		guard data.byteCount >= MemoryLayout<T>.size else {
			throw DisassemblyError.unexpectedEndOfFile
		}
		let value = data.unsafeLoadUnaligned(as: T.self)
		data = data.extracting(droppingFirst: MemoryLayout<T>.size)
		return value
	}
}

//MARK: - Tables

extension X86_64 {
	mutating func instruction() throws(DisassemblyError) {

	}

	mutating func Reg8() throws(DisassemblyError) -> UInt8 {
		switch true {
		case !context.rexprefix:
			let reg8 = try token(x86_64_modrm.self).reg8
			assembly += format(r8: reg8)
			return reg8
		case context.rexprefix && !context.rexRprefix:
			let reg8 = try token(x86_64_modrm.self).reg8
			assembly += format(r8x0: reg8)
			return reg8
		case context.rexprefix && context.rexRprefix:
			let reg8 = try token(x86_64_modrm.self).reg8
			assembly += format(r8x1: reg8)
			return reg8
		default:
			throw DisassemblyError.incompletePattern
		}
	}
}

//MARK: - Formatting

extension X86_64 {
	func format(r8 i: UInt8) -> String {
		["AL", "CL", "DL", "BL", "AH", "CH", "DH", "BH"][Int(i), defaultValue: i.description]
	}

	func format(r8x0 i: UInt8) -> String {
		["AL", "CL", "DL", "BL", "SPL", "BPL", "SIL", "DIL"][Int(i), defaultValue: i.description]
	}

	func format(r8x1 i: UInt8) -> String {
		["R8B", "R9B", "R10B", "R11B", "R12B", "R13B", "R14B", "R15B"][Int(i), defaultValue: i.description]
	}
}
