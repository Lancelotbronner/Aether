//
//  SleighSpec.swift
//  AetherKit
//
//  Created by Christophe Bronner on 2026-06-20.
//

import Foundation
import CaseAccessors

public enum SleighSpec {}

public extension SleighSpec {
	struct Document: Codable, Sendable {
		public var version: String
		public var children: Children

		@CaseAccessors
		public enum Child: Codable, Sendable {
			case sleigh(Specification)
		}

		public struct Children: Codable, Sendable {
			var sleigh: Specification

			public init(from decoder: any Decoder) throws {
				var c = try decoder.unkeyedContainer()
				sleigh = try c.decode(Child.self, as: \.sleigh)
			}

			public func encode(to encoder: any Encoder) throws {
				var c = encoder.unkeyedContainer()
				try c.encode(Child.sleigh(sleigh))
			}
		}
	}

	struct Specification: Codable, Sendable {
		public var align: Int
		public var bigendian: Bool
		public var children: Children
		public var maxdelay: Int?
		public var numsections: Int?
		public var uniqbase: Int
		public var uniqmask: Int?
		public var version: Int

		@CaseAccessors
		public enum Child: Codable, Sendable {
			case sourcefiles(Sourcefiles)
			case spaces(Spaces)
			case symbol_table(SymbolTable)
		}

		public struct Children: Codable, Sendable {
			var sourcefiles: Sourcefiles
			var spaces: Spaces
			var symbol_table: SymbolTable

			public init(from decoder: any Decoder) throws {
				var c = try decoder.unkeyedContainer()
				sourcefiles = try c.decode(Child.self, as: \.sourcefiles)
				spaces = try c.decode(Child.self, as: \.spaces)
				symbol_table = try c.decode(Child.self, as: \.symbol_table)
			}

			public func encode(to encoder: any Encoder) throws {
				var c = encoder.unkeyedContainer()
				try c.encode(Child.sourcefiles(sourcefiles))
				try c.encode(Child.spaces(spaces))
				try c.encode(Child.symbol_table(symbol_table))
			}
		}
	}

	struct Sourcefiles: Codable, Sendable {
		public var children: Children

		@CaseAccessors
		public enum Child: Codable, Sendable {
			case sourcefile(Sourcefile)
		}

		public struct Children: Codable, Sendable {
			var sourcefiles: [String] = []

			public init() {}

			public init(from decoder: any Decoder) throws {
				var c = try decoder.unkeyedContainer()
				sourcefiles = Array(repeating: "", count: c.count ?? 0)
				while !c.isAtEnd {
					let next = try c.decode(Child.self, as: \.sourcefile)
					sourcefiles[next.index] = next.name
				}
			}

			public func encode(to encoder: any Encoder) throws {
				var c = encoder.unkeyedContainer()
				for i in sourcefiles.indices {
					try c.encode(Child.sourcefile(.init(index: i, name: sourcefiles[i])))
				}
			}
		}
	}

	struct Sourcefile: Codable, Sendable {
		public var index: Int
		public var name: String
	}

	struct Spaces: Codable, Sendable {
		public var children: [Child]
		public var defaultspace: String

		public enum Child: Codable, Sendable {
			case space(Space)
			case space_other(Space)
			case space_unique(Space)
		}
	}

	struct Space: Codable, Sendable {
		public var bigendian: Bool
		public var delay: Int
		public var index: Int
		public var name: String
		public var physical: Bool
		public var size: Int
		/// defaults to 1 if nil
		public var wordsize: Int?
	}

	struct SymbolTable: Codable, Sendable {
		public var children: Children
		public var scopesize: Int
		public var symbolsize: Int

		@CaseAccessors
		public enum Child: Codable, Sendable {
			case context_sym(ContextSym)
			case context_sym_head(SymbolHeader)
			case end_sym(EndSym)
			case end_sym_head(SymbolHeader)
			case name_sym(NameSym)
			case name_sym_head(SymbolHeader)
			case next2_sym(Next2Sym)
			case next2_sym_head(SymbolHeader)
			case operand_sym(OperandSym)
			case operand_sym_head(SymbolHeader)
			case scope(Scope)
			case start_sym(StartSym)
			case start_sym_head(SymbolHeader)
			case subtable_sym(SubtableSym)
			case subtable_sym_head(SymbolHeader)
			case userop(Userop)
			case userop_head(SymbolHeader)
			case value_sym(ValueSym)
			case value_sym_head(SymbolHeader)
			case valuemap_sym(ValuemapSym)
			case valuemap_sym_head(SymbolHeader)
			case varlist_sym(VarlistSym)
			case varlist_sym_head(SymbolHeader)
			case varnode_sym(VarnodeSym)
			case varnode_sym_head(SymbolHeader)

			var sym_head: SymbolHeader? {
				switch self {
				case let .context_sym_head(x): x
				case let .end_sym_head(x): x
				case let .name_sym_head(x): x
				case let .next2_sym_head(x): x
				case let .operand_sym_head(x): x
				case let .start_sym_head(x): x
				case let .subtable_sym_head(x): x
				case let .userop_head(x): x
				case let .value_sym_head(x): x
				case let .valuemap_sym_head(x): x
				case let .varlist_sym_head(x): x
				case let .varnode_sym_head(x): x
				default: nil
				}
			}

			var sym: Symbol? {
				switch self {
				case let .context_sym(x): .context_sym(x)
				case let .end_sym(x): .end_sym(x)
				case let .name_sym(x): .name_sym(x)
				case let .next2_sym(x): .next2_sym(x)
				case let .operand_sym(x): .operand_sym(x)
				case let .start_sym(x): .start_sym(x)
				case let .subtable_sym(x): .subtable_sym(x)
				case let .userop(x): .userop(x)
				case let .value_sym(x): .value_sym(x)
				case let .valuemap_sym(x): .valuemap_sym(x)
				case let .varlist_sym(x): .varlist_sym(x)
				case let .varnode_sym(x): .varnode_sym(x)
				default: nil
				}
			}
		}

		public struct Children: Codable, Sendable {
			var scopes: [Int] = []
			var headers: [SymbolHeader] = []
			var symbols: [Symbol] = []

			public init() {}

			public func resolve(context range: ClosedRange<Int>) -> SymbolHeader? {
				for i in symbols.indices {
					guard
						let sym = symbols[i].context_sym,
						sym.low == range.lowerBound,
						sym.high == range.upperBound
					else { continue }
					return headers[i]
				}
				return nil
			}

			public func resolve(instruction range: ClosedRange<Int>) -> SymbolHeader? {
				return nil
			}

			public init(from decoder: any Decoder) throws {
				var c = try decoder.unkeyedContainer()
				(scopes, headers, symbols) = try c.decodeWhile(Child.self, is: { $0.scope?.parent }, \.sym_head, \.sym)
			}


			public func encode(to encoder: any Encoder) throws {
				var c = encoder.unkeyedContainer()
				for i in scopes.indices {
					try c.encode(Child.scope(.init(id: i, parent: scopes[i])))
				}
				for header in headers {
					try c.encode(header)
				}
				for header in symbols {
					try c.encode(header)
				}
			}
		}
	}

	@CaseAccessors
	enum Symbol: Codable, Sendable {
		case context_sym(ContextSym)
		case end_sym(EndSym)
		case name_sym(NameSym)
		case next2_sym(Next2Sym)
		case operand_sym(OperandSym)
		case start_sym(StartSym)
		case subtable_sym(SubtableSym)
		case userop(Userop)
		case value_sym(ValueSym)
		case valuemap_sym(ValuemapSym)
		case varlist_sym(VarlistSym)
		case varnode_sym(VarnodeSym)
	}

	struct ContextSym: Codable, Sendable {
		public var children: Children
		public var flow: Bool
		public var high: Int
		public var id: Int
		public var low: Int
		public var varnode: Int

		@CaseAccessors
		public enum Child: Codable, Sendable {
			case contextfield(Field)
		}

		public struct Children: Codable, Sendable {
			public var field: Field

			public init(from decoder: any Decoder) throws {
				var c = try decoder.unkeyedContainer()
				field = try c.decode(Child.self, as: \.contextfield)
			}

			public func encode(to encoder: any Encoder) throws {
				var c = encoder.unkeyedContainer()
				try c.encode(Child.contextfield(field))
			}
		}
	}

	struct Field: Codable, Sendable {
		public var bigendian: Bool?
		public var endbit: Int
		public var endbyte: Int
		public var shift: Int
		public var signbit: Bool
		public var startbit: Int
		public var startbyte: Int
	}

	struct SymbolHeader: Codable, Sendable {
		public var id: Int
		public var name: String
		public var scope: Int
	}

	struct StartSym: Codable, Sendable {
		public var id: Int
	}

	struct EndSym: Codable, Sendable {
		public var id: Int
	}

	struct Next2Sym: Codable, Sendable {
		public var id: Int
	}

	struct NameSym: Codable, Sendable {
		public var children: [PatternExprOr<Child>]
		public var id: Int

		public enum Child: Codable, Sendable {
			case nametab(Nametab)
		}
	}

	struct Nametab: Codable, Sendable {
		/// NIl if an illegal index
		public var name: Name?
	}

	enum Name: Codable, Sendable {
		case integer(Int)
		case string(String)

		public init(from decoder: Decoder) throws {
			let container = try decoder.singleValueContainer()
			if let x = try? container.decode(Int.self) {
				self = .integer(x)
				return
			}
			if let x = try? container.decode(String.self) {
				self = .string(x)
				return
			}
			throw DecodingError.typeMismatch(Name.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Wrong type for Name"))
		}

		public func encode(to encoder: Encoder) throws {
			var container = encoder.singleValueContainer()
			switch self {
			case .integer(let x):
				try container.encode(x)
			case .string(let x):
				try container.encode(x)
			}
		}
	}

	enum PatternExpr: Codable, Sendable {
		case and_exp(BinaryExpr)
		case contextfield(Field)
		case div_exp(BinaryExpr)
		case end_exp(EndInstructionValue)
		case intb(ConstantValue)
		case lshift_exp(BinaryExpr)
		/// negate
		case minus_exp(UnaryExpr)
		case mult_exp(BinaryExpr)
		case next2_exp(Next2InstructionValue)
		case not_exp(UnaryExpr)
		case operand_exp(OperandValue)
		case or_exp(BinaryExpr)
		case plus_exp(BinaryExpr)
		case rshift_exp(BinaryExpr)
		case start_exp(StartInstructionValue)
		/// subtract
		case sub_exp(BinaryExpr)
		case tokenfield(Field)
		case xor_exp(BinaryExpr)
	}

	struct BinaryExpr: Codable, Sendable {
		/// `[left, right]`
		public var children: [PatternExpr]
	}

	struct UnaryExpr: Codable, Sendable {
		/// `[val]`
		public var children: [PatternExpr]
	}

	struct StartInstructionValue: Codable, Sendable {}
	struct EndInstructionValue: Codable, Sendable {}
	struct Next2InstructionValue: Codable, Sendable {}

	enum PatternExprOr<Other: Codable & Sendable>: Codable, Sendable {
		case pattern(PatternExpr)
		case other(Other)

		public init(from decoder: Decoder) throws {
			let container = try decoder.singleValueContainer()
			if let x = try? container.decode(Other.self) {
				self = .other(x)
				return
			}
			if let x = try? container.decode(PatternExpr.self) {
				self = .pattern(x)
				return
			}
			throw DecodingError.typeMismatch(PatternExprOr.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected \(PatternExpr.self) or \(Other.self)"))
		}

		public func encode(to encoder: Encoder) throws {
			var container = encoder.singleValueContainer()
			switch self {
			case .pattern(let x):
				try container.encode(x)
			case .other(let x):
				try container.encode(x)
			}
		}
	}

	struct OperandSym: Codable, Sendable {
		public var base: Int
		/// First child is `localexp` and always an `operand_exp`, second child is `defexp`.
		public var children: [PatternExpr]
		/// Defaults to false
		public var code: Bool?
		public var id: Int
		public var index: Int
		public var minlen: Int
		public var off: Int
		/// Id of TripleSymbol
		public var subsym: Int?
	}

	struct ConstantValue: Codable, Sendable, Equatable, CustomStringConvertible {
		public var val: UInt64

		public var description: String {
			val.description
		}

		public init(from decoder: any Decoder) throws {
			let c = try decoder.container(keyedBy: CodingKeys.self)
			val = try c.decode(ToUInt64.self, forKey: CodingKeys.val).value
		}
	}

	private struct ToUInt64: Codable {
		public var value: UInt64

		init(from decoder: any Decoder) throws {
			let c = try decoder.singleValueContainer()
			do {
				value = try c.decode(UInt64.self)
			} catch {
				value = UInt64(bitPattern: try c.decode(Int64.self))
			}
		}
	}

	struct OperandValue: Codable, Sendable {
		public var ct: Int
		public var index: Int
		public var table: Int
	}

	struct Scope: Codable, Sendable {
		public var id: Int
		public var parent: Int
	}

	struct SubtableSym: Codable, Sendable {
		public var children: Children
		public var id: Int
		public var numct: Int

		@CaseAccessors
		public enum Child: Codable, Sendable {
			case constructor(Constructor)
			case decision(DecisionNode)
		}

		public struct Children: Codable, Sendable {
			var constructors: [Constructor]
			var decision: DecisionNode

			public init(from decoder: any Decoder) throws {
				var c = try decoder.unkeyedContainer()
				(constructors, decision) = try c.decodeWhile(Child.self, is: \.constructor, \.decision)
			}

			public func encode(to encoder: any Encoder) throws {
				var c = encoder.unkeyedContainer()
				for constructor in constructors {
					try c.encode(Child.constructor(constructor))
				}
				try c.encode(Child.decision(decision))
			}
		}
	}

	struct Constructor: Codable, Sendable {
		public var children: Children
		public var first: Int
		public var length: Int
		public var line: Int
		/// The scope id of the constructor.
		public var parent: Int
		public var source: Int

		public func debugDescription(
			symtab: SymbolTable.Children,
			sourcefiles: Sourcefiles,
		) -> String {
			let sourcename = sourcefiles.children.sourcefiles[source]
			var output = "// \(length)@\(first)\n// \(sourcename):\(line) \(parent)\n"
			var exprs: [String] = []
			exprs.reserveCapacity(children.context.count + children.operands.count + children.tpls.count)
			for context in children.context {
				exprs.append("\(context)")
			}
			for op in children.operands {
				let sym = symtab.headers.indices.contains(op.id) ? symtab.headers[op.id].name : "#\(op.id)"
				exprs.append(sym)
			}
			output += "case \(exprs.joined(separator: " && ")):\n"
			for tpl in children.tpls {
				for input in tpl.children.inputs {
					output += "\(input)\n"
				}
				if let handle = tpl.children.output {
					output += "return \(handle)\n"
				}
			}
			if !children.print.isEmpty {
				output += "assembly += \""
				for piece in children.print {
					switch piece {
					case let .piece(x):
						output += x
					case let .op(x):
						let id = children.operands[x].id
						let name = symtab.headers.indices.contains(id) ? symtab.headers[id].name : "#\(id)"
						output += "\\(\(name))"
					}
				}
				output += "\"\n"
			}
			return output
		}

		@CaseAccessors
		public enum Child: Codable, Sendable {
			case commit(ContextCommit)
			case construct_tpl(ConstructTpl)
			case context_op(ContextOp)
			case oper(ConstructorOperand)
			case opprint(_PrintOp)
			case print(_Print)

			var context: ConstructorContext? {
				switch self {
				case let .commit(x): .commit(x)
				case let .context_op(x): .context_op(x)
				default: nil
				}
			}

			var piece: ConstructorPrint? {
				switch self {
				case let .opprint(x): .op(x.id)
				case let .print(x): .piece(x.piece.literal)
				default: nil
				}
			}
		}

		public struct Children: Codable, Sendable {
			public var operands: [ConstructorOperand]
			public var print: [ConstructorPrint]
			public var context: [ConstructorContext]
			public var tpls: [ConstructTpl]

			public init(from decoder: any Decoder) throws {
				var c = try decoder.unkeyedContainer()
				(operands, print, context, tpls) = try c.decodeWhile(Child.self, is: \.oper, \.piece, \.context, \.construct_tpl)
			}

			public func encode(to encoder: any Encoder) throws {
				var c = encoder.unkeyedContainer()
				for operand in operands {
					try c.encode(Child.oper(operand))
				}
				for piece in print {
					try c.encode(piece)
				}
				for context in context {
					try c.encode(context)
				}
				for tpl in tpls {
					try c.encode(Child.construct_tpl(tpl))
				}
			}
		}
	}

	@CaseAccessors
	enum ConstructorContext: Codable, Sendable {
		case commit(ContextCommit)
		case context_op(ContextOp)
	}

	@CaseAccessors
	enum ConstructorPrint: Codable, Sendable {
		case piece(String)
		case op(Int)
	}

	struct ConstructorOperand: Codable, Sendable {
		public var id: Int
	}

	struct _PrintOp: Codable, Sendable {
		public var id: Int
	}

	struct ContextCommit: Codable, Sendable {
		public var flow: Bool
		public var id: Int
		public var mask: Int
		public var number: Int
	}

	struct ConstructTpl: Codable, Sendable {
		public var children: Children
		// Defaults to 0
		public var delay: Int?
		public var labels: Int?
		public var section: Int?

		@CaseAccessors
		public enum Child: Codable, Sendable {
			case handle_tpl(HandleTpl)
			case null(Null)
			case op_tpl(OpTpl)

			var asHandleTpl: HandleTpl?? {
				switch self {
				case let .handle_tpl(x): .some(x)
				case .null: .some(.none)
				default: .none
				}
			}
		}

		public struct Children: Codable, Sendable {
			var output: HandleTpl?
			var inputs: [OpTpl]

			public init(from decoder: any Decoder) throws {
				var c = try decoder.unkeyedContainer()
				output = try c.decode(Child.self, as: \.asHandleTpl)
				inputs = try c.decodeRemaining(Child.self, as: \.op_tpl)
			}

			public func encode(to encoder: any Encoder) throws {
				var c = encoder.unkeyedContainer()
				if let output {
					try c.encode(Child.handle_tpl(output))
				} else {
					try c.encode(Child.null(.init()))
				}
				for op in inputs {
					try c.encode(Child.op_tpl(op))
				}
			}
		}
	}

	struct Null: Codable, Sendable {}

	struct HandleTpl: Codable, Sendable, CustomStringConvertible {
		public var children: Children

		public var description: String {
			"*[\(children.space)]:\(children.size) \(children.ptroffset) (ptrspace: \(children.ptrspace), ptrsize: \(children.ptrsize), temp_space: \(children.temp_space), temp_offset: \(children.temp_offset))"
		}

		public struct Children: Codable, Sendable {
			var space: ConstTpl
			var size: ConstTpl
			var ptrspace: ConstTpl
			var ptroffset: ConstTpl
			var ptrsize: ConstTpl
			var temp_space: ConstTpl
			var temp_offset: ConstTpl

			public init(from decoder: any Decoder) throws {
				var c = try decoder.unkeyedContainer()
				space = try c.decode(ConstTpl.self)
				size = try c.decode(ConstTpl.self)
				ptrspace = try c.decode(ConstTpl.self)
				ptroffset = try c.decode(ConstTpl.self)
				ptrsize = try c.decode(ConstTpl.self)
				temp_space = try c.decode(ConstTpl.self)
				temp_offset = try c.decode(ConstTpl.self)
			}

			public func encode(to encoder: any Encoder) throws {
				var c = encoder.unkeyedContainer()
				try c.encode(space)
				try c.encode(size)
				try c.encode(ptrspace)
				try c.encode(ptroffset)
				try c.encode(ptrsize)
				try c.encode(temp_space)
				try c.encode(temp_offset)
			}
		}
	}

	enum ConstTpl: Codable, Sendable, Equatable, CustomStringConvertible {
		case const_curspace(CurrentSpace)
		case const_curspace_size(SizeOfCurrentSpace)
		case const_handle(Handle)
		case const_next(Next)
		case const_next2(Next2)
		case const_real(ConstantValue)
		case const_relative(ConstantValue)
		case const_spaceid(SpaceId)
		case const_start(Start)

		public var description: String {
			switch self {
			case .const_curspace: "curspace"
			case .const_curspace_size: "sizeof(curspace)"
			case let .const_handle(x): "handle(i:\(x.val),select:\(x.s),offset:\(x.plus ?? 0))"
			case .const_next: "next"
			case .const_next2: "next2"
			case let .const_real(x): x.description
			case let .const_relative(x): x.description
			case let .const_spaceid(x): x.space
			case .const_start: "start"
			}
		}

		public struct CurrentSpace: Codable, Sendable, Equatable {}
		public struct SizeOfCurrentSpace: Codable, Sendable, Equatable {}

		public struct Handle: Codable, Sendable, Equatable {
			public var s: Select
			public var val: Int
			public var plus: Int?
		}

		public enum Select: UInt8, Codable, Sendable, Equatable {
			case space, v_offset, v_size, v_offset_plus
		}

		public struct Next: Codable, Sendable, Equatable {}
		public struct Next2: Codable, Sendable, Equatable {}

		public struct SpaceId: Codable, Sendable, Equatable {
			public var space: String
		}

		public struct Start: Codable, Sendable, Equatable {}
	}

	struct OpTpl: Codable, Sendable, CustomStringConvertible {
		public var children: Children
		public var code: Code

		public var description: String {
			var description = "\(code) "
			if let out = children.output {
				description += out.description
				description += " "
			}
			description += children.inputs
				.map(\.description)
				.joined(separator: " ")
			return description
		}

		@CaseAccessors
		public enum Child: Codable, Sendable {
			case null(Null)
			case varnode_tpl(VarnodeTpl)

			var output: VarnodeTpl?? {
				switch self {
				case .null: .some(.none)
				case let .varnode_tpl(x): .some(x)
				}
			}
		}

		public struct Children: Codable, Sendable {
			var output: VarnodeTpl?
			var inputs: [VarnodeTpl]

			public init(from decoder: any Decoder) throws {
				var c = try decoder.unkeyedContainer()
				output = try c.decode(Child.self, as: \.output)
				inputs = try c.decodeRemaining(Child.self, as: \.varnode_tpl)
			}

			public func encode(to encoder: any Encoder) throws {
				var c = encoder.unkeyedContainer()
				if let output {
					try c.encode(Child.varnode_tpl(output))
				} else {
					try c.encode(Child.null(.init()))
				}
				for op in inputs {
					try c.encode(Child.varnode_tpl(op))
				}
			}
		}
	}

	struct VarnodeTpl: Codable, Sendable, CustomStringConvertible {
		public var children: Children

		public var description: String {
			if children.space == .const_spaceid(.init(space: "const")) {
				return "\(children.offset)i\(children.size)"
			}
			return "\(children.space)[\(children.offset)]i\(children.size)"
		}

		public struct Children: Codable, Sendable {
			var space: ConstTpl
			var offset: ConstTpl
			var size: ConstTpl

			public init(from decoder: any Decoder) throws {
				var c = try decoder.unkeyedContainer()
				space = try c.decode(ConstTpl.self)
				offset = try c.decode(ConstTpl.self)
				size = try c.decode(ConstTpl.self)
			}

			public func encode(to encoder: any Encoder) throws {
				var c = encoder.unkeyedContainer()
				try c.encode(space)
				try c.encode(offset)
				try c.encode(size)
			}
		}
	}

	enum Code: String, Codable, Sendable {
		case boolAnd = "BOOL_AND"
		case boolNegate = "BOOL_NEGATE"
		case boolOr = "BOOL_OR"
		case boolXor = "BOOL_XOR"
		case branch = "BRANCH"
		case branchind = "BRANCHIND"
		case build = "BUILD"
		case call = "CALL"
		case callind = "CALLIND"
		case callother = "CALLOTHER"
		case cbranch = "CBRANCH"
		case ceil = "CEIL"
		case codeRETURN = "RETURN"
		case copy = "COPY"
		case cpoolref = "CPOOLREF"
		case crossbuild = "CROSSBUILD"
		case delaySlot = "DELAY_SLOT"
		case float2Float = "FLOAT2FLOAT"
		case floatAbs = "FLOAT_ABS"
		case floatAdd = "FLOAT_ADD"
		case floatDiv = "FLOAT_DIV"
		case floatEqual = "FLOAT_EQUAL"
		case floatLess = "FLOAT_LESS"
		case floatLessequal = "FLOAT_LESSEQUAL"
		case floatMult = "FLOAT_MULT"
		case floatNan = "FLOAT_NAN"
		case floatNeg = "FLOAT_NEG"
		case floatNotequal = "FLOAT_NOTEQUAL"
		case floatSqrt = "FLOAT_SQRT"
		case floatSub = "FLOAT_SUB"
		case floor = "FLOOR"
		case int2Comp = "INT_2COMP"
		case int2Float = "INT2FLOAT"
		case intAdd = "INT_ADD"
		case intAnd = "INT_AND"
		case intCarry = "INT_CARRY"
		case intDiv = "INT_DIV"
		case intEqual = "INT_EQUAL"
		case intLeft = "INT_LEFT"
		case intLess = "INT_LESS"
		case intLessequal = "INT_LESSEQUAL"
		case intMult = "INT_MULT"
		case intNegate = "INT_NEGATE"
		case intNotequal = "INT_NOTEQUAL"
		case intOr = "INT_OR"
		case intRem = "INT_REM"
		case intRight = "INT_RIGHT"
		case intSborrow = "INT_SBORROW"
		case intScarry = "INT_SCARRY"
		case intSdiv = "INT_SDIV"
		case intSext = "INT_SEXT"
		case intSless = "INT_SLESS"
		case intSlessequal = "INT_SLESSEQUAL"
		case intSrem = "INT_SREM"
		case intSright = "INT_SRIGHT"
		case intSub = "INT_SUB"
		case intXor = "INT_XOR"
		case intZext = "INT_ZEXT"
		case label = "LABEL"
		case load = "LOAD"
		case lzcount = "LZCOUNT"
		case new = "NEW"
		case popcount = "POPCOUNT"
		case round = "ROUND"
		case store = "STORE"
		case subpiece = "SUBPIECE"
		case trunc = "TRUNC"
	}

	struct ContextOp: Codable, Sendable {
		public var children: [PatternExpr]
		public var i: Int
		public var mask: Int
		public var shift: Int
	}

	struct _Print: Codable, Sendable {
		/// xml2json sometimes produced Double, should've always been a String
		public var piece: Piece

		public struct Piece: Codable, Sendable {
			public var literal: String

			public init(from decoder: Decoder) throws {
				let container = try decoder.singleValueContainer()
				if let x = try? container.decode(Int.self) {
					literal = x.description
					return
				}
				if let x = try? container.decode(Decimal.self) {
					literal = x.description
					return
				}
				if let x = try? container.decode(String.self) {
					literal = x
					return
				}
				throw DecodingError.typeMismatch(Piece.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Wrong type for Piece"))
			}

			public func encode(to encoder: Encoder) throws {
				var container = encoder.singleValueContainer()
				try container.encode(literal)
			}
		}
	}

	struct DecisionNode: Codable, Sendable, CustomDebugStringConvertible {
		public var children: Children?
		/// Whether this decision node acts on bits of the context or the instruction.
		public var context: Bool
		/// The number of children
		public var number: Int
		public var size: Int
		public var startbit: Int

		public var debugDescription: String {
			debugDescription(depth: 0, using: [], symtab: .init(), sourcefiles: .init(children: .init()))
		}

		func debugDescription(
			depth: Int,
			using constructors: [Constructor],
			symtab: SymbolTable.Children,
			sourcefiles: Sourcefiles,
		) -> String {
			var description = switch true {
			case size == 0: "terminal"
			case context: "context"
			default: "instruction"
			}
			if size != 0 {
				description += " [\(size) bits @ \(startbit)]"
			}
			guard let children else { return description }

			var i = 0
			let lastIndex = children.candidates.count + children.subdecisions.count - 1
			var isLast: Bool { i == lastIndex }

			func tree() {
				description += "\n\(isLast ? "└" : "├") "
			}

			for pair in children.candidates {
				tree()
				let ct = constructors.indices.contains(pair.id)
					? constructors[pair.id].debugDescription(
						symtab: symtab,
						sourcefiles: sourcefiles)
					: "#\(pair.id)"
				let pattern = pair.children.pattern.description
				description += "\(pattern)\n\(ct)"
					.replacing("\n", with: isLast ? "\n  " : "\n│ ")
				i += 1
			}

			for d in children.subdecisions {
				tree()
				description += d
					.debugDescription(
						depth: depth + 1,
						using: constructors,
						symtab: symtab,
						sourcefiles: sourcefiles)
					.replacing("\n", with: isLast ? "\n  " : "\n│ ")
				i += 1
			}
			description += "\n"
			return description
		}

		public enum Child: Codable, Sendable {
			case decision(DecisionNode)
			case pair(Candidate)
		}

		public struct Children: Codable, Sendable {
			/// The sub-decisions on the rest of the patterns.
			var subdecisions: [DecisionNode] = []
			/// The constructors to call based on the decision.
			var candidates: [Candidate] = []

			public init(from decoder: any Decoder) throws {
				var c = try decoder.unkeyedContainer()
				subdecisions.reserveCapacity(c.remainingCount)
				candidates.reserveCapacity(c.remainingCount)
				while !c.isAtEnd {
					switch try c.decode(Child.self) {
					case let .decision(decision): subdecisions.append(decision)
					case let .pair(pair): candidates.append(pair)
					}
				}
			}
		}

		public struct Candidate: Codable, Sendable {
			/// Constructor Id
			public var id: Int
			public var children: Children

			public struct Children: Codable, Sendable {
				var pattern: DisjointPattern

				public init(from decoder: any Decoder) throws {
					var c = try decoder.unkeyedContainer()
					pattern = try c.decode(DisjointPattern.self)
				}

				public func encode(to encoder: any Encoder) throws {
					var c = encoder.unkeyedContainer()
					try c.encode(pattern)
				}
			}
		}
	}

	@CaseAccessors
	enum DisjointPattern: Codable, Sendable, CustomStringConvertible {
		case combine_pat(CombinePattern)
		case context_pat(Pattern)
		case instruct_pat(Pattern)

		public func description(using symtab: SymbolTable.Children) -> String {
			switch self {
			case let .combine_pat(pattern):
				"\(pattern.children.context.descriptionOfContext(using: symtab)) \(pattern.children.instr.descriptionOfInstruction(using: symtab))"
			case let .context_pat(pattern):
				pattern.descriptionOfContext(using: symtab)
			case let .instruct_pat(pattern):
				pattern.descriptionOfInstruction(using: symtab)
			}
		}

		public var description: String {
			switch self {
			case let .combine_pat(pattern): 
				"context \(pattern.children.context) instruction \(pattern.children.instr)"
			case let .context_pat(pattern):
				"context \(pattern)"
			case let .instruct_pat(pattern):
				"instruction \(pattern)"
			}
		}
	}

	struct CombinePattern: Codable, Sendable {
		public var children: Children

		@CaseAccessors
		public enum Child: Codable, Sendable {
			case context_pat(Pattern)
			case instruct_pat(Pattern)
		}

		public struct Children: Codable, Sendable {
			public var context: Pattern
			public var instr: Pattern

			public init(from decoder: any Decoder) throws {
				var c = try decoder.unkeyedContainer()
				context = try c.decode(Child.self, as: \.context_pat)
				instr = try c.decode(Child.self, as: \.instruct_pat)
			}
		}
	}

	struct Pattern: Codable, Sendable, CustomStringConvertible {
		public var children: Children

		public func descriptionOfContext(
			using symtab: SymbolTable.Children
		) -> String {
			description(of: "context", using: symtab.resolve(context:))
		}

		public func descriptionOfInstruction(
			using symtab: SymbolTable.Children
		) -> String {
			description(of: "instruction", using: symtab.resolve(instruction:))
		}

		public func description(
			of label: String,
			using resolve: (ClosedRange<Int>) -> SymbolHeader?,
		) -> String {
			var output = "\(label) "
			for block in children.blocks {
				if let header = resolve(block.range) {
					output += header.name
				} else {
					output += "\(block)"
				}
				output += " "
			}
			return output
		}

		public var description: String {
			children.blocks.lazy
				.map(\.description)
				.joined(separator: " && ")
		}

		@CaseAccessors
		public enum Child: Codable, Sendable {
			case pat_block(PatternBlock)
		}

		public struct Children: Codable, Sendable {
			var blocks: [PatternBlock]

			public init(from decoder: any Decoder) throws {
				var c = try decoder.unkeyedContainer()
				blocks = try c.decodeRemaining(Child.self, as: \.pat_block)
			}

			public func encode(to encoder: any Encoder) throws {
				var c = encoder.unkeyedContainer()
				try c.encode(blocks.map(Child.pat_block))
			}
		}
	}

	struct PatternBlock: Codable, Sendable, CustomStringConvertible {
		public var children: Children?
		/// Offset to first non-zero byte of mask
		public var off: Int
		/// Last byte(+1) containing nonzero mask, or the number of bytes in this pattern.
		public var nonzero: Int

		public var range: ClosedRange<Int> {
			guard let children else { return 0...0 }
			let low = children.words[0].mask.leadingZeroBitCount
			var high = children.words[children.words.count - 1].mask.trailingZeroBitCount
			high = 32 - high
			high += 32 * (children.words.count - 1)
			high -= 1
			return low...high
		}

		public var description: String {
			let mask = (children?.words ?? []).lazy
				.flatMap { $0.description.split(separator: ":") }
				.prefix(nonzero)
				.joined(separator: ":")
			return "@\(off) [\(mask)]"
		}

		@CaseAccessors
		public enum Child: Codable, Sendable {
			case mask_word(MaskWord)
		}

		public struct Children: Codable, Sendable {
			var words: [MaskWord]

			public init(from decoder: any Decoder) throws {
				var c = try decoder.unkeyedContainer()
				words = try c.decodeRemaining(Child.self, as: \.mask_word)
			}

			public func encode(to encoder: any Encoder) throws {
				var c = encoder.unkeyedContainer()
				try c.encode(words.map(Child.mask_word))
			}
		}

		public struct MaskWord: Codable, Sendable, CustomStringConvertible {
			public var mask: UInt32
			public var val: UInt32

			public func description(offset: Int, nonzero: Int) -> String {
				let mask = mask >> (offset * 8)
				let val = val >> (offset * 8)
				return "0x\(String(mask, radix: 16)) is 0x\(String(val, radix: 16))"
			}

			public static func description<I: FixedWidthInteger>(mask: I, val: I) -> String {
				var mask = String(mask, radix: 2)
				if mask.count < I.bitWidth {
					mask = String(repeating: "0", count: I.bitWidth - mask.count) + mask
				}
				var val = String(val, radix: 2)
				if val.count < I.bitWidth {
					val = String(repeating: "0", count: I.bitWidth - val.count) + val
				}
				var result = ""
				result.reserveCapacity(I.bitWidth + I.bitWidth / 8 - 1)
				var m = mask.startIndex
				var v = val.startIndex
				while m < mask.endIndex, v < val.endIndex {
					let c = switch (mask[m], val[v]) {
					case ("0", _): "x"
					case ("1", "0"): "0"
					case ("1", "1"): "1"
					default: "?"
					}
					result.append(c)
					m = mask.index(after: m)
					v = val.index(after: v)
				}
				for offset in stride(from: I.bitWidth - 8, through: 1, by: -8) {
					let i = result.index(result.startIndex, offsetBy: offset)
					result.insert(":", at: i)
				}
				return result
			}

			public var description: String {
				Self.description(mask: mask, val: val)
			}
		}
	}

	struct Userop: Codable, Sendable {
		public var id: Int
		public var index: Int
	}

	struct ValueSym: Codable, Sendable {
		/// Always a PatternValue
		public var children: [PatternExpr]
		public var id: Int
	}

	struct ValuemapSym: Codable, Sendable {
		/// `[patval, valuetab...]`
		public var children: [PatternExprOr<Child>]
		public var id: Int

		public enum Child: Codable, Sendable {
			case valuetab(ConstantValue)
		}
	}

	struct VarlistSym: Codable, Sendable {
		/// `[patval, varnode_table... (null or public var)]`
		public var children: [PatternExprOr<Child>]
		public var id: Int

		public enum Child: Codable, Sendable {
			case null(Null)
			case `var`(Var)
		}

		public struct Var: Codable, Sendable {
			public var id: Int
		}
	}

	struct VarnodeSym: Codable, Sendable {
		public var id: Int
		public var off: Int
		public var size: Int
		public var space: String
	}
}
