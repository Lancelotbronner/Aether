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
		abstract: "Run the procedure detection pass over every binary in the project.")

	@OptionGroup var aether: AetherOptions

	@Flag(help: "Emit one JSON object per program instead of the report lines")
	var json = false

	mutating func run() async throws {
		let context = try aether.backgroundContext()
		var rows: [String] = []
		for binary in try context.fetch(FetchDescriptor<BinaryModel>()) {
			let report = ProcedureDetector().detect(in: binary)
			if json {
				// The summary sentence is four counts; the JSON row gives them
				// as fields rather than asking a script to parse prose.
				rows.append(jsonRow([
					field("program", binary.name),
					field("codeSections", report.codeSections),
					field("entryPoints", report.entryPoints),
					field("synthesized", report.synthesized),
					field("created", report.created),
					field("total", binary.procedures.count),
				]))
			} else {
				print("\(binary.name): \(report.summary), \(binary.procedures.count) total procedures")
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
