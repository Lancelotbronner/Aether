import ArgumentParser
import Foundation
import AetherKit
import SwiftData

struct SymbolCommand: AsyncParsableCommand {
	static let configuration = CommandConfiguration(
		commandName: "symbol",
		abstract: "Work with symbols.",
		subcommands: [
			FetchCommand<SymbolModel>.self,
			CountCommand<SymbolModel>.self,
			DeleteCommand<SymbolModel>.self,
			InsertCommand<SymbolModel>.self,
			RawCommand.self,
		])
}

extension SymbolModel: FetchableModel {
	static let plural = "symbols"

	struct FetchOptions: ParsableArguments {
		@Option(help: "Filters to a specific program")
		var binary: String?

		@Option(help: "Search within the symbol name")
		var name: String?

		@Option(help: "Filter to a symbol at an address: decimal, 0x…, @…, off:<file offset> or a symbol name")
		var address: AddressArgument?

		@Option(help: "Filter on kind (0 unknown, 1 function, 2 data, 3 section)")
		var kind: SymbolKind?

		@Option(help: "Filter on type (0 unknown, 1 u8, 2 u16, 3 u32, 4 u64, 5 u128, 6 ascii, 7 utf8, 8 utf16, 9 ptr, 10 function)")
		var type: SymbolType?

		@Option(help: "Filter on binding (0 undefined, 1 local, 2 global, 3 weak, 4 external)")
		var binding: SymbolBinding?

		@Option(help: "Search within the decoded string value")
		var value: String?

		@Option(help: "Filter to symbols at least this many bytes long (decimal)")
		var minLength: UInt64?

		@Option(help: "Filter to symbols inside a section: its name or the <segment>,<section> identity fetch prints")
		var section: String?

		@Flag(help: "Filter to imported symbols")
		var imported: Bool = false

		@Flag(help: "Filter to exported symbols")
		var exported: Bool = false
	}

	static func apply(_ options: FetchOptions, to descriptor: inout FetchDescriptor<SymbolModel>, in modelContext: ModelContext) throws {
		let addressValue = try filterAddress(options.address, named: options.binary, in: modelContext)
		let sectionRange = try filterSection(options.section, named: options.binary, in: modelContext)
		let binary = options.binary.flatMap { filter in
			#Predicate<SymbolModel> { $0.binary.name == filter }
		} ?? .true
		let name = options.name.flatMap { filter in
			#Predicate<SymbolModel> { $0.name.localizedStandardContains(filter) }
		} ?? .true
		let address = addressValue.flatMap { filter in
			#Predicate<SymbolModel> { $0.address == filter }
		} ?? .true
		let kind = options.kind.flatMap { filter in
			#Predicate<SymbolModel> { $0.rawKind == filter.rawValue }
		} ?? .true
		let type = options.type.flatMap { filter in
			#Predicate<SymbolModel> { $0.rawType == filter.rawValue }
		} ?? .true
		let binding = options.binding.flatMap { filter in
			#Predicate<SymbolModel> { $0.rawBinding == filter.rawValue }
		} ?? .true
		let value = options.value.flatMap { filter in
			#Predicate<SymbolModel> { $0.stringValue.localizedStandardContains(filter) }
		} ?? .true
		let imported = options.imported ? #Predicate<SymbolModel> { $0.isImport } : .true
		let exported = options.exported ? #Predicate<SymbolModel> { $0.isExport } : .true
		// `--section` is a range over `address`, not a relationship hop: the
		// schema has no `SymbolModel` → `SectionModel` link, and the range is
		// resolved before the predicate is built. Two `UInt64` lets are captured
		// rather than the `Range` because the predicate compiler only ever sees
		// plain comparable values here.
		let inSection = sectionRange != nil
		let sectionLo = sectionRange?.lowerBound ?? 0
		let sectionHi = sectionRange?.upperBound ?? 0
		let section = inSection ? #Predicate<SymbolModel> { $0.address >= sectionLo && $0.address < sectionHi } : .true
		let minLength = options.minLength.flatMap { limit in
			#Predicate<SymbolModel> { $0.size >= limit }
		} ?? .true
		descriptor.predicate = #Predicate<SymbolModel> {
			binary.evaluate($0) && name.evaluate($0) && address.evaluate($0)
				&& kind.evaluate($0) && type.evaluate($0) && binding.evaluate($0)
				&& value.evaluate($0) && imported.evaluate($0) && exported.evaluate($0)
				&& section.evaluate($0) && minLength.evaluate($0)
		}
		descriptor.sortBy = [SortDescriptor(\SymbolModel.address)]
	}

	func fields() -> [RowField] {
		[
			head("name", name),
			at(hex(address)),
			field("size", size),
			field("kind", kind),
			field("type", type),
			field("binding", binding),
			field("import", isImport),
			field("export", isExport),
			field("identifier", identifier),
			field("value", stringValue),
			field("program", binary.name),
		]
	}

	static let demanglable = true

	/// A symbol row's mangled name is its `identifier`: `name` is what the loader
	/// chose to display, which for a string row is the string's text.
	var mangledName: String? {
		identifier.isEmpty ? nil : identifier
	}

	/// A symbol row has no `demangled` column to fill, so the sibling is
	/// appended after the stored fields — and only when a demangler actually
	/// changed the name, which is why `--demangle` over a Rust binary leaves
	/// every row byte-for-byte as it was printed before.
	func row(applying names: [String: String]) -> [RowField] {
		guard let mangled = mangledName, let demangled = names[mangled] else { return fields() }
		return fields() + [field("demangled", demangled)]
	}

	/// The same filters `apply` compiles into a `Predicate`, evaluated in
	/// Swift. `symbol raw` needs a row-by-row rule because a row produced by a
	/// fresh scan is not in the store, so no descriptor can reach it — and
	/// because both halves of that diff have to be filtered by one rule, or the
	/// difference they report is a filtering artefact rather than a real one.
	func matches(_ options: FetchOptions, address filter: UInt64?, section sectionRange: Range<UInt64>?) -> Bool {
		if let filter = options.binary, binary.name != filter {
			return false
		}
		if let filter = options.name, !name.localizedStandardContains(filter) {
			return false
		}
		if let filter, self.address != filter {
			return false
		}
		if let sectionRange, !sectionRange.contains(address) {
			return false
		}
		if let limit = options.minLength, size < limit {
			return false
		}
		if let filter = options.kind, kind != filter {
			return false
		}
		if let filter = options.type, type != filter {
			return false
		}
		if let filter = options.binding, binding != filter {
			return false
		}
		if let filter = options.value, !stringValue.localizedStandardContains(filter) {
			return false
		}
		if options.imported, !isImport {
			return false
		}
		if options.exported, !isExport {
			return false
		}
		return true
	}
}

extension SymbolModel: InsertableModel {
	static let singular = "symbol"

	struct InsertOptions: ParsableArguments {
		@Argument(help: "Name of the program to add a symbol to")
		var binary: String

		@Argument(help: "Symbol name")
		var name: String

		@Argument(help: "Address the symbol lives at: decimal, 0x…, @…, off:<file offset> or a symbol name")
		var address: AddressArgument

		@Option(help: "Size of the symbol in bytes (decimal)")
		var size: UInt64 = 1

		@Option(help: "Identifier the symbol is known by, for example a mangled name")
		var identifier: String = ""

		@Option(help: "Kind (0 unknown, 1 function, 2 data, 3 section)")
		var kind: SymbolKind = .unknown

		@Option(help: "Type (0 unknown, 1 u8, 2 u16, 3 u32, 4 u64, 5 u128, 6 ascii, 7 utf8, 8 utf16, 9 ptr, 10 function)")
		var type: SymbolType = .unknown

		@Option(help: "Binding (0 undefined, 1 local, 2 global, 3 weak, 4 external)")
		var binding: SymbolBinding = .undefined

		@Option(help: "Decoded string value")
		var value: String = ""

		@Flag(help: "Mark the symbol as imported")
		var imported: Bool = false

		@Flag(help: "Mark the symbol as exported")
		var exported: Bool = false
	}

	convenience init(options: InsertOptions, using modelContext: ModelContext) async throws {
		let binary = try requireBinary(named: options.binary, in: modelContext)
		let binaryName = binary.name
		let address = try resolveAddress(options.address, named: binaryName, in: modelContext)
		let identifier = options.identifier.isEmpty ? options.name : options.identifier
		var taken = FetchDescriptor<SymbolModel>()
		taken.predicate = #Predicate<SymbolModel> { $0.binary.name == binaryName && $0.address == address && $0.identifier == identifier }
		taken.fetchLimit = 1
		if try modelContext.fetch(taken).first != nil {
			throw InsertError.duplicate(kind: "symbol", key: "\(binaryName) \(identifier) @\(hex(address))")
		}

		self.init(in: binary)
		self.name = options.name
		self.identifier = identifier
		self.address = address
		self.size = options.size
		self.kind = options.kind
		self.type = options.type
		self.binding = options.binding
		self.stringValue = options.value
		self.isImport = options.imported
		self.isExport = options.exported
	}
}

struct RawCommand: AsyncParsableCommand {
	static let configuration = CommandConfiguration(
		commandName: "raw",
		abstract: "Re-parse a program's bytes in memory and report how the stored symbol rows differ from what the current loader would produce, writing nothing.")

	@OptionGroup var aether: AetherOptions

	@OptionGroup var modelOptions: SymbolModel.FetchOptions

	@OptionGroup var fetchOptions: FetchOptions

	@Flag(help: "Run procedure detection in the re-parse too: the detector appends its own `sub_`/`stub_` symbol rows, so without it those stored rows are counted as stale")
	var analyze = false

	@Flag(help: "Emit the report as one JSON object of counts")
	var json = false

	/// The pair that identifies a row on both sides of the diff. It is also
	/// the store's own identity for a row: `#Unique<SymbolModel>([\.binary,
	/// \.address, \.identifier])`, so a row that survives a re-parse is
	/// recognisable rather than just nearby.
	private func key(_ symbol: SymbolModel) -> String {
		"\(hex(symbol.address)):\(symbol.identifier)"
	}

	/// What the current loader would produce for the stored bytes.
	///
	/// The stored program cannot be re-scanned in place: `symbolize(in:)`
	/// refuses every range a symbol row already covers — `overlapsNamed` per
	/// element, `hasNamed` for the section-spanning row — and its "named" set
	/// is the whole `symbols` table, so scanning an already symbolized program
	/// yields *nothing* and every generated row reads as stale. Verified: on a
	/// store holding 7 generated rows, scanning that program gives 0 rows. A
	/// hand-built copy does not work either — the rows a model's initializer
	/// attaches (`SegmentModel(in:)` and friends) only stick to a model its
	/// store tracks; a detached `BinaryModel` reports 0 segments. So the scan
	/// runs against the stored `data` in an in-memory container, exactly as
	/// `inspect` does. `analyze` follows the flag rather than a fixed choice
	/// because detection is half of what an import runs, and the detector
	/// appends symbol rows of its own (`ProcedureDetector.swift:225-229`:
	/// `sub_<address>`, or `stub_<address>` for a dyld-call stub) — so leaving
	/// it out makes those stored rows look like drift. It defaults off because
	/// the parse is the part that can be re-run cheaply; see the measured cost
	/// of detection over the `big` corpus in CLI.md.
	private func rescan(_ program: BinaryModel, analyze: Bool) async throws -> [SymbolModel] {
		let container = try ModelContainer(
			for: .project,
			configurations: [ModelConfiguration(schema: .project, isStoredInMemoryOnly: true)]
		)
		let context = ModelContext(container)
		let probe = BinaryModel()
		probe.name = program.name
		probe.fileURL = program.fileURL
		// The stored bytes have to be re-copied, not passed through: SwiftData
		// hands back `@Attribute(.externalStorage)` data as a view into a
		// memory-mapped buffer whose start is not 8-byte aligned, and `machO(for:)`
		// performs aligned loads from `data.bytes` — passing the view through
		// traps with "load from misaligned raw pointer". Verified: this copy
		// is what makes the re-parse run at all.
		probe.data = program.data.subdata(in: 0..<program.data.count)
		context.insert(probe)
		_ = try await MachOLoader.load(probe, analyze: analyze)
		return Array(probe.symbols)
	}

	private func report(_ rows: [SymbolModel], titled title: String) {
		guard !rows.isEmpty else {
			print("\(title): 0")
			return
		}
		let offset = fetchOptions.offset ?? 0
		let shown = Array(rows.dropFirst(offset).prefix(fetchOptions.limit ?? rows.count))
		print("\(title): \(rows.count)" + (shown.count == rows.count ? "" : ", showing \(shown.count)"))
		for symbol in shown {
			print(symbol.describe())
		}
	}

	mutating func run() async throws {
		let context = try aether.backgroundContext()
		let program = try requireProgram(named: modelOptions.binary, in: context)
		let addressFilter = try filterAddress(modelOptions.address, named: modelOptions.binary, in: context)
		let sectionRange = try filterSection(modelOptions.section, named: modelOptions.binary, in: context)

		// One rule for both halves. The fresh rows are not in the store, so no
		// descriptor can reach them; filtering the stored half through the
		// descriptor as well would leave the diff comparing two different
		// filter implementations.
		func keep(_ symbol: SymbolModel) -> Bool {
			symbol.matches(modelOptions, address: addressFilter, section: sectionRange)
		}

		var storedQuery = FetchDescriptor<SymbolModel>()
		let programName = program.name
		storedQuery.predicate = #Predicate<SymbolModel> { $0.binary.name == programName }
		let stored = try context.fetch(storedQuery)
		let fresh = try await rescan(program, analyze: analyze)

		var storedRows: [String: SymbolModel] = [:]
		var storedKept = 0
		for symbol in stored where keep(symbol) {
			storedKept += 1
			storedRows[key(symbol)] = symbol
		}

		var freshKeys: [String: Bool] = [:]
		var missing: [SymbolModel] = []
		var changed: [SymbolModel] = []
		var freshKept = 0
		for symbol in fresh where keep(symbol) {
			freshKept += 1
			let id = key(symbol)
			freshKeys[id] = true
			guard let existing = storedRows[id] else {
				missing.append(symbol)
				continue
			}
			if existing.size != symbol.size || existing.type != symbol.type || existing.stringValue != symbol.stringValue {
				changed.append(symbol)
			}
		}

		var stale: [SymbolModel] = []
		for symbol in stored where keep(symbol) && freshKeys[key(symbol)] == nil {
			stale.append(symbol)
		}

		missing.sort { $0.address < $1.address }
		stale.sort { $0.address < $1.address }
		changed.sort { $0.address < $1.address }

		if json {
			print(jsonRow([
				field("program", program.name),
				field("analyze", analyze),
				field("fresh", freshKept),
				field("freshTotal", fresh.count),
				field("stored", storedKept),
				field("storedTotal", stored.count),
				field("missing", missing.count),
				field("stale", stale.count),
				field("changed", changed.count),
			]))
			return
		}

		// The kept counts are the ones the buckets were computed from; the
		// totals say how much the filters hid, so a clean report under a filter
		// cannot be mistaken for a clean report about the whole program.
		print("\(program.name): \(freshKept) of \(fresh.count) re-parsed rows, \(storedKept) of \(stored.count) stored rows")
		print("missing \(missing.count) stale \(stale.count) changed \(changed.count)")
		if !analyze {
			print("detection skipped — the detector appends its own `sub_`/`stub_` symbol rows, so those stored rows count as stale here; pass --analyze to include them")
		}
		report(missing, titled: "missing — what a re-parse would add")
		report(stale, titled: "stale — stored rows the current loader no longer produces")
		report(changed, titled: "changed — same address and name, different size/type/value")
	}
}
