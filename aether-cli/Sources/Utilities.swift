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

enum SectionError: LocalizedError {
	case noSection(name: String, program: String)
	case ambiguousSection(name: String, program: String, sections: [String])

	var errorDescription: String? {
		switch self {
		case .noSection(let name, let program):
			return "No section named \(name) in \(program)"
		case .ambiguousSection(let name, let program, let sections):
			return "\(name) is several sections in \(program): \(sections.joined(separator: " ")) — spell it as <segment>,<section> instead"
		}
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

/// A section named as a filter: the range of addresses it covers. `--section`
/// cannot be a stored-field comparison because a `SymbolModel` has no
/// relationship to a `SectionModel` — sections are their own group precisely
/// so that a symbol can be scoped to one by address instead. Exact matching,
/// like every other name that selects a place rather than searching a label,
/// and both spellings are accepted: the bare section name and the
/// `<segment>,<section>` identity `describe()` prints.
func filterSection(_ name: String?, named binary: String?, in modelContext: ModelContext) throws -> Range<UInt64>? {
	guard let name else { return nil }
	let program = try requireProgram(named: binary, in: modelContext)

	let needle = name
	var descriptor = FetchDescriptor<SectionModel>()
	if name.contains(",") {
		let parts = name.components(separatedBy: ",")
		guard parts.count == 2, !parts.first!.isEmpty, !parts.last!.isEmpty else {
			throw SectionError.noSection(name: name, program: program.name)
		}
		let segmentName = parts.first!
		let sectionName = parts.last!
		descriptor.predicate = #Predicate<SectionModel> { $0.segmentName == segmentName && $0.name == sectionName }
	} else {
		descriptor.predicate = #Predicate<SectionModel> { $0.name == needle }
	}
	// Same-name sections in two segments of the same program, or of several
	// programs, are a real ambiguity: guess one and scope the query to the
	// wrong range.
	let rows = try modelContext.fetch(descriptor).filter { $0.binary.name == program.name }
	guard !rows.isEmpty else {
		throw SectionError.noSection(name: name, program: program.name)
	}
	let starts = Array(Set(rows.map { $0.address })).sorted()
	guard starts.count == 1 else {
		throw SectionError.ambiguousSection(
			name: name,
			program: program.name,
			sections: rows.map { $0.fullName }
		)
	}
	let section = rows.first { $0.address == starts.first! }!
	return section.address..<(section.address + section.size)
}

enum DemangleError: LocalizedError {
	case unsupported(plural: String)

	var errorDescription: String? {
		switch self {
		case .unsupported(let plural):
			return "Nothing to demangle in \(plural): these rows carry no symbol name"
		}
	}
}

/// The high-level name for a page of rows, asked from the toolchain's own
/// demanglers rather than from a mangling grammar written in Swift — the
/// grammar is versioned, while these are the same tools that read the binary.
/// `SymbolModel.displayName` has called itself a placeholder for this since
/// the schema was written.
///
/// Which tool a name goes to is decided by prefix: Swift's mangled names carry
/// `_$` (the bare `$s…` spelling appears too), C++ Itanium names carry `_Z`
/// or — the way `nm` prints them on macOS — `__Z`. Names are passed over
/// verbatim, with no underscore stripped: `c++filt` accepts the double-underscore
/// spelling directly, and stripping would quietly turn a plain `_main` into
/// `main`.
///
/// The whole page goes through one process per tool: both read names on stdin
/// and print one line per name in order, so 8903 rows cost two processes
/// (measured: 300 names through `c++filt` in 0.007 s — process start-up is
/// the only cost worth paying). A name the tool does not recognise comes back
/// unchanged, which is the raw name rather than an error: rustc's current
/// V0 mangling (`__R…`, which is what the `rg` store holds) is spoken by
/// neither tool on this machine, and a pass-through row is not a difference.
func demangledNames(_ names: [String]) -> [String: String] {
	var out: [String: String] = [:]
	for (executable, arguments, batch) in [
		("/usr/bin/swift", ["demangle"], names.filter { $0.hasPrefix("_$") || $0.hasPrefix("$") }),
		("/usr/bin/c++filt", [], names.filter { $0.hasPrefix("__Z") || $0.hasPrefix("_Z") }),
	] {
		guard !batch.isEmpty else { continue }
		guard let lines = runDemangler(executable, arguments: arguments, names: batch) else { continue }
		guard lines.count == batch.count else {
			// Rows are paired by position, so a tool that changes the framing
			// is not applied at all rather than guessed at row by row.
			warning("\(executable) printed \(lines.count) lines for \(batch.count) names")
			continue
		}
		for (name, line) in zip(batch, lines) where line != name {
			out[name] = line
		}
	}
	return out
}

/// One batch through an external demangler. `Process` cannot hand a child a
/// string, and a name given as an argument would be read as a *file name* by
/// both tools, so the names are staged in a temp file on stdin.
private func runDemangler(_ executable: String, arguments: [String], names: [String]) -> [String]? {
	guard FileManager.default.isExecutableFile(atPath: executable) else {
		warning("no demangler at \(executable)")
		return nil
	}
	let url = FileManager.default.temporaryDirectory
		.appending(path: "aether-demangle-\(UUID().uuidString).txt")
	guard FileManager.default.createFile(atPath: url.path, contents: Data((names.joined(separator: "\n") + "\n").utf8)) else {
		warning("cannot stage names for \(executable)")
		return nil
	}
	defer { try? FileManager.default.removeItem(at: url) }

	let process = Process()
	process.executableURL = URL(fileURLWithPath: executable)
	process.arguments = arguments
	guard let stdin = try? FileHandle(forReadingFrom: url) else {
		warning("cannot read the staged names back for \(executable)")
		return nil
	}
	process.standardInput = stdin
	let stdout = Pipe()
	process.standardOutput = stdout
	do {
		try process.run()
	} catch {
		warning("cannot run \(executable): \(error)")
		return nil
	}
	let data = stdout.fileHandleForReading.readDataToEndOfFile()
	process.waitUntilExit()
	guard process.terminationStatus == 0 else {
		warning("\(executable) did not exit cleanly")
		return nil
	}
	guard let text = String(data: data, encoding: .utf8) else {
		warning("\(executable) printed text that is not UTF-8")
		return nil
	}
	var lines = text.components(separatedBy: "\n")
	if lines.last == "" {
		lines.removeLast()
	}
	return lines
}

/// A demangler that is missing or failed earns one line on stderr: the rows
/// still print, so the run is not a failure, but without this a bare
/// `demangled 0 of N rows` reads as "these names are not mangled".
private func warning(_ text: String) {
	FileHandle.standardError.write(Data((text + "\n").utf8))
}
