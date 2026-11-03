import Foundation
import MachO

/// Identifies function entry points and creates the `ProcedureModel` rows.
///
/// The simplest useful pass, run once the sections and symbol table exist:
/// 1. every symtab symbol already classified as a function,
/// 2. the image entry point,
/// 3. a raw postpattern scan of the executable sections, which recovers the
///    unnamed local functions the symbol table never mentions.
///
/// Every start address gets a `ProcedureModel`. Addresses found only by the
/// scan get a synthetic `sub_<address>` (`stub_<address>` for dyld call
/// thunks) symbol first, because a procedure is always anchored to a symbol.
/// Re-running the pass is safe: addresses that already have a procedure are
/// skipped.
public nonisolated struct ProcedureDetector {
	public init() {}
}

/// What a single `detect` pass saw and produced.
public nonisolated struct ProcedureDetectionReport {
	/// Executable sections the scan walked.
	public let codeSections: Int
	/// Distinct entry points the pass knows about: symtab symbols, the image
	/// entry point, and every postpattern hit.
	public let entryPoints: Int
	/// Entry points that had no symbol and got a synthesized one.
	public let synthesized: Int
	/// `ProcedureModel` rows this pass appended.
	public let created: Int

	public var summary: String {
		"ProcedureDetector: \(codeSections) code sections, \(entryPoints) entry points, "
		+ "\(synthesized) synthesized symbols, \(created) procedures"
	}
}

public nonisolated extension ProcedureDetector {
	/// AArch64 pre-indexed `stp Rt, Rt2, [sp, #-imm]!` — the frame pair landing
	/// on the stack pointer is the entry signature clang/rustc emit for every
	/// non-leaf function, whatever registers it uses.
	///
	/// Signed-offset STP layout: `opc(31-30) 101001(29-24) 00(25-24) imm(23)
	/// V(22) imm7(21-15) Rt2(14-10) Rn(9-5) Rt(4-0)`. Measured encodings:
	/// `stp x29,x30,[sp,#-0x10]!` = A9BF7BFD, `stp x20,x19,[sp,#-0x10]!` =
	/// A9BF4FF4, `stp x20,x19,[sp]` = A9004FF4. Bit 23 pins the pre-index form
	/// and bit 22 is the vector flag, so the epilogue load
	/// (`ldp x29,x30,[sp],#0x10` = A8C17BFD) and the plain store
	/// (`stp x29,x30,[sp,#0x10]` = A9017BFD) stay out of the match.
	private static let framePairMask: UInt32 = 0xFCC0_03E0
	private static let framePairPattern: UInt32 = 0xA880_03E0

	/// `str x30, [sp, #-imm]!` — the link register saved on its own. The
	/// pre-index offset is a raw 9-bit signed byte count in bits 20-12:
	/// `#-0x8` = F81F8FFE, `#-0x10` = F81F0FFE, `#-0x100` = F8100FFE,
	/// `#+0x8` = F8008FFE. Bit 24 distinguishes pre-index from the plain
	/// `str x30, [sp]` (F90003FE), which is not an entry point.
	private static let linkStoreMask: UInt32 = 0xFD00_03FF
	private static let linkStorePattern: UInt32 = 0xF800_03FE

	/// `sub sp, sp, #imm`, including the shifted form `#imm, lsl #6k`.
	/// `sub sp, sp, #0x30` = D100C3FF, `sub sp, sp, #0x1, lsl #12` = D14007FF.
	private static let stackAdjustMask: UInt32 = 0xFD00_03FF
	private static let stackAdjustPattern: UInt32 = 0xD100_03FF

	/// Guard instructions clang emits as the very first instruction of an entry
	/// point: `bti c` = D503245F, `pacibsp` = D503237F.
	private static let bti: UInt32 = 0xD503_245F
	private static let pacibsp: UInt32 = 0xD503_237F

	/// Mach-O call thunk: `adrp x16, page` / `ldr x16, [x16, #off]` / `br x16`.
	/// `ldr x16, [x16, #0x8]` = F9400610, `br x16` = D61F0200. BR keeps bit 25
	/// and puts its register in bits 9-5, so the mask pins x16.
	private static let stubLoadMask: UInt32 = 0xFD00_03FF
	private static let stubLoadPattern: UInt32 = 0xF900_0210
	private static let stubBranchMask: UInt32 = 0xFE1F_03E0
	private static let stubBranchPattern: UInt32 = 0xD61F_0200
	private static let stubThunkWidth = 12

	/// x86-64 `push rbp` / `mov rbp, rsp`
	private static let x86Prologue: [UInt8] = [0x55, 0x48, 0x89, 0xE5]

	/// A detected entry point that has no symbol yet.
	private struct Synthesized {
		let address: UInt64
		let stackSize: Int
		let isStub: Bool
	}

	/// Creates the procedures and reports what the pass saw.
	func detect(in model: BinaryModel) -> ProcedureDetectionReport {
		// Entry points, deduped by address so a symtab symbol and a postpattern
		// hit at the same address produce one procedure. Value = frame size
		// where the prologue reveals one.
		var known: [UInt64: Int] = [:]
		for symbol in model.symbols where symbol.kind == .function && symbol.address != 0 {
			known[symbol.address] = 0
		}
		if model.entryPoint != 0 {
			known[model.entryPoint] = 0
		}

		var synthesized: [Synthesized] = []

		// Record an entry point. A hit that knows a frame size upgrades an
		// address that only a symbol or a guard instruction put on the map.
		func note(_ address: UInt64, stackSize: Int, isStub: Bool) {
			if known[address] == nil {
				known[address] = stackSize
				synthesized.append(Synthesized(address: address, stackSize: stackSize, isStub: isStub))
			} else if known[address] == 0 && stackSize != 0 {
				known[address] = stackSize
			}
		}

		var codeSections = 0

		for section in model.sections where section.containsCode {
			codeSections += 1
			let size = Int(section.size)
			let offset = Int(section.offset)
			guard size >= 4, offset >= 0, offset + size <= model.data.count else { continue }
			let data = model.data

			switch model.architecture {
			case .arm64, .appleSilicon, .arm64e:
				// Instructions are stored in the image's byte order, so the
				// encodings below are read as native little-endian words.
				data.withUnsafeBytes { buffer in
					if section.name.lowercased().contains("stub") {
						// dyld call thunks are fixed-width blocks: scan them
						// block by block rather than instruction by instruction.
						for block in 0..<(size / Self.stubThunkWidth) {
							let base = offset + block * Self.stubThunkWidth
							var load = buffer.loadUnaligned(fromByteOffset: base + 4, as: UInt32.self)
							var branch = buffer.loadUnaligned(fromByteOffset: base + 8, as: UInt32.self)
							if model.endian == .big {
								load = load.byteSwapped
								branch = branch.byteSwapped
							}
							if load & Self.stubLoadMask != Self.stubLoadPattern { continue }
							if branch & Self.stubBranchMask != Self.stubBranchPattern { continue }

							note(section.address + UInt64(block * Self.stubThunkWidth), stackSize: 0, isStub: true)
						}
					} else {
						for i in 0..<(size / 4) {
							var word = buffer.loadUnaligned(fromByteOffset: offset + i * 4, as: UInt32.self)
							if model.endian == .big { word = word.byteSwapped }

							if word == Self.bti || word == Self.pacibsp {
								note(section.address + UInt64(i * 4), stackSize: 0, isStub: false)
								continue
							}

							let stackSize: Int

							if word & Self.framePairMask == Self.framePairPattern {
								// imm7 is the scaled index: a pre-indexed store of
								// the frame pair *is* the frame allocation.
								let imm7 = Int((word >> 15) & 0x7F)
								let signed = imm7 & 0x40 != 0 ? imm7 - 128 : imm7
								stackSize = abs(signed) * 8
							} else if word & Self.linkStoreMask == Self.linkStorePattern {
								// Pre-index `str` carries the offset as a raw 9-bit
								// signed byte count in bits 20-12. Only stores below
								// sp allocate a frame; a positive offset is a spill
								// inside a body, not a prologue.
								let imm9 = Int((word >> 12) & 0x1FF)
								if imm9 & 0x100 == 0 { continue }
								stackSize = 512 - imm9
							} else if word & Self.stackAdjustMask == Self.stackAdjustPattern {
								let imm12 = Int((word >> 10) & 0xFFF)
								let shift = Int((word >> 21) & 3) * 6
								stackSize = imm12 << shift
							} else {
								continue
							}

							note(section.address + UInt64(i * 4), stackSize: stackSize, isStub: false)
						}
					}
				}
			case .x86_64, .i386:
				for i in 0..<(size - 3) {
					let base = offset + i
					if data[base] != Self.x86Prologue[0] || data[base + 1] != Self.x86Prologue[1]
					|| data[base + 2] != Self.x86Prologue[2] || data[base + 3] != Self.x86Prologue[3] { continue }

					let address = section.address + UInt64(i)
					if known[address] != nil { continue }
					known[address] = 0
					synthesized.append(Synthesized(address: address, stackSize: 0, isStub: false))
				}
			default:
				break
			}
		}

		// The entry point is a function start even when the symbol table names
		// nobody there (`LC_MAIN` gives only an offset), and a procedure needs a
		// symbol to hang off — so give the entry point one. The postpattern scan
		// may already have synthesized it, in which case there is nothing to do.
		if model.entryPoint != 0
		&& !synthesized.contains(where: { $0.address == model.entryPoint })
		&& !model.symbols.contains(where: { $0.kind == .function && $0.address == model.entryPoint }) {
			synthesized.append(Synthesized(address: model.entryPoint, stackSize: known[model.entryPoint] ?? 0, isStub: false))
		}

		// A synthesized function runs to the next entry point in the same
		// section; the last one in a section has no upper bound, so it keeps
		// the default size rather than a fabricated one.
		var sizeOf: [UInt64: UInt64] = [:]
		for section in model.sections {
			let starts = known.keys.filter { section.contains(address: $0) }.sorted()
			for (i, address) in starts.enumerated() where i + 1 < starts.count {
				sizeOf[address] = starts[i + 1] - address
			}
		}

		var created = 0

		for entry in synthesized {
			let symbol = SymbolModel(in: model)
			symbol.address = entry.address
			symbol.name = entry.isStub
				? String(format: "stub_%llX", entry.address)
				: String(format: "sub_%llX", entry.address)
			symbol.identifier = symbol.name
			symbol.kind = .function
			symbol.type = .function
			symbol.binding = .local
			symbol.size = sizeOf[entry.address] ?? 0
			symbol.refresh()
			model.symbols.append(symbol)

			let procedure = ProcedureModel(is: symbol, in: model)
			procedure.stackSize = entry.stackSize
			model.procedures.append(procedure)
			created += 1
		}

		// Idempotence: symbols that already have a procedure are left alone,
		// including the ones synthesized above.
		let existing = Set(model.procedures.map { $0.symbol.persistentModelID })
		for symbol in model.symbols where symbol.kind == .function && symbol.address != 0 {
			if existing.contains(symbol.persistentModelID) { continue }
			let procedure = ProcedureModel(is: symbol, in: model)
			procedure.stackSize = known[symbol.address] ?? 0
			model.procedures.append(procedure)
			created += 1
		}

		return ProcedureDetectionReport(
			codeSections: codeSections,
			entryPoints: known.count,
			synthesized: synthesized.count,
			created: created
		)
	}
}
