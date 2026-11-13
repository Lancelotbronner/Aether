import ArgumentParser
import AetherKit
import SwiftData
import Foundation

struct EmptyOptions: ParsableArguments {}

/// Upper-case hexadecimal, matching the way addresses print elsewhere.
func hex(_ value: some BinaryInteger) -> String {
	String(value, radix: 16, uppercase: true)
}

enum InsertError: Error {
	case unknownBinary(String)
	case unknownSegment(name: String, binary: String)
	case unknownSymbol(name: String, binary: String)
	case duplicate(kind: String, key: String)
}

/// Resolve the program a subcommand was told to operate on.
func requireBinary(named name: String, in modelContext: ModelContext) throws -> BinaryModel {
	var descriptor = FetchDescriptor<BinaryModel>()
	descriptor.predicate = #Predicate<BinaryModel> { $0.name == name }
	descriptor.fetchLimit = 1
	guard let binary = try modelContext.fetch(descriptor).first else {
		throw InsertError.unknownBinary(name)
	}
	return binary
}

/// The program an address resolution answers for: the one `--binary` names,
/// or the document's only program when no name was given. A name or an
/// `off:` spelling has no meaning without one, so several programs make the
/// request ambiguous rather than guessing.
func requireProgram(named name: String?, in modelContext: ModelContext) throws -> BinaryModel {
	if let name {
		return try requireBinary(named: name, in: modelContext)
	}
	let programs = try modelContext.fetch(FetchDescriptor<BinaryModel>())
	switch programs.count {
	case 0:
		throw AddressError.noProgram
	case 1:
		return programs.first!
	default:
		throw AddressError.programs(names: programs.map { $0.name })
	}
}

/// One address in any notation: decimal, the `0x…` form, the `@…` form
/// `describe()` prints, `off:<n>` for a file offset, or a symbol name.
/// Addresses print as hex but were only ever accepted as decimal, which made
/// every address-taking argument a copy-paste hazard.
struct AddressArgument: ExpressibleByArgument {
	enum Notation {
		case virtual(UInt64)
		case offset(UInt64)
		case name(String)
	}

	var notation: Notation

	init?(argument: String) {
		guard !argument.isEmpty else { return nil }

		if argument.hasPrefix("off:") {
			guard let value = AddressArgument.number(String(argument.dropFirst(4))) else { return nil }
			notation = .offset(value)
			return
		}
		// A hex prefix that does not parse is a typo, and saying so beats
		// going to look for a symbol called `0x1000fe00g`.
		if argument.hasPrefix("0x") || argument.hasPrefix("0X") {
			guard let value = UInt64(argument.dropFirst(2), radix: 16) else { return nil }
			notation = .virtual(value)
			return
		}
		if argument.hasPrefix("@") {
			guard let value = UInt64(argument.dropFirst(), radix: 16) else { return nil }
			notation = .virtual(value)
			return
		}
		if let value = UInt64(argument, radix: 10) {
			notation = .virtual(value)
			return
		}
		// Anything else is a name, which is why a symbol whose name is all
		// digits cannot be selected by name.
		notation = .name(argument)
	}

	/// File offsets accept the same numeric spellings as a virtual address,
	/// minus `@` — that one is how `describe()` prints an address.
	private static func number(_ text: String) -> UInt64? {
		if text.hasPrefix("0x") || text.hasPrefix("0X") {
			return UInt64(text.dropFirst(2), radix: 16)
		}
		return UInt64(text, radix: 10)
	}
}

enum AddressError: LocalizedError {
	case noSymbol(name: String, program: String)
	case ambiguousSymbol(name: String, program: String, addresses: [String])
	case offsetNotInFile(offset: UInt64, program: String)
	case noProgram
	case programs(names: [String])

	var errorDescription: String? {
		switch self {
		case .noSymbol(let name, let program):
			return "No symbol named \(name) in \(program)"
		case .ambiguousSymbol(let name, let program, let addresses):
			return "\(name) resolves to several addresses in \(program): \(addresses.joined(separator: " ")) — pass an address instead"
		case .offsetNotInFile(let offset, let program):
			return "File offset \(hex(offset)) is not inside any segment of \(program)"
		case .noProgram:
			return "The project holds no program; import one first"
		case .programs(let names):
			return "Several programs in the project — pass --binary: \(names.joined(separator: ", "))"
		}
	}
}

/// Where a virtual address sits inside the file. The load commands pair each
/// segment's `fileoff` with its own `vmaddr`, so this is a segment-table lookup,
/// not the global `address - baseAddress` shift AetherKit's own byte helpers
/// still perform.
func fileOffset(of address: UInt64, in program: BinaryModel) -> UInt64? {
	guard let segment = program.segments.first(where: {
		$0.fileSize > 0 && address >= $0.address && address < $0.address + $0.fileSize
	}) else { return nil }
	return segment.fileOffset + (address - segment.address)
}

/// Inverse of `fileOffset(of:in:)`: where in the image a byte of the file sits.
/// A search finds its match by file offset and has to report the address an
/// `--address` filter would take, so the same segment table is walked the other
/// way instead of adding `baseAddress`.
func virtualAddress(of offset: UInt64, in program: BinaryModel) -> UInt64? {
	guard let segment = program.segments.first(where: {
		$0.fileSize > 0 && offset >= $0.fileOffset && offset < $0.fileOffset + $0.fileSize
	}) else { return nil }
	return segment.address + (offset - segment.fileOffset)
}

/// Turn an `<address|name>` argument into a virtual address. A name goes
/// through the symbol table and an `off:` through the segment table, because
/// a Mach-O image maps file offsets per segment — `fileoff`/`vmaddr` pairs
/// from the load commands — rather than by one global shift.
func resolveAddress(_ argument: AddressArgument, named binary: String?, in modelContext: ModelContext) throws -> UInt64 {
	switch argument.notation {
	case .virtual(let address):
		return address
	case .offset(let offset):
		let program = try requireProgram(named: binary, in: modelContext)
		guard let segment = program.segments.first(where: { $0.fileSize > 0 && offset >= $0.fileOffset && offset < $0.fileOffset + $0.fileSize }) else {
			throw AddressError.offsetNotInFile(offset: offset, program: program.name)
		}
		return segment.address + (offset - segment.fileOffset)
	case .name(let name):
		let program = try requireProgram(named: binary, in: modelContext)
		let needle = name
		var descriptor = FetchDescriptor<SymbolModel>()
		descriptor.predicate = #Predicate<SymbolModel> { $0.name == needle || $0.identifier == needle }
		// Rows at address 0 are imports: they have a name but no place.
		let rows = try modelContext.fetch(descriptor).filter { $0.binary.name == program.name && $0.address != 0 }
		guard !rows.isEmpty else {
			throw AddressError.noSymbol(name: name, program: program.name)
		}
		let addresses = Array(Set(rows.map { $0.address })).sorted()
		if addresses.count > 1 {
			throw AddressError.ambiguousSymbol(name: name, program: program.name, addresses: addresses.map { hex($0) })
		}
		return addresses.first!
	}
}

/// Filter shape: no address was asked for when the option is absent. Named
/// apart from `resolveAddress` because an optional argument would otherwise
/// make the two overloads ambiguous at every call site.
func filterAddress(_ argument: AddressArgument?, named binary: String?, in modelContext: ModelContext) throws -> UInt64? {
	guard let argument else { return nil }
	return try resolveAddress(argument, named: binary, in: modelContext)
}
