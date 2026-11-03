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
		])
}

extension SymbolModel: FetchableModel {
	static let plural = "symbols"

	struct FetchOptions: ParsableArguments {
		@Option(help: "Filters to a specific program")
		var binary: String?

		@Option(help: "Search within the symbol name")
		var name: String?

		@Option(help: "Filter to a symbol at an address (decimal; addresses print as hex)")
		var address: UInt64?

		@Option(help: "Filter on kind (0 unknown, 1 function, 2 data, 3 section)")
		var kind: SymbolKind?

		@Option(help: "Filter on type (0 unknown, 1 u8, 2 u16, 3 u32, 4 u64, 5 u128, 6 ascii, 7 utf8, 8 utf16, 9 ptr, 10 function)")
		var type: SymbolType?

		@Option(help: "Filter on binding (0 undefined, 1 local, 2 global, 3 weak, 4 external)")
		var binding: SymbolBinding?

		@Option(help: "Search within the decoded string value")
		var value: String?

		@Flag(help: "Filter to imported symbols")
		var imported: Bool = false

		@Flag(help: "Filter to exported symbols")
		var exported: Bool = false
	}

	static func apply(_ options: FetchOptions, to descriptor: inout FetchDescriptor<SymbolModel>) {
		let binary = options.binary.flatMap { filter in
			#Predicate<SymbolModel> { $0.binary.name == filter }
		} ?? .true
		let name = options.name.flatMap { filter in
			#Predicate<SymbolModel> { $0.name.localizedStandardContains(filter) }
		} ?? .true
		let address = options.address.flatMap { filter in
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
		descriptor.predicate = #Predicate<SymbolModel> {
			binary.evaluate($0) && name.evaluate($0) && address.evaluate($0)
				&& kind.evaluate($0) && type.evaluate($0) && binding.evaluate($0)
				&& value.evaluate($0) && imported.evaluate($0) && exported.evaluate($0)
		}
		descriptor.sortBy = [SortDescriptor(\SymbolModel.address)]
	}

	func describe() -> String {
		"\(name) @\(hex(address)) size=\(size) kind=\(kind) type=\(type) binding=\(binding)"
			+ " import=\(isImport) export=\(isExport) identifier=\(identifier) value=\(stringValue)"
			+ " program=\(binary.name)"
	}
}

extension SymbolModel: InsertableModel {
	static let singular = "symbol"

	struct InsertOptions: ParsableArguments {
		@Argument(help: "Name of the program to add a symbol to")
		var binary: String

		@Argument(help: "Symbol name")
		var name: String

		@Argument(help: "Memory address of the symbol (decimal; addresses print as hex)")
		var address: UInt64

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
		let address = options.address
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
