import Foundation
import SwiftData
import Testing
import AetherKit

private func probeBinary(architecture: Architecture, code: [UInt8], entryPoint: UInt64 = 0) throws -> BinaryModel {
	let container = try ModelContainer(for: Schema.project)
	let context = ModelContext(container)

	let binary = BinaryModel()
	binary.name = "probe"
	binary.architecture = architecture
	binary.baseAddress = 0x1000
	binary.entryPoint = entryPoint
	binary.data = Data(code)

	let segment = SegmentModel(in: binary)
	segment.name = "__TEXT"
	segment.address = 0x1000
	segment.size = UInt64(code.count)
	segment.fileOffset = 0
	segment.fileSize = UInt64(code.count)
	segment.initProtection = 4
	binary.segments.append(segment)

	let section = SectionModel(in: segment, of: binary)
	section.name = "__text"
	section.segmentName = "__TEXT"
	section.address = 0x1000
	section.size = UInt64(code.count)
	section.offset = 0
	section.flags = 0x8000_0400
	segment.sections.append(section)
	binary.sections.append(section)

	try context.save()
	return binary
}

@Test("arm64 prologue scan recovers unnamed functions and ignores the epilogue load")
func arm64PrologueScan() throws {
	// Machine code is stored in the image's byte order, so the encodings
	// appear little-endian on arm64: `stp x29, x30, [sp, #-16]` is A9BF7BFD,
	// which clang writes as FD 7B BF A9.
	let code: [UInt8] = [
		0xFD, 0x7B, 0xBF, 0xA9,  // stp x29, x30, [sp, #-0x10]!  @0x1000
		0xFF, 0x43, 0x00, 0x91,  // add sp, sp, #0x10
		0xFD, 0x7B, 0x41, 0xA9,  // ldp x29, x30, [sp], #0x10   @0x1008 — epilogue, not a prologue
		0xF4, 0x4F, 0xBF, 0xA9,  // stp x20, x19, [sp, #-0x10]! @0x100C — generic frame pair
		0xFD, 0x7B, 0x02, 0xA9,  // stp x29, x30, [sp, #0x10]   @0x1010 — not pre-indexed
		0xC0, 0x03, 0x5F, 0xD6,  // ret                         @0x1014
	]
	let binary = try probeBinary(architecture: .arm64, code: code)

	let report = ProcedureDetector().detect(in: binary)
	#expect(report.created == 2)
	#expect(report.codeSections == 1)
	#expect(report.synthesized == 2)
	#expect(report.entryPoints == 2)

	let addresses = binary.procedures.map { $0.symbol.address }.sorted()
	#expect(addresses == [0x1000, 0x100C])
	#expect(binary.procedures.first { $0.symbol.address == 0x1000 }?.stackSize == 16)
	#expect(binary.procedures.first { $0.symbol.address == 0x100C }?.stackSize == 16)

	let names = binary.symbols.filter { $0.kind == .function }.map { $0.name }.sorted()
	#expect(names == ["sub_1000", "sub_100C"])
	// Each synthetic function ends where the next entry point begins.
	#expect(binary.symbols.first { $0.address == 0x1000 }?.size == 12)
}

@Test("sub sp, sp, #imm is an entry point and its immediate is the frame size")
func stackAdjustPostpattern() throws {
	let code: [UInt8] = [
		0xFF, 0xC3, 0x00, 0xD1,  // sub sp, sp, #0x30            @0x1000 -> frame 48
		0xC0, 0x03, 0x5F, 0xD6,  // ret                          @0x1004
		0xFF, 0x07, 0x40, 0xD1,  // sub sp, sp, #0x1, lsl #12    @0x1008 -> frame 4096
		0xC0, 0x03, 0x5F, 0xD6,  // ret                          @0x100C
	]
	let binary = try probeBinary(architecture: .arm64, code: code)

	let report = ProcedureDetector().detect(in: binary)
	#expect(report.created == 2)
	#expect(report.synthesized == 2)

	#expect(binary.procedures.first { $0.symbol.address == 0x1000 }?.stackSize == 48)
	#expect(binary.procedures.first { $0.symbol.address == 0x1008 }?.stackSize == 4096)
	// The second entry point is the last one in the section, so it has no bound.
	#expect(binary.symbols.first { $0.address == 0x1000 }?.size == 8)
	#expect(binary.symbols.first { $0.address == 0x1008 }?.size == 0)
}

@Test("bti and pacibsp mark entry points on their own")
func guardInstructionPostpatterns() throws {
	let code: [UInt8] = [
		0x5F, 0x24, 0x03, 0xD5,  // bti c                        @0x1000
		0xC0, 0x03, 0x5F, 0xD6,  // ret                          @0x1004
		0x7F, 0x23, 0x03, 0xD5,  // pacibsp                      @0x1008
		0xC0, 0x03, 0x5F, 0xD6,  // ret                          @0x100C
		0xFE, 0x8F, 0x1F, 0xF8,  // str x30, [sp, #-0x8]!        @0x1010 -> frame 8
		0xC0, 0x03, 0x5F, 0xD6,  // ret                          @0x1014
		0xFE, 0x0F, 0x1F, 0xF8,  // str x30, [sp, #-0x10]!       @0x1018 -> frame 16
		0xC0, 0x03, 0x5F, 0xD6,  // ret                          @0x101C
		0xFE, 0x0F, 0x10, 0xF8,  // str x30, [sp, #-0x100]!      @0x1020 -> frame 256
		0xC0, 0x03, 0x5F, 0xD6,  // ret                          @0x1024
		0xFE, 0x8F, 0x00, 0xF8,  // str x30, [sp, #0x8]!         @0x1028 — a spill, not a frame
		0xFE, 0x03, 0x00, 0xF9,  // str x30, [sp]                @0x102C — no pre-index
		0xC0, 0x03, 0x5F, 0xD6,  // ret                          @0x1030
	]
	let binary = try probeBinary(architecture: .arm64e, code: code)

	let report = ProcedureDetector().detect(in: binary)
	#expect(report.created == 5)
	#expect(report.synthesized == 5)

	let addresses = binary.procedures.map { $0.symbol.address }.sorted()
	#expect(addresses == [0x1000, 0x1008, 0x1010, 0x1018, 0x1020])
	for (address, frame) in [(0x1010, 8), (0x1018, 16), (0x1020, 256)] {
		#expect(binary.procedures.first { $0.symbol.address == address }?.stackSize == frame)
	}
	#expect(binary.symbols.filter { $0.kind == .function }.map { $0.name }.sorted()
		== ["sub_1000", "sub_1008", "sub_1010", "sub_1018", "sub_1020"])
}

@Test("dyld stub thunks become entry points named stub_<address>")
func stubThunkScan() throws {
	// Two 12-byte adrp/ldr/br thunks, exactly what clang puts in __TEXT,__stubs.
	let code: [UInt8] = [
		0x10, 0x00, 0x00, 0x90,  // adrp x16, 0        @0x1000
		0x10, 0x06, 0x40, 0xF9,  // ldr  x16, [x16, #0x8]
		0x00, 0x02, 0x1F, 0xD6,  // br   x16
		0xD0, 0x0E, 0x00, 0xF0,  // adrp x16, 0x1db000 @0x100C
		0x10, 0x0A, 0x40, 0xF9,  // ldr  x16, [x16, #0x10]
		0x00, 0x02, 0x1F, 0xD6,  // br   x16
	]
	let binary = try probeBinary(architecture: .arm64, code: code)
	binary.sections[0].name = "__stubs"

	let report = ProcedureDetector().detect(in: binary)
	#expect(report.created == 2)
	#expect(report.synthesized == 2)
	#expect(report.entryPoints == 2)

	let names = binary.symbols.filter { $0.kind == .function }.map { $0.name }.sorted()
	#expect(names == ["stub_1000", "stub_100C"])
	#expect(binary.procedures.map { $0.stackSize } == [0, 0])
	// A thunk runs until the next thunk.
	#expect(binary.symbols.first { $0.address == 0x1000 }?.size == 12)
	#expect(binary.symbols.first { $0.address == 0x100C }?.size == 0)
}

@Test("the report summary describes the pass")
func reportSummary() throws {
	let binary = try probeBinary(architecture: .arm64, code: [0xF4, 0x4F, 0xBF, 0xA9, 0xC0, 0x03, 0x5F, 0xD6])
	let report = ProcedureDetector().detect(in: binary)
	#expect(report.summary == "ProcedureDetector: 1 code sections, 1 entry points, 1 synthesized symbols, 1 procedures")
}

@Test("symtab function symbols get procedures without a duplicate symbol")
func symtabSeededProcedures() throws {
	let code: [UInt8] = [0xFD, 0x7B, 0xBF, 0xA9, 0xC0, 0x03, 0x5F, 0xD6]
	let binary = try probeBinary(architecture: .arm64, code: code, entryPoint: 0x1000)

	let symbol = SymbolModel(in: binary)
	symbol.address = 0x1000
	symbol.name = "main"
	symbol.identifier = "main"
	symbol.kind = .function
	symbol.type = .function
	symbol.binding = .global
	binary.symbols.append(symbol)

	let report = ProcedureDetector().detect(in: binary)
	#expect(report.created == 1)
	#expect(report.synthesized == 0)
	#expect(binary.procedures.count == 1)
	#expect(binary.procedures.first?.symbol.name == "main")
	// The prologue at `main` still contributes its frame size.
	#expect(binary.procedures.first?.stackSize == 16)
	#expect(binary.symbols.filter { $0.kind == .function }.count == 1)
}

@Test("re-running the pass does not duplicate procedures")
func detectorIsIdempotent() throws {
	let code: [UInt8] = [0xFD, 0x7B, 0xBF, 0xA9, 0xF4, 0x4F, 0xBF, 0xA9]
	let binary = try probeBinary(architecture: .arm64e, code: code)

	let first = ProcedureDetector().detect(in: binary)
	let second = ProcedureDetector().detect(in: binary)
	#expect(first.created == 2)
	#expect(second.created == 0)
	#expect(second.synthesized == 0)
	#expect(binary.procedures.count == 2)
	#expect(binary.symbols.count == 2)
}

@Test("x86-64 push rbp / mov rbp, rsp is a function entry")
func x86PrologueScan() throws {
	// prologues at byte offsets 0 and 7 of the section
	let code: [UInt8] = [0x55, 0x48, 0x89, 0xE5, 0x48, 0x8B, 0x05, 0x55, 0x48, 0x89, 0xE5, 0xC3]
	let binary = try probeBinary(architecture: .x86_64, code: code)

	let report = ProcedureDetector().detect(in: binary)
	#expect(report.created == 2)
	#expect(binary.procedures.map { $0.symbol.address }.sorted() == [0x1000, 0x1007])
}

@Test("data sections are not scanned for prologues")
func nonExecutableSectionsAreSkipped() throws {
	let binary = try probeBinary(architecture: .arm64, code: [0xA9, 0xBF, 0x7B, 0xFD, 0xA9, 0xBF, 0x7B, 0xFD])
	binary.sections[0].flags = 0
	binary.sections[0].name = "__data"

	let report = ProcedureDetector().detect(in: binary)
	#expect(report.created == 0)
	#expect(report.codeSections == 0)
}

@Test("the entry point is a procedure even when the symbol table names nobody there")
func entryPointWithoutASymbol() throws {
	// `sub sp, sp, #0x30` at the entry point: the prologue hit is already in
	// `known` because the entry point was seeded, so only the entry check
	// synthesizes the symbol — exactly one, not one per discovery.
	let code: [UInt8] = [0xFF, 0xC3, 0x00, 0xD1, 0xC0, 0x03, 0x5F, 0xD6]
	let binary = try probeBinary(architecture: .arm64, code: code, entryPoint: 0x1000)

	let report = ProcedureDetector().detect(in: binary)
	#expect(report.created == 1)
	#expect(report.synthesized == 1)
	#expect(binary.procedures.count == 1)
	#expect(binary.symbols.filter { $0.kind == .function }.map { $0.name } == ["sub_1000"])
	// The seeded entry point keeps the frame size the prologue reported.
	#expect(binary.procedures.first?.stackSize == 48)

	// Second pass: the entry point now has a symbol, so nothing is repeated.
	let second = ProcedureDetector().detect(in: binary)
	#expect(second.created == 0)
	#expect(second.synthesized == 0)
	#expect(binary.symbols.count == 1)
	#expect(binary.procedures.count == 1)
}

@Test("an entry point with no recognizable prologue still gets a procedure")
func entryPointWithNoPrologueHit() throws {
	// `nop` (D503201F) then `ret` — no pattern matches, but LC_MAIN says the
	// image starts here.
	let code: [UInt8] = [0x1F, 0x20, 0x03, 0xD5, 0xC0, 0x03, 0x5F, 0xD6]
	let binary = try probeBinary(architecture: .arm64, code: code, entryPoint: 0x1000)

	let report = ProcedureDetector().detect(in: binary)
	#expect(report.created == 1)
	#expect(report.synthesized == 1)
	#expect(report.entryPoints == 1)
	#expect(binary.procedures.first?.symbol.address == 0x1000)
	#expect(binary.procedures.first?.stackSize == 0)
}
