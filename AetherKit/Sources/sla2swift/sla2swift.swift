//
//  sla2swift.swift
//  AetherKit
//
//  Created by Christophe Bronner on 2026-06-30.
//

import Foundation
import ArgumentParser

@main
struct sla2swift: AsyncParsableCommand {
	@Argument
	var inputs: [String]

	mutating func run() async throws {
		await withTaskGroup { group in
			let args = self

			for input in inputs {
				group.addTask {
					do { try await Self.run(input, using: args) }
					catch { print("\(input): \(error.localizedDescription)\n\(error)") }
				}
			}

			await group.waitForAll()
		}
	}

	@concurrent
	private static func run(_ input: String, using args: sla2swift) async throws {
		let url = URL(fileURLWithPath: input)
		let data = try Data(contentsOf: url, options: .uncached)
		let sla = try JSONDecoder().decode(SleighSpec.Document.self, from: data)
		let config = ArchitectureConfiguration(
			name: url
				.deletingPathExtension()
				.lastPathComponent
				.components(separatedBy: .alphanumerics.inverted)
				.joined(separator: "_")
				.replacing(/_+/, with: "_")
				.capitalized)
		let headerUrl = url.deletingPathExtension().appendingPathExtension("h")
		try sla.toHeader.write(to: headerUrl, atomically: true, encoding: .utf8)
		let swiftUrl = url.deletingPathExtension().appendingPathExtension("swift")
		try sla.toSwift(using: config).write(to: swiftUrl, atomically: true, encoding: .utf8)
	}
}

public extension SleighSpec.Document {
	var toHeader: String {
		""
	}

	func toSwift(using configuration: ArchitectureConfiguration) -> String {
		var output = ""
		output += "public enum \(configuration.name) {}\n"
		output += "\n"
		output += "public extension \(configuration.name) {\n"
		output += "\n\t//MARK: - Address Spaces\n\n"
		for space in children.sleigh.children.spaces.children {
			switch space {
			case let .space(space):
				output += "\tstatic let \(space.name) = \(space)\n"
			case let .space_other(space):
				output += "\tstatic let \(space.name) = \(space)\n"
			case let .space_unique(space):
				output += "\tstatic let \(space.name) = \(space)\n"
			}
		}
		output += "\n\t//MARK: - Symbols\n\n"
		let symtab = children.sleigh.children.symbol_table.children
		let sourcefiles = children.sleigh.children.sourcefiles
		for i in symtab.headers.indices {
			let header = symtab.headers[i]
			switch symtab.symbols[i] {
			case let .context_sym(sym):
				output += "\tstatic let \(header.name) = \(symtab.headers[sym.varnode].name).context(\(sym.low)...\(sym.high), flow: \(sym.flow))\n"
				continue
			case let .name_sym(name):
				fatalError("unsupported name_sym: \(name)")
			case let .varnode_sym(sym):
				output += "\tstatic let \(header.name) = Varnode(at: \(sym.off), in: \(sym.space), size: \(sym.size))\n"
				continue
			case let .userop(sym):
				output += "\tstatic let \(header.name) = PcodeId(user: \(sym.index))\n"
				continue
			case let .subtable_sym(sym):
				output += "\tmutating func \(header.name)() throws(DisassemblyError) -> UInt8 {\n"


				// Constructors may be jumped to from multiple matches, they should be their own function.

				// Non-terminals read a number of bits from either the context or instruction and use that as a jump table for their children.

//				if (contextdecision)
//				  val = walker.getContextBits(startbit,bitsize);
//				else
//				  val = walker.getInstructionBits(startbit,bitsize);
//				return children[val]->resolve(walker);

				output += sym.children.decision.debugDescription(
					depth: 0,
					using: sym.children.constructors,
					symtab: symtab,
					sourcefiles: sourcefiles)

				var indent = "\t"
				func write(_ decision: SleighSpec.DecisionNode, from parent: borrowing SleighSpec.DecisionNode?) {
					if decision.size == 0 {
						for pair in decision.children?.candidates ?? [] {
							output += indent
							//TODO: extract the pattern as dictated by the parent decision node
							output += "case \(pair.children.pattern.description): ct\(pair.id)()\n"
						}
					} else {
						let source = decision.context ? "context" : "instruction"
						let bits = decision.size//.roundedUp(toMultipleOf: 8)
						output += "\(indent)switch \(source).u\(bits)(from: \(decision.startbit), length: \(decision.size)) {\n"
						if !(decision.children?.candidates ?? []).isEmpty {
							output += "\(indent)// HAS CANDIDATES\n"
						}
						for d in decision.children?.subdecisions ?? [] {
							write(d, from: decision)
						}
						output += indent
						output += "default: unreachable()\n"
						output += indent + "}\n"
					}
				}

				write(sym.children.decision, from: nil)

				for (i, ct) in sym.children.constructors.enumerated() {
					output += "\t\t" + "func ct\(i)() throws(DisassemblyError) {\n"
					output += "\t\t\t" + ct.debugDescription(symtab: symtab, sourcefiles: sourcefiles)
						.replacingOccurrences(of: "\n", with: "\n\t\t\t")
					output += "\t\t" + "}\n"
				}
				continue
			case .start_sym, .end_sym, .next2_sym:
				// Note: builtin
				output += "\t// builtin: \(header.name)\n"
				continue
			default:
//				output += "static let \(header.name) = ;\n"
				continue
			}
		}
		output += "}\n"
		return output
	}
}

public struct ArchitectureConfiguration {
	public var name: String

	public init(name: String) {
		self.name = name
	}
}
