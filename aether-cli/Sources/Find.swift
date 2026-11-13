import ArgumentParser
import AetherKit
import Foundation
import SwiftData

struct FindCommand: AsyncParsableCommand {
	static let configuration = CommandConfiguration(
		commandName: "find",
		abstract: "Searches the file bytes: a byte pattern with ?? wildcards, literal text, or pointers to an address.")

	@OptionGroup var aether: AetherOptions

	@Option(help: "Program to search; required when the project holds several")
	var binary: String?

	@Option(help: "Byte pattern, two hex digits per byte, ?? for any byte, e.g. DE??00 (max 4096)")
	var bytes: BytePattern?

	@Option(help: "Literal text, matched as its UTF-8 bytes")
	var text: String?

	@Option(help: "Address to search for as a pointer: decimal, 0x…, @…, off:<file offset> or a symbol name")
	var pointerTo: AddressArgument?

	@Option(help: "Hits to print (default 500; 0 counts without printing)")
	var limit: Int = 500

	@Flag(help: "Print every hit rather than the first 500")
	var all: Bool = false

	mutating func run() async throws {
		let context = try aether.backgroundContext()
		let program = try requireProgram(named: binary, in: context)
		guard bytes != nil || text != nil || pointerTo != nil else { throw FindError.noPattern }
		guard limit >= 0 else { throw FindError.negativeLimit }

		var searches: [Search] = []
		if let pattern = bytes {
			searches.append(Search(label: "bytes", pattern: pattern.pattern, needle: pattern.needle))
		}
		if let needle = text {
			guard !needle.isEmpty else { throw FindError.emptyText }
			var bytes: [UInt8?] = []
			for byte in Array(needle.utf8) {
				bytes.append(byte)
			}
			searches.append(Search(label: "text", pattern: needle, needle: bytes))
		}
		if let argument = pointerTo {
			let address = try resolveAddress(argument, named: binary, in: context)
			guard address != 0 else { throw FindError.pointerIsZero }
			var bytes: [UInt8?] = []
			for byte in pointerBytes(address, in: program) {
				bytes.append(byte)
			}
			searches.append(Search(label: "pointer", pattern: "@" + hex(address), needle: bytes, pointer: true))
		}

		for search in searches {
			report(search, hits: scan(search.needle, in: program.data), cap: all ? Int.max : limit, in: program)
		}
	}

	/// One line says what is being searched and how many of it were found; the
	/// rows underneath are the hits themselves, in file order.
	private func report(_ search: Search, hits: [Int], cap: Int, in program: BinaryModel) {
		print("search=\(search.label) pattern=\(search.pattern) program=" + program.name)
		let shown = min(cap, hits.count)
		if hits.isEmpty {
			print("No hits in \(program.name)")
			return
		}
		if shown == 0 {
			print("Showing 0 of \(hits.count) hits:")
			return
		}
		print("Showing \(shown) (0-\(shown - 1)) of \(hits.count) hits:")
		for offset in hits.prefix(shown) {
			print(row(offset: offset, in: program, pointer: search.pointer, width: search.needle.count))
		}
	}

	private func row(offset: Int, in program: BinaryModel, pointer: Bool, width: Int) -> String {
		let address = virtualAddress(of: UInt64(offset), in: program)
		var fields = [
			"off=" + hex(UInt64(offset)),
			address.map { "@" + hex($0) } ?? "@none",
			"segment=" + (address.flatMap { program.segment(containing: $0) }.map { $0.name } ?? "none"),
			"section=" + (address.flatMap { program.section(containing: $0) }.map { $0.fullName } ?? "none"),
		]
		if pointer {
			// A pointer that is not a multiple of its own width is almost
			// always a coincidence in the data rather than an address.
			fields.append("aligned=" + (offset % width == 0 ? "true" : "false"))
		}
		return fields.joined(separator: " ")
	}

	/// One matcher for all three kinds of search: every requested pattern reduces
	/// to a needle of bytes, some of which may not care what they match.
	private func scan(_ needle: [UInt8?], in data: Data) -> [Int] {
		var hits: [Int] = []
		guard !needle.isEmpty, needle.count <= data.count else { return hits }
		outer: for offset in 0...(data.count - needle.count) {
			for index in 0..<needle.count {
				guard let wanted = needle[index] else { continue }
				if data[offset + index] != wanted { continue outer }
			}
			hits.append(offset)
		}
		return hits
	}

	/// The address encoded the way the file spells addresses, so the search
	/// finds pointers as they are stored rather than as host integers.
	private func pointerBytes(_ address: UInt64, in program: BinaryModel) -> [UInt8] {
		let width = program.is64 ? 8 : 4
		let bigEndian = program.endian == .big
		var out: [UInt8] = []
		for index in 0..<width {
			let shift = UInt64(bigEndian ? width - 1 - index : index) * 8
			out.append(UInt8((address >> shift) & 0xFF))
		}
		return out
	}
}

/// What one search is: a label for the report, the canonical spelling of the
/// pattern, and the needle to scan for.
private struct Search {
	let label: String
	let pattern: String
	let needle: [UInt8?]
	var pointer: Bool = false
}

/// A byte pattern with wildcard positions, the spelling borer's `search` uses
/// (`DE??00`) and the same shape `sig` prints, which is how a library-function
/// pattern set gets handed back to `--bytes`.
struct BytePattern: ExpressibleByArgument {
	var pattern = ""
	var needle: [UInt8?] = []

	init?(argument: String) {
		let chars = Array(argument)
		guard !chars.isEmpty, chars.count % 2 == 0, chars.count <= 8192 else { return nil }
		var pattern = ""
		var needle: [UInt8?] = []
		var index = 0
		while index < chars.count {
			let pair = "\(chars[index])\(chars[index + 1])"
			if pair == "??" {
				pattern += "??"
				needle.append(nil)
			} else if let byte = UInt8(pair, radix: 16) {
				pattern += String(format: "%02X", byte)
				needle.append(byte)
			} else {
				// A stray digit is a typo in the pattern, not a symbol name:
				// there is nothing else `--bytes` could mean by it.
				return nil
			}
			index += 2
		}
		self.pattern = pattern
		self.needle = needle
	}
}

enum FindError: LocalizedError {
	case noPattern
	case emptyText
	case negativeLimit
	case pointerIsZero

	var errorDescription: String? {
		switch self {
		case .noPattern:
			return "Pass at least one of --bytes, --text or --pointer-to"
		case .emptyText:
			return "--text cannot be empty, it would match every byte in the file"
		case .negativeLimit:
			return "--limit cannot be negative"
		case .pointerIsZero:
			return "Nothing points at address 0: it is not inside any segment"
		}
	}
}
