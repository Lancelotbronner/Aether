import ArgumentParser
import SwiftData

protocol FetchableModel: PersistentModel {
	associatedtype FetchOptions: ParsableArguments = EmptyOptions

	static var plural: String { get }

	func describe() -> String

	/// The row as fields rather than as text, which is what `--json` prints and
	/// what `describe()` renders. One source for both, so a field cannot be
	/// added to a row and forgotten in the other view.
	func fields() -> [RowField]

	/// Whether `--demangle` means anything for this row type, and the name on
	/// the row the demangler should be asked about. The flag lives on `fetch`
	/// rather than in the shared filter group so `count` and `delete` cannot
	/// accept a spelling of a row they never print.
	static var demanglable: Bool { get }

	var mangledName: String? { get }

	/// The row with the demangled siblings applied. A row that already carries
	/// a `demangled` column fills it — a name the user set with
	/// `insert --demangled` outranks the toolchain's guess — while a row that
	/// has no such column gains one, so an un-flagged row keeps its shape.
	/// The label is `applying:` because a call spelled `row(demangled:)` resolves
	/// to a member taking a single `String` before it reaches this requirement.
	func row(applying names: [String: String]) -> [RowField]

	static var subcommands: [any ParsableCommand.Type] { get }

	/// Filters are allowed to look things up in the document first — a name or
	/// a file offset only becomes a comparable address after that — which is
	/// why this gets a context and may fail.
	static func apply(_ options: FetchOptions, to descriptor: inout FetchDescriptor<Self>, in modelContext: ModelContext) throws
}

extension FetchableModel {
	static var subcommands: [any ParsableCommand.Type] { [] }

	static var demanglable: Bool { false }

	var mangledName: String? { nil }

	func row(applying names: [String: String]) -> [RowField] { fields() }

	func describe() -> String {
		render(fields())
	}
}

extension FetchableModel where FetchOptions == EmptyOptions {
	static func apply(_ options: FetchOptions, to descriptor: inout FetchDescriptor<Self>, in modelContext: ModelContext) throws {}
}

struct FetchOptions: ParsableArguments {
	@Option(help: "Maximum number of models to show")
	var limit: Int?

	@Option(help: "Skip this many models from the start of the result")
	var offset: Int?

	func apply(to descriptor: inout FetchDescriptor<some PersistentModel>) {
		descriptor.fetchLimit = limit
		descriptor.fetchOffset = offset
	}
}

struct FetchCommand<Model: FetchableModel>: AsyncParsableCommand {
	static var configuration: CommandConfiguration {
		CommandConfiguration(
			commandName: "fetch",
			abstract: "Fetches a list of \(Model.plural) from the project.",
			subcommands: Model.subcommands)
	}

	@OptionGroup var aether: AetherOptions
	@OptionGroup var modelOptions: Model.FetchOptions
	@OptionGroup var fetchOptions: FetchOptions

	@Flag(help: "Emit the rows as a JSON array of objects keyed by the field names of the text rows")
	var json = false

	@Flag(help: "Ask the toolchain's own demanglers for a `demangled` sibling of each row's symbol name; a name they do not recognise keeps the raw spelling and prints no field")
	var demangle = false

	mutating func run() async throws {
		let context = try aether.backgroundContext()
		var descriptor = FetchDescriptor<Model>()
		try Model.apply(modelOptions, to: &descriptor, in: context)
		let count = try context.fetchCount(descriptor)
		fetchOptions.apply(to: &descriptor)
		let models = try context.fetch(descriptor)
		// One process per demangler for the whole page, keyed by the mangled
		// name, so a page of any size costs at most two processes rather than
		// one per row.
		var demangled: [String: String] = [:]
		if demangle {
			guard Model.demanglable else {
				throw DemangleError.unsupported(plural: Model.plural)
			}
			demangled = demangledNames(models.compactMap { $0.mangledName })
		}
		if json {
			print(jsonRows(models.map { jsonRow($0.row(applying: demangled)) }))
			return
		}
		let offset = fetchOptions.offset ?? 0
		print("Showing \(models.count) (\(offset)-\(offset + models.count)) of \(count) \(Model.plural):")
		if demangle {
			// Rows the demanglers did not change print no field at all, so the
			// census line is the only place a script can tell "no mangling here"
			// apart from "mangling not recognised".
			let hits = models.filter { model in
				guard let name = model.mangledName else { return false }
				return demangled[name] != nil
			}.count
			if hits == 0 {
				print("demangled 0 of \(models.count) rows — neither /usr/bin/swift demangle nor /usr/bin/c++filt recognised these names")
			} else {
				print("demangled \(hits) of \(models.count) rows")
			}
		}
		for model in models {
			print(render(model.row(applying: demangled)))
		}
	}
}
