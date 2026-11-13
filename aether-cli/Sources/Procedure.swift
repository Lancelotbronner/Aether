import ArgumentParser
import AetherKit
import Foundation
import SwiftData

struct ProcedureCommand: AsyncParsableCommand {
	static let configuration = CommandConfiguration(
		commandName: "procedure",
		abstract: "Work with procedures.",
		subcommands: [
			FetchCommand<ProcedureModel>.self,
			CountCommand<ProcedureModel>.self,
			DeleteCommand<ProcedureModel>.self,
			InsertCommand<ProcedureModel>.self,
			DetectCommand.self,
		])
}

extension ProcedureModel: FetchableModel {
	static let plural = "procedures"

	struct FetchOptions: ParsableArguments {
		@Option(help: "Search within the symbol name of the procedure")
		var name: String?

		@Option(help: "Filters to a specific program")
		var binary: String?

		@Option(help: "Filter to a procedure at an address: decimal, 0x…, @…, off:<file offset> or a symbol name")
		var address: AddressArgument?

		@Flag(help: "Filter to thunk procedures")
		var thunk: Bool = false

		@Flag(help: "Filter to leaf procedures")
		var leaf: Bool = false
	}

	static func apply(_ options: FetchOptions, to descriptor: inout FetchDescriptor<ProcedureModel>, in modelContext: ModelContext) throws {
		let addressValue = try filterAddress(options.address, named: options.binary, in: modelContext)
		let name = options.name.flatMap { filter in
			#Predicate<ProcedureModel> { $0.symbol.name.localizedStandardContains(filter) }
		} ?? .true
		let binary = options.binary.flatMap { filter in
			#Predicate<ProcedureModel> { $0.binary.name == filter }
		} ?? .true
		let address = addressValue.flatMap { filter in
			#Predicate<ProcedureModel> { $0.symbol.address == filter }
		} ?? .true
		let thunk = options.thunk ? #Predicate<ProcedureModel> { $0.isThunk } : .true
		let leaf = options.leaf ? #Predicate<ProcedureModel> { $0.isLeaf } : .true
		descriptor.predicate = #Predicate<ProcedureModel> {
			name.evaluate($0) && binary.evaluate($0) && address.evaluate($0) && thunk.evaluate($0) && leaf.evaluate($0)
		}
		descriptor.sortBy = [SortDescriptor(\ProcedureModel.symbol.address)]
	}

	var argumentList: String {
		"[" + arguments.map { argument in
			var text = "\(argument.name): \(argument.type)"
			if let register = argument.register {
				text += " " + register
			} else if let stackOffset = argument.stackOffset {
				text += " sp+\(stackOffset)"
			}
			return text
		}.joined(separator: ", ") + "]"
	}

	var localList: String {
		"[" + localVariables.map { local in "\(local.name): \(local.type) sp+\(local.stackOffset):\(local.size)" }.joined(separator: ", ") + "]"
	}

	func fields() -> [RowField] {
		[
			head("name", symbol.name),
			at(hex(symbol.address)),
			field("size", symbol.size),
			field("frame", stackSize),
			field("thunk", isThunk),
			field("leaf", isLeaf),
			field("demangled", demangled),
			field("blocks", blocks.count),
			field("callers", callers.count),
			field("callees", callees.count),
			field("arguments", argumentList),
			field("locals", localList),
			field("program", binary.name),
		]
	}

	static let demanglable = true

	/// The procedure's display name comes from its symbol; the mangled spelling
	/// lives on that symbol's `identifier`.
	var mangledName: String? {
		symbol.identifier.isEmpty ? nil : symbol.identifier
	}

	/// This row already carries a `demangled` column, which `procedure insert
	/// --demangled` writes by hand, so the demangler only fills the ones that
	/// are empty: a name the user stored outranks the toolchain's guess, and
	/// the column never gains a second value to disagree with.
	func row(applying names: [String: String]) -> [RowField] {
		guard let mangled = mangledName, let demangled = names[mangled] else { return fields() }
		return fields().map { existing in
			existing.key == "demangled" && existing.value.isEmpty ? field("demangled", demangled) : existing
		}
	}
}

extension ProcedureModel {
	/// `ProcedureModel.blocks` declares `deleteRule: .cascade`, so a procedure
	/// delete takes its block rows with it. There is no `block` command group,
	/// so those rows are otherwise invisible in the CLI: this is the only place
	/// their count surfaces.
	static func cascade(of models: [ProcedureModel], in modelContext: ModelContext) -> CascadeReport {
		var report = CascadeReport()
		for model in models {
			report.take("blocks", model.blocks.count)
		}
		return report
	}
}

extension ProcedureModel: InsertableModel {
	static let singular = "procedure"

	struct InsertOptions: ParsableArguments {
		@Argument(help: "Name of the program the procedure belongs to")
		var binary: String

		@Argument(help: "Name or identifier of the symbol the procedure is for")
		var symbol: String

		@Flag(help: "Mark the procedure as a simple jump to another function")
		var thunk: Bool = false

		@Option(help: "Stack frame size, in bytes (decimal)")
		var stackSize: Int = 0

		@Option(help: "High-level name of the procedure")
		var demangled: String = ""
	}

	convenience init(options: InsertOptions, using modelContext: ModelContext) async throws {
		let binary = try requireBinary(named: options.binary, in: modelContext)
		let binaryName = binary.name
		let symbolName = options.symbol
		var symbolQuery = FetchDescriptor<SymbolModel>()
		symbolQuery.predicate = #Predicate<SymbolModel> { ($0.name == symbolName || $0.identifier == symbolName) && $0.binary.name == binaryName }
		symbolQuery.fetchLimit = 1
		guard let symbol = try modelContext.fetch(symbolQuery).first else {
			throw InsertError.unknownSymbol(name: symbolName, binary: binaryName)
		}

		var taken = FetchDescriptor<ProcedureModel>()
		taken.predicate = #Predicate<ProcedureModel> { $0.binary.name == binaryName && $0.symbol.name == symbolName }
		taken.fetchLimit = 1
		if try modelContext.fetch(taken).first != nil {
			throw InsertError.duplicate(kind: "procedure", key: "\(binaryName) \(symbolName)")
		}

		self.init(is: symbol, in: binary)
		self.demangled = options.demangled
		self.stackSize = options.stackSize
		self.isThunk = options.thunk
	}
}

struct DetectCommand: AsyncParsableCommand {
	static let configuration = CommandConfiguration(
		commandName: "detect",
		abstract: "Run procedure detection over a program or every program in the project.",
		discussion: """
			`--explain` answers "what did this pass actually match, and where": one
			census line per program, then the same counts per code section the scan
			walked. A section line names only the patterns that matched there; the
			zeros live on the whole-program line, which is what makes `framePair:0`
			read as a regression instead of an omission.

			`--address` answers the narrower question — which pattern put this one
			row on the map. It prints `none` when the pass never noted that
			address, which includes rows that already existed before a restricted
			pass ran. A symbol NAME is resolved before the pass runs, so it has to
			be a name the store already holds: pass the address of a symbol this
			run only just synthesized.

			`--pattern` runs one way of finding an entry point on its own, which
			is how one pattern's yield is measured rather than inferred from the
			rows it created: a pass told to use only `stubThunk` declines the
			symtab rows too. Addresses the store already has a procedure for stay
			counted but are never synthesized twice, so a restricted pass is
			idempotent the way a full one is.

			On a store that has already been detected, a row an earlier pass
			synthesized now reads as `symtab`: the symbol table names it now, which
			is why the row exists today. The census counts matches this pass walked,
			not rows in the store — `total procedures` stays the store's count.
			""")

	@OptionGroup var aether: AetherOptions

	@Flag(help: "Emit one JSON object per program instead of the report lines")
	var json = false

	@Flag(help: "Report which pattern found how much, and the same counts per code section")
	var explain = false

	@Option(help: "Report which pattern put one entry point on the map: decimal, 0x…, @…, off:<file offset> or a symbol name")
	var address: AddressArgument?

	@Option(help: "Run only these ways of finding an entry point: symtab, entryPoint, stubThunk, bti, pacibsp, framePair, linkStore, stackAdjust, x86Prologue")
	var pattern: [ProcedureDetectionPattern] = []

	@Option(help: "Filters to a specific program")
	var binary: String?

	mutating func run() async throws {
		let context = try aether.backgroundContext()
		let program = binary

		// Resolved before the pass runs, so a symbol name is answered from the
		// persisted store rather than from a name this same pass just invented.
		let wanted = try filterAddress(address, named: program, in: context)
		// Empty means every pattern the architecture can walk.
		let patterns = pattern.isEmpty ? nil : Set(pattern)

		var programs: [BinaryModel]
		if let program {
			programs = [try requireBinary(named: program, in: context)]
		} else {
			programs = try context.fetch(FetchDescriptor<BinaryModel>())
		}

		var rows: [String] = []
		for program in programs {
			let report = ProcedureDetector().detect(in: program, patterns: patterns)
			if json {
				// The summary sentence is four counts; the JSON row gives them
				// as fields rather than asking a script to parse prose.
				var fields: [RowField] = [
					field("program", program.name),
					field("codeSections", report.codeSections),
					field("entryPoints", report.entryPoints),
					field("synthesized", report.synthesized),
					field("created", report.created),
					field("total", program.procedures.count),
				]
				if explain {
					fields.append(field("patterns", report.patternsSummary))
					fields.append(field("patternSections", report.sections
						.map { "\($0.name)=\($0.census)" }
						.joined(separator: ";")))
				}
				if let wanted {
					fields.append(field("origin", report.origin[wanted]?.rawValue ?? "none"))
				}
				rows.append(jsonRow(fields))
			} else {
				print("\(program.name): \(report.summary), \(program.procedures.count) total procedures")
				if explain {
					print("\(program.name): patterns \(report.patternsSummary)")
					for section in report.sections {
						print("  \(section.name): \(section.census)")
					}
				}
				if let wanted {
					print("\(program.name): @\(hex(wanted)) — \(report.origin[wanted]?.rawValue ?? "none")")
				}
			}
		}
		if json {
			print(jsonRows(rows))
		}
		if !aether.dryRun {
			try context.save()
		}
	}
}
