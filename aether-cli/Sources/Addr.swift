import ArgumentParser
import Foundation
import AetherKit
import SwiftData

struct AddrCommand: AsyncParsableCommand {
	static let configuration = CommandConfiguration(
		commandName: "addr",
		abstract: "Resolves one address: where it is and what lives there.")

	@OptionGroup var aether: AetherOptions

	@Option(help: "Program to resolve the address in; required when the project holds several")
	var binary: String?

	@Argument(help: "Address to resolve: decimal, 0x…, @…, off:<file offset> or a symbol name")
	var address: AddressArgument

	mutating func run() async throws {
		let context = aether.backgroundContext
		let program = try requireProgram(named: binary, in: context)
		let address = try resolveAddress(address, named: program.name, in: context)

		let offset = fileOffset(of: address, in: program)

		print([
			"@\(hex(address))",
			"off=" + (offset.map { hex($0) } ?? "none"),
			"program=" + program.name,
			"segment=" + (program.segment(containing: address).map { "\($0.name) prot=\($0.protectionString)" } ?? "none"),
			"section=" + (program.section(containing: address).map { $0.fullName } ?? "none"),
			"symbol=" + (owner(of: address, in: program.symbols).map { "\($0.name) @\(hex($0.address))+\(hex($0.size))" } ?? "none"),
			"procedure=" + (owner(of: address, in: program.procedures).map { $0.symbol.name } ?? "none"),
		].joined(separator: " "))
	}
}

/// The symbol that owns an address: the row starting closest at or before it
/// whose size still covers it. A row with `size == 0` runs to the next symbol,
/// so it owns everything after it — except at address 0, which is how imported
/// symbols are stored, and a row with no place in the file owns no address.
private func owner(of address: UInt64, in rows: [SymbolModel]) -> SymbolModel? {
	var owner: SymbolModel?
	for row in rows where row.address != 0 && row.address <= address && (row.size == 0 || address < row.address + row.size) {
		guard let current = owner else {
			owner = row
			continue
		}
		if row.address > current.address {
			owner = row
		}
	}
	return owner
}

/// The procedure that owns an address: the innermost one covering it, which is
/// the last procedure in a section — its symbol has no size, so `contains`
/// alone would never answer for it.
private func owner(of address: UInt64, in rows: [ProcedureModel]) -> ProcedureModel? {
	var owner: ProcedureModel?
	for row in rows where row.symbol.address != 0 && (row.contains(address: address) || (row.symbol.size == 0 && address >= row.symbol.address)) {
		guard let current = owner else {
			owner = row
			continue
		}
		if row.symbol.address > current.symbol.address {
			owner = row
		}
	}
	return owner
}
