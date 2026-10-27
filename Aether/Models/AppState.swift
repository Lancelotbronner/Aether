import SwiftUI
import SwiftData
import Combine
import UniformTypeIdentifiers
import OSLog
import AetherKit

@Observable
final class AppState {
	var currentFile: BinaryFile?
	var isLoading = false

	// MARK: - Selection

	var selectedBinary: BinaryModel?
	var selectedSegment: SegmentModel?
	var selectedSection: SectionModel?
	var selectedFunction: ProcedureModel?

	var selectedAddress: UInt64 {
		get { selectedAddressRange.lowerBound }
		set { selectedAddressRange = newValue..<(newValue + 1) }
	}
	var selectedAddressRange: Range<UInt64> = 0..<0

	var functionNavigator: ProcedureModel? {
		get { selectedFunction }
		set {
			guard let newValue else { return }
			selectedBinary = newValue.binary
			selectedFunction = newValue
			goToAddress(newValue.symbol.address)
		}
	}

	var sectionNavigator: SectionModel? {
		get { selectedSection }
		set {
			guard let newValue else { return }
			selectedBinary = newValue.binary
			selectedSection = newValue
			goToAddress(newValue.address)
		}
	}

	@ObservationIgnored
	var selectedInstruction: Instruction? {
		_read {
			let selected = instructions(in: selectedAddressRange)
			if selected.count == 1 {
				yield selected[selected.startIndex]
			} else {
				yield nil
			}
		}
	}

	var programNavigatorSelection: Set<ProgramNavigatorSelection> = []

	// MARK: - UI State
	var showCFG = false
	var showDecompiler = true
	var showHexView = true
	var showGoToAddress = false
	var showSearch = false
	var sidebarSelection: NavigatorTab = .functions
	var isInspectorPresented = false

	// MARK: - Advanced Analysis UI State
	var showCallGraph = false
	var showCryptoDetection = false
	var showDeobfuscation = false
	var showTypeRecovery = false
	var showIdiomRecognition = false
	var showExportSheet = false
	var showPseudoCode = false
	var showJumpTable = false
	var showSettings = false
	var showSecurityAnalysis = false
	var showFridaScript = false

	// MARK: - Frida Script Generation State
	var isGeneratingFridaScript = false
	var fridaScriptResult: FridaScriptResult?
	var aiFridaScriptResult: AIFridaScriptResult?
	var fridaScriptError: String?
	var selectedFridaPlatform: FridaPlatform = .macOS
	var selectedFridaHookType: FridaHookType = .trace
	var preConfiguredBypassTechniques: [String] = []
	var preConfiguredPatchPoints: [String] = []

	// MARK: - AI Analysis State
	var isAnalyzingWithAI = false
	var securityAnalysisResult: SecurityAnalysisResult?
	var securityAnalysisError: String?
	private let aiClient = AIClient()

	// MARK: - AI Chat State
	var showAIChat = false
	var chatMessages: [ChatMessage] = []
	var isChatLoading = false
	var chatError: String?

	// MARK: - AI Explain Code State
	var showExplainCode = false
	var codeExplanation: CodeExplanation?
	var isExplainingCode = false
	var explainError: String?

	// MARK: - AI Variable Rename State
	var showAIRename = false
	var suggestedRenames: [VariableRename] = []
	var isGeneratingRenames = false
	var renameError: String?

	// MARK: - Malware Analysis State
	var showMalwareDashboard = false
	var showImportExportBrowser = false
	var showEntropyView = false
	var isAnalyzingMalware = false
	var malwareReport: MalwareReport?

	// MARK: - Malware Flow State
	var showMalwareFlow = false
	var isAnalyzingMalwareFlow = false
	var malwareFlowResult: MalwareFlowResult?
	var malwareFlowError: String?

	// MARK: - Advanced Analysis Results
	var cryptoFindings: [AdvancedCryptoDetector.CryptoFinding] = []
	var deobfuscationReport: DeobfuscationReportWrapper?
	var recoveredTypes: [RecoveredTypeWrapper] = []
	var recognizedIdioms: [IdiomRecognizer.Idiom] = []
	var structuredCode: String = ""

	// MARK: - Operand Symbol Resolution (Task 10)
	//
	// O(1) lookups behind OperandsView, built lazily on the MainActor from
	// the models (the `symbols` / `procedures` relationships are already in
	// memory — no fetch needed). Live `SymbolModel` refs (not copied
	// strings) so a user rename stays fresh: `displayName` reads `name` at
	// render time. A re-Load keeps the same `BinaryModel`, so the tables
	// are also dropped by `resetDisassemblyCache()` — otherwise the
	// reset-first re-parse (new symbol rows) would never be seen.
	@ObservationIgnored private var operandSymbolsByAddress: [UInt64: SymbolModel] = [:]
	@ObservationIgnored private var operandSymbolsByName: [String: SymbolModel] = [:]
	@ObservationIgnored private var operandLookupsFor: PersistentIdentifier?

	// MARK: - Disassembly Cache
	var decompilerOutput: String = ""

	// MARK: - User Annotations
	// Renames, comments, and bookmarks are SwiftData rows now
	// (SymbolModel.name, AnnotationModel, BookmarkModel) — the model-backed
	// mutators below keep them in the document, with undo through the
	// window's UndoManager via registerUndoRedo.

	// MARK: - Services
	@ObservationIgnored var undoManager: UndoManager?
	@ObservationIgnored var modelContext: ModelContext?
	private let disassembler = DisassemblerEngine()
	private let functionAnalyzer = FunctionAnalyzer()
	private let stringAnalyzer = StringAnalyzer()
	private let xrefAnalyzer = XRefAnalyzer()
	private let decompiler = Decompiler()
	private let fridaGenerator = FridaScriptGenerator()

	// MARK: - Malware Analysis

	func analyzeMalware() {
//		guard let binary = selectedBinary else { return }
//		isAnalyzingMalware = true
//
//		Task.detached(priority: .userInitiated) {
//			let analyzer = MalwareAnalyzer()
//			let report = analyzer.analyze(binary: binary)
//			await MainActor.run { [weak self] in
//				self?.malwareReport = report
//				self?.isAnalyzingMalware = false
//			}
//		}
	}

	// MARK: - Malware Flow Analysis

	var apiKey: String {
		KeychainHelper.load(key: "AIAPIKey") ?? ""
	}

	func analyzeMalwareFlow() {
//		guard let binary = selectedBinary else { return }
//		guard let apiKey = KeychainHelper.load(key: "AIAPIKey"), !apiKey.isEmpty else {
//			malwareFlowError = "No API key configured. Please add your AI API key in Settings."
//			return
//		}
//
//		isAnalyzingMalwareFlow = true
//		malwareFlowResult = nil
//		malwareFlowError = nil
//
//		// Run malware analysis first if not done yet
//		if malwareReport == nil {
//			let analyzer = MalwareAnalyzer()
//			malwareReport = analyzer.analyze(binary: binary)
//		}
//
//		let report = malwareReport!
//
//		Task {
//			do {
//				let sectionData = binary.sections.map { section -> (name: String, size: UInt64, entropy: Double, permissions: String) in
//					let sectionEntropy = report.entropyResult.sectionEntropies.first { $0.name == section.name }
//					// PE flags: R=0x40000000, W=0x80000000, X=0x20000000
//					let r = (section.flags & 0x40000000 != 0) || !section.isExecutable // default readable
//					let w = section.flags & 0x80000000 != 0
//					let x = section.isExecutable
//					let perms = "\(r ? "R" : "-")\(w ? "W" : "-")\(x ? "X" : "-")"
//					return (
//						name: section.name,
//						size: section.size,
//						entropy: sectionEntropy?.entropy ?? 0,
//						permissions: perms
//					)
//				}
//
//				let importNames = imports.map { $0.name }
//				let exportNames = exports.map { $0.name }
//				let stringValues = strings.prefix(100).map { $0.value }
//				let anomalyDescs = report.anomalies.map { "\($0.severity.rawValue): \($0.title) - \($0.description)" }
//
//				let result = try await aiClient.analyzeMalwareFlowAsync(
//					binaryName: binary.name,
//					sections: sectionData,
//					imports: importNames,
//					exports: exportNames,
//					strings: Array(stringValues),
//					entropyOverall: report.entropyResult.overallEntropy,
//					anomalies: anomalyDescs,
//					apiKey: apiKey
//				)
//
//				await MainActor.run {
//					self.malwareFlowResult = result
//					self.isAnalyzingMalwareFlow = false
//				}
//			} catch {
//				await MainActor.run {
//					self.malwareFlowError = error.localizedDescription
//					self.isAnalyzingMalwareFlow = false
//				}
//			}
//		}
	}

	// MARK: - Analysis

	func analyzeAll() {
		guard selectedBinary != nil else { return }
		Task {
			await performAnalysis()
		}
	}

	private func performAnalysis() async {
		guard let binary = selectedBinary else { return }

//		isLoading = true
//
//		// Find functions
//		loadingMessage = "Analyzing functions..."
//		loadingProgress = 0.4
//		self.functions = await functionAnalyzer.analyze(binary: binary, disassembler: disassembler)
//
//		// Find strings
//		loadingMessage = "Extracting strings..."
//		loadingProgress = 0.6
//		self.strings = stringAnalyzer.analyze(binary: binary)
//
//		// Build cross-references
//		loadingMessage = "Building cross-references..."
//		loadingProgress = 0.8
//		self.xrefs = await xrefAnalyzer.analyze(binary: binary, functions: functions, disassembler: disassembler)
//
//		// Extract imports/exports
//		loadingMessage = "Processing symbols..."
//		loadingProgress = 0.9
//		self.imports = binary.symbols.filter { $0.isImport }
//		self.exports = binary.symbols.filter { $0.isExport }
//
//		loadingProgress = 1.0
//		loadingMessage = "Analysis complete"
//		isLoading = false
	}

	func findFunctions() {
//		guard let binary = selectedBinary else { return }
//		Task {
//			isLoading = true
//			loadingMessage = "Finding functions..."
//			self.functions = await functionAnalyzer.analyze(binary: binary, disassembler: disassembler)
//			isLoading = false
//		}
	}

	// MARK: - Advanced Analysis

	func runCryptoDetection() {
//		guard let binary = selectedBinary else { return }
//		Task {
//			isLoading = true
//			loadingMessage = "Detecting cryptographic patterns..."
//			let detector = AdvancedCryptoDetector()
//			self.cryptoFindings = detector.scan(binary: binary)
//			isLoading = false
//			showCryptoDetection = true
//		}
	}

	func runDeobfuscation() {
//		guard let binary = selectedBinary, let function = selectedFunction else { return }
//		Task {
//			isLoading = true
//			loadingMessage = "Analyzing obfuscation..."
//			let deobfuscator = Deobfuscator()
//			let instructions = await disassembleFunction(function)
//
//			// Build basic blocks for analysis
//			var basicBlocks: [BasicBlock] = []
//			if !instructions.isEmpty {
//				let bb = BasicBlock(startAddress: function.startAddress, endAddress: function.endAddress, instructions: instructions)
//				basicBlocks.append(bb)
//			}
//
//			var func_ = function
//			func_.basicBlocks = basicBlocks
//			let findings = deobfuscator.analyze(function: func_, binary: binary)
//			let result = deobfuscator.deobfuscate(function: func_, binary: binary)
//
//			self.deobfuscationReport = DeobfuscationReportWrapper.from(result, findings: findings)
//			isLoading = false
//			showDeobfuscation = true
//		}
	}

	func runTypeRecovery() {
//		guard let binary = selectedBinary, let function = selectedFunction else { return }
//		Task {
//			isLoading = true
//			loadingMessage = "Recovering types..."
//			let recovery = TypeRecovery()
//			let instructions = await disassembleFunction(function)
//
//			var basicBlocks: [BasicBlock] = []
//			if !instructions.isEmpty {
//				let bb = BasicBlock(startAddress: function.startAddress, endAddress: function.endAddress, instructions: instructions)
//				basicBlocks.append(bb)
//			}
//
//			self.recoveredTypes = recovery.recoverTypes(function: function, blocks: basicBlocks, binary: binary)
//			isLoading = false
//			showTypeRecovery = true
//		}
	}

	func runIdiomRecognition() {
//		guard let function = selectedFunction else { return }
//		Task {
//			isLoading = true
//			loadingMessage = "Recognizing code idioms..."
//			let recognizer = IdiomRecognizer()
//			let instructions = await disassembleFunction(function)
//
//			var basicBlocks: [BasicBlock] = []
//			if !instructions.isEmpty {
//				let bb = BasicBlock(startAddress: function.startAddress, endAddress: function.endAddress, instructions: instructions)
//				basicBlocks.append(bb)
//			}
//
//			var func_ = function
//			func_.basicBlocks = basicBlocks
//			self.recognizedIdioms = recognizer.recognize(function: func_)
//			isLoading = false
//			showIdiomRecognition = true
//		}
	}

	func generateStructuredCode() {
//		guard let binary = selectedBinary, let function = selectedFunction else { return }
//		Task {
//			isLoading = true
//			loadingMessage = "Generating structured code..."
//			let instructions = await disassembleFunction(function)
//
//			guard !instructions.isEmpty else {
//				self.structuredCode = "// No instructions found for function"
//				isLoading = false
//				showPseudoCode = true
//				return
//			}
//
//			// Build proper basic blocks by splitting at control flow instructions
//			let basicBlocks = buildBasicBlocks(from: instructions, function: function)
//
//			var func_ = function
//			func_.basicBlocks = basicBlocks
//
//			// Generate pseudo-code directly from instructions
//			self.structuredCode = generatePseudoCodeFromInstructions(instructions, function: func_, binary: binary)
//			isLoading = false
//			showPseudoCode = true
//		}
	}

	private func buildBasicBlocks(from instructions: ArraySlice<Instruction>, function: Function) -> [BasicBlock] {
		guard !instructions.isEmpty else { return [] }

		var blocks: [BasicBlock] = []
		var currentBlockStart = 0
		var leaders: Set<UInt64> = [instructions[0].address]

		// Find all leaders (start of basic blocks)
		for (index, insn) in instructions.enumerated() {
			// After a branch/jump, the next instruction is a leader
			if insn.type == .jump || insn.type == .conditionalJump || insn.type == .call || insn.type == .return {
				if index + 1 < instructions.count {
					leaders.insert(instructions[index + 1].address)
				}
				// Target of jump is also a leader
				if let target = insn.branchTarget {
					leaders.insert(target)
				}
			}
		}

		// Create basic blocks
		let sortedLeaders = leaders.sorted()
		for (i, leaderAddr) in sortedLeaders.enumerated() {
			guard let startIdx = instructions.firstIndex(where: { $0.address == leaderAddr }) else { continue }

			let endIdx: Int
			if i + 1 < sortedLeaders.count {
				let nextLeader = sortedLeaders[i + 1]
				endIdx = instructions.firstIndex(where: { $0.address >= nextLeader }) ?? instructions.count
			} else {
				endIdx = instructions.count
			}

			if startIdx < endIdx {
				let blockInsns = instructions[startIdx..<endIdx]
				let endAddr = blockInsns.last.map { $0.address + UInt64($0.size) } ?? leaderAddr
				let bb = BasicBlock(startAddress: leaderAddr, endAddress: endAddr, instructions: blockInsns)
				blocks.append(bb)
			}
		}

		return blocks
	}

	private func generatePseudoCodeFromInstructions(_ instructions: ArraySlice<Instruction>, function: Function, binary: BinaryFile) -> String {
		var output = "// Function: \(function.displayName)\n"
		output += "// Address: 0x\(String(format: "%llX", function.startAddress))\n"
		output += "// Size: \(function.size) bytes\n\n"

		// Generate function signature
		output += "void \(function.displayName.replacingOccurrences(of: "-", with: "_").replacingOccurrences(of: "[", with: "").replacingOccurrences(of: "]", with: "").replacingOccurrences(of: " ", with: "_"))() {\n"

		var indent = "    "
		var pendingElse = false
		var loopStack: [UInt64] = []

		for (index, insn) in instructions.enumerated() {
			let addr = String(format: "0x%llX", insn.address)

			switch insn.type {
			case .conditionalJump:
				// Generate if statement
				let condition = extractCondition(from: insn)
				if let target = insn.branchTarget, target < insn.address {
					// Backward jump = loop
					output += "\(indent)// Loop back to \(String(format: "0x%llX", target))\n"
					output += "\(indent)} // end loop\n"
				} else {
					output += "\(indent)if (\(condition)) {\n"
					indent += "    "
					pendingElse = true
				}

			case .jump:
				if let target = insn.branchTarget {
					if target < insn.address {
						// Backward jump = loop
						output += "\(indent)// Continue loop\n"
					} else if pendingElse {
						indent = String(indent.dropLast(4))
						output += "\(indent)} else {\n"
						indent += "    "
						pendingElse = false
					} else {
						output += "\(indent)goto loc_\(String(format: "%llX", target));\n"
					}
				}

			case .call:
				let target = insn.operands
				output += "\(indent)\(target)();  // call\n"

			case .return:
				if indent.count > 4 {
					indent = String(indent.dropLast(4))
					output += "\(indent)}\n"
				}
				output += "\(indent)return;\n"

			case .move:
				let parts = insn.operands.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
				if parts.count >= 2 {
					output += "\(indent)\(parts[0]) = \(parts[1]);\n"
				}

			case .arithmetic:
				output += "\(indent)// \(insn.mnemonic) \(insn.operands)\n"
				let parts = insn.operands.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
				if parts.count >= 2 {
					let op = arithmeticOp(insn.mnemonic)
					output += "\(indent)\(parts[0]) \(op)= \(parts[1]);\n"
				}

			case .compare:
				// Just a comment, the condition will be used by the next branch
				output += "\(indent)// compare \(insn.operands)\n"

			case .push:
				output += "\(indent)push(\(insn.operands));\n"

			case .pop:
				output += "\(indent)\(insn.operands) = pop();\n"

			default:
				// Generic instruction as comment
				if !insn.mnemonic.isEmpty {
					output += "\(indent)// \(insn.mnemonic) \(insn.operands)\n"
				}
			}
		}

		// Close any remaining blocks
		while indent.count > 4 {
			indent = String(indent.dropLast(4))
			output += "\(indent)}\n"
		}

		output += "}\n"
		return output
	}

	private func extractCondition(from insn: Instruction) -> String {
		let mnemonic = insn.mnemonic.lowercased()

		switch mnemonic {
		case "je", "jz": return "zero_flag"
		case "jne", "jnz": return "!zero_flag"
		case "jg", "jnle": return "greater"
		case "jge", "jnl": return "greater_or_equal"
		case "jl", "jnge": return "less"
		case "jle", "jng": return "less_or_equal"
		case "ja", "jnbe": return "above"  // unsigned
		case "jae", "jnb", "jnc": return "above_or_equal"
		case "jb", "jnae", "jc": return "below"
		case "jbe", "jna": return "below_or_equal"
		case "js": return "sign_flag"
		case "jns": return "!sign_flag"
		case "jo": return "overflow_flag"
		case "jno": return "!overflow_flag"
		default: return "condition"
		}
	}

	private func arithmeticOp(_ mnemonic: String) -> String {
		switch mnemonic.lowercased() {
		case "add": return "+"
		case "sub": return "-"
		case "imul", "mul": return "*"
		case "idiv", "div": return "/"
		case "and": return "&"
		case "or": return "|"
		case "xor": return "^"
		case "shl", "sal": return "<<"
		case "shr", "sar": return ">>"
		default: return "?"
		}
	}

	func exportTo(format: ExportManager.ExportFormat, url: URL) {
//		guard let binary = selectedBinary else { return }
//		Task {
//			isLoading = true
//			loadingMessage = "Exporting to \(format.rawValue)..."
//			let exporter = ExportManager()
//			do {
//				try exporter.export(binary: binary, functions: functions, symbols: symbols, to: url, format: format)
//				loadingMessage = "Export complete!"
//			} catch {
//				errorMessage = "Export failed: \(error.localizedDescription)"
//				showError = true
//			}
//			isLoading = false
//		}
	}

	// MARK: - Navigation

	func goToAddress(_ address: UInt64) {
		guard let selectedBinary else { return }
		// Update section if necessary
		if let selectedSection, selectedSection.contains(address: address) {} else {
			self.selectedSection = selectedBinary.sections.first { $0.contains(address: address) }
		}
		// Update function if necessary
		if let selectedFunction, selectedFunction.contains(address: address) {} else {
			self.selectedFunction = selectedBinary.procedures.first { $0.contains(address: address) }
		}
		// Update selection range
		selectedAddress = address
	}

	func select(_ range: Range<UInt64>) {
		goToAddress(range.lowerBound)
		selectedAddressRange = range
	}

	func selectFunction(_ function: Function) {
//		functionNavigator = function
	}

	// MARK: - Decompilation

	/// Whether the decompiler is running, done, or failed for the current
	/// selection. Driven by `DecompilerView`'s `.task(id:)`, which cancels
	/// the in-flight decompile when the selection changes.
	enum DecompilerState {
		case running
		case done
		case failed(String)
	}

	var decompileState: DecompilerState = .done
	/// Finished pseudo-code keyed by the procedure's `persistentModelID`, so a
	/// result for one function is never shown for another.
	@ObservationIgnored var decompiledOutputs: [PersistentIdentifier: String] = [:]
	/// The key the in-flight decompile task owns, if any. Keyed (not a bool or the
	/// state itself) so a task cancelled mid-flight cannot wedge the next one:
	/// a stale `.running` left by a cancelled task would trip a state-based
	/// re-entrancy guard and leave a new `.task(id:)` returning without ever
	/// decompiling (stuck spinner on rapid A→B→A selection switches).
	@ObservationIgnored var decompileOwner: PersistentIdentifier?

	/// The procedure identity to drive `DecompilerView`'s `.task(id:)` with.
	var selectedProcedureID: PersistentIdentifier? {
		selectedFunction?.persistentModelID
	}

	func decompileCurrentFunction() async {
		guard let function = selectedFunction,
			  let binary = selectedBinary else { return }
		let key = function.persistentModelID
		// Only a live task for the *same* procedure may pre-empt us (e.g. the
		// ⇧⌘D command racing the view task). A different key always proceeds —
		// its old task has been cancelled by `.task(id:)` and will publish nothing.
		if decompileOwner == key { return }
		decompileOwner = key
		defer { if decompileOwner == key { decompileOwner = nil } }

		decompileState = .running
		decompilerOutput = ""
		if let cached = decompiledOutputs[key] {
			decompilerOutput = cached
			decompileState = .done
			return
		}

		do {
			let instructions = await disassembleFunction(function)
			guard !Task.isCancelled else { return }
			guard !instructions.isEmpty else {
				throw DecompilerError.noInstructions
			}

			// Legacy adapters: the Decompiler still consumes `Function` /
			// `BinaryFile` (porting it to the models is Task 12).
			let legacyFunction = Function(name: function.displayName,
				startAddress: function.symbol.address,
				endAddress: function.symbol.address + function.symbol.size)
			legacyFunction.callees = Set(function.callees.map { $0.symbol.address })
			let legacyBinary = Self.legacyBinary(for: binary)

			let output = decompiler.decompile(
				function: legacyFunction,
				instructions: instructions,
				binary: legacyBinary
			)

			guard !Task.isCancelled else { return }
			decompiledOutputs[key] = output
			decompilerOutput = output
			decompileState = .done
		} catch is CancellationError {
			return
		} catch {
			guard !Task.isCancelled else { return }
			decompileState = .failed(error.localizedDescription)
		}
	}

	private enum DecompilerError: LocalizedError {
		case noInstructions
		var errorDescription: String? {
			switch self {
			case .noInstructions:
				return "No instructions could be disassembled for this function."
			}
		}
	}

	/// Builds a legacy `BinaryFile` view over a `BinaryModel` for the
	/// (still legacy) `Decompiler`. Sections carry their own byte slice so
	/// the decompiler's string cache reads the right data.
	private static func legacyBinary(for binary: BinaryModel) -> BinaryFile {
		let sections: [_Section] = binary.sections.map { section in
			_Section(
				name: section.name,
				segmentName: section.segmentName,
				address: section.address,
				size: section.size,
				offset: section.offset,
				alignment: section.alignment,
				flags: section.flags,
				data: binary.data(in: section.addressRange) ?? Data()
			)
		}
		let symbols: [Symbol] = binary.symbols.map { symbol in
			Symbol(
				name: symbol.name,
				address: symbol.address,
				size: symbol.size,
				type: symbol.type,
				binding: symbol.binding
			)
		}
		return BinaryFile(
			format: binary.format,
			architecture: binary.architecture,
			endianness: binary.endian,
			is64Bit: binary.is64,
			fileSize: binary.data.count,
			entryPoint: binary.entryPoint,
			baseAddress: binary.baseAddress,
			sections: sections,
			segments: [],
			symbols: symbols,
			data: binary.data
		)
	}

	// MARK: - AI Security Analysis

	var hasAIAPIKey: Bool {
		KeychainHelper.load(key: "AIAPIKey") != nil
	}

	func analyzeWithAI() {
//		guard let apiKey = KeychainHelper.load(key: "AIAPIKey") else {
//			securityAnalysisError = "No API key configured. Please add your AI API key in Settings."
//			showSecurityAnalysis = true
//			return
//		}
//
//		guard let function = selectedFunction else {
//			securityAnalysisError = "Please select a function to analyze."
//			showSecurityAnalysis = true
//			return
//		}
//
//		isAnalyzingWithAI = true
//		securityAnalysisResult = nil
//		securityAnalysisError = nil
//		showSecurityAnalysis = true
//
//		Task {
//			do {
//				// Get disassembly for the function
//				let instructions = await disassembleFunction(function)
//				let disassembly = instructions.prefix(200).map { insn in
//					String(format: "0x%llX: %@ %@", insn.address, insn.mnemonic, insn.operands)
//				}.joined(separator: "\n")
//
//				// Get relevant strings
//				let relevantStrings = strings.filter { str in
//					str.address >= function.startAddress && str.address < function.endAddress
//				}.map { $0.value }
//
//				// Get imports
//				let importNames = imports.map { $0.name }
//
//				// Call AI API
//				let result = try await aiClient.analyzeSecurityAsync(
//					functionName: function.displayName,
//					decompiledCode: decompilerOutput,
//					disassembly: disassembly,
//					strings: relevantStrings + Array(strings.prefix(30).map { $0.value }),
//					imports: importNames,
//					apiKey: apiKey
//				)
//
//				await MainActor.run {
//					securityAnalysisResult = result
//					isAnalyzingWithAI = false
//				}
//			} catch {
//				await MainActor.run {
//					securityAnalysisError = error.localizedDescription
//					isAnalyzingWithAI = false
//				}
//			}
//		}
	}

	func analyzeBinaryWithAI() {
//		guard let apiKey = KeychainHelper.load(key: "AIAPIKey") else {
//			securityAnalysisError = "No API key configured. Please add your AI API key in Settings."
//			showSecurityAnalysis = true
//			return
//		}
//
//		guard let binary = selectedBinary else {
//			securityAnalysisError = "No binary loaded."
//			showSecurityAnalysis = true
//			return
//		}
//
//		isAnalyzingWithAI = true
//		securityAnalysisResult = nil
//		securityAnalysisError = nil
//		showSecurityAnalysis = true
//
//		Task {
//			do {
//				let functionNames = functions.map { $0.displayName }
//				let stringValues = strings.map { $0.value }
//				let importNames = imports.map { $0.name }
//				let exportNames = exports.map { $0.name }
//
//				let result = try await aiClient.analyzeBinaryAsync(
//					binaryName: binary.name,
//					functions: functionNames,
//					strings: stringValues,
//					imports: importNames,
//					exports: exportNames,
//					apiKey: apiKey
//				)
//
//				await MainActor.run {
//					securityAnalysisResult = result
//					isAnalyzingWithAI = false
//				}
//			} catch {
//				await MainActor.run {
//					securityAnalysisError = error.localizedDescription
//					isAnalyzingWithAI = false
//				}
//			}
//		}
	}

	// MARK: - AI Chat

	func sendChatMessage(_ message: String) {
//		guard let apiKey = KeychainHelper.load(key: "AIAPIKey") else {
//			chatError = "No API key configured. Please add your AI API key in Settings."
//			return
//		}
//
//		// Add user message
//		let userMessage = ChatMessage(role: "user", content: message)
//		chatMessages.append(userMessage)
//		isChatLoading = true
//		chatError = nil
//
//		Task {
//			do {
//				// Build context
//				let context = BinaryContext(
//					name: selectedBinary?.name ?? "Unknown",
//					architecture: selectedBinary?.architecture.rawValue ?? "Unknown",
//					functionCount: functions.count,
//					currentFunction: selectedFunction?.displayName,
//					decompiledCode: decompilerOutput.isEmpty ? nil : decompilerOutput,
//					relevantStrings: strings.prefix(30).map { $0.value }
//				)
//
//				let response = try await aiClient.chatAsync(
//					messages: chatMessages,
//					context: context,
//					apiKey: apiKey
//				)
//
//				await MainActor.run {
//					let assistantMessage = ChatMessage(role: "assistant", content: response)
//					chatMessages.append(assistantMessage)
//					isChatLoading = false
//				}
//			} catch {
//				await MainActor.run {
//					chatError = error.localizedDescription
//					isChatLoading = false
//				}
//			}
//		}
	}

	func clearChat() {
		chatMessages = []
		chatError = nil
	}

	// MARK: - AI Explain Code

	func explainCurrentFunction() {
//		guard let apiKey = KeychainHelper.load(key: "AIAPIKey") else {
//			explainError = "No API key configured. Please add your AI API key in Settings."
//			showExplainCode = true
//			return
//		}
//
//		guard let function = selectedFunction else {
//			explainError = "Please select a function to explain."
//			showExplainCode = true
//			return
//		}
//
//		isExplainingCode = true
//		codeExplanation = nil
//		explainError = nil
//		showExplainCode = true
//
//		Task {
//			do {
//				let instructions = await disassembleFunction(function)
//				let disassembly = instructions.prefix(100).map { insn in
//					String(format: "0x%llX: %@ %@", insn.address, insn.mnemonic, insn.operands)
//				}.joined(separator: "\n")
//
//				let result = try await aiClient.explainCodeAsync(
//					functionName: function.displayName,
//					decompiledCode: decompilerOutput,
//					disassembly: disassembly,
//					apiKey: apiKey
//				)
//
//				await MainActor.run {
//					codeExplanation = result
//					isExplainingCode = false
//				}
//			} catch {
//				await MainActor.run {
//					explainError = error.localizedDescription
//					isExplainingCode = false
//				}
//			}
//		}
	}

	// MARK: - AI Variable Renaming

	func suggestVariableNames() {
		guard let apiKey = KeychainHelper.load(key: "AIAPIKey") else {
			renameError = "No API key configured. Please add your AI API key in Settings."
			showAIRename = true
			return
		}

		guard let function = selectedFunction else {
			renameError = "Please select a function first."
			showAIRename = true
			return
		}

		guard !decompilerOutput.isEmpty else {
			renameError = "No decompiled code available. Please decompile the function first."
			showAIRename = true
			return
		}

		isGeneratingRenames = true
		suggestedRenames = []
		renameError = nil
		showAIRename = true

		Task {
			do {
				let renames = try await aiClient.suggestVariableNamesAsync(
					decompiledCode: decompilerOutput,
					functionName: function.displayName,
					apiKey: apiKey
				)

				await MainActor.run {
					suggestedRenames = renames
					isGeneratingRenames = false
				}
			} catch {
				await MainActor.run {
					renameError = error.localizedDescription
					isGeneratingRenames = false
				}
			}
		}
	}

	func applySelectedRenames() {
		let acceptedRenames = suggestedRenames.filter { $0.isAccepted }
		guard !acceptedRenames.isEmpty else { return }

		var newCode = decompilerOutput
		for rename in acceptedRenames {
			// Replace variable names (word boundary aware)
			let pattern = "\\b\(NSRegularExpression.escapedPattern(for: rename.originalName))\\b"
			if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
				let range = NSRange(newCode.startIndex..<newCode.endIndex, in: newCode)
				newCode = regex.stringByReplacingMatches(in: newCode, options: [], range: range, withTemplate: rename.suggestedName)
			}
		}

		decompilerOutput = newCode
		showAIRename = false
	}

	func toggleRenameSelection(_ rename: VariableRename) {
		if let index = suggestedRenames.firstIndex(where: { $0.id == rename.id }) {
			suggestedRenames[index].isAccepted.toggle()
		}
	}

	func selectAllRenames() {
		for index in suggestedRenames.indices {
			suggestedRenames[index].isAccepted = true
		}
	}

	func deselectAllRenames() {
		for index in suggestedRenames.indices {
			suggestedRenames[index].isAccepted = false
		}
	}

	// MARK: - Frida Script Generation

	func generateFridaScript() {
//		guard let binary = selectedBinary, let function = selectedFunction else {
//			fridaScriptError = "Please select a function first"
//			showFridaScript = true
//			return
//		}
//
//		isGeneratingFridaScript = true
//		fridaScriptResult = nil
//		aiFridaScriptResult = nil
//		fridaScriptError = nil
//		showFridaScript = true
//
//		Task {
//			let result = fridaGenerator.generateHookScript(
//				function: function,
//				binary: binary,
//				platform: selectedFridaPlatform,
//				hookType: selectedFridaHookType,
//				bypassTechniques: preConfiguredBypassTechniques,
//				patchPoints: preConfiguredPatchPoints
//			)
//
//			await MainActor.run {
//				fridaScriptResult = result
//				isGeneratingFridaScript = false
//			}
//		}
	}

	func generateFridaScriptWithAI() {
//		guard let apiKey = KeychainHelper.load(key: "AIAPIKey") else {
//			// Fallback to basic generation
//			generateFridaScript()
//			return
//		}
//
//		guard selectedBinary != nil, let function = selectedFunction else {
//			fridaScriptError = "Please select a function first"
//			showFridaScript = true
//			return
//		}
//
//		isGeneratingFridaScript = true
//		fridaScriptResult = nil
//		aiFridaScriptResult = nil
//		fridaScriptError = nil
//		showFridaScript = true
//
//		Task {
//			do {
//				let instructions = await disassembleFunction(function)
//				let disassembly = instructions.prefix(150).map { insn in
//					String(format: "0x%llX: %@ %@", insn.address, insn.mnemonic, insn.operands)
//				}.joined(separator: "\n")
//
//				// Use security findings if available
//				let securityFindings = securityAnalysisResult?.findings.map { $0.description } ?? []
//				let bypassTechniques = preConfiguredBypassTechniques.isEmpty
//				? (securityAnalysisResult?.bypassTechniques ?? [])
//				: preConfiguredBypassTechniques
//
//				let result = try await aiClient.generateFridaScriptAsync(
//					functionName: function.displayName,
//					decompiledCode: decompilerOutput,
//					disassembly: disassembly,
//					securityFindings: securityFindings,
//					bypassTechniques: bypassTechniques,
//					platform: selectedFridaPlatform.rawValue,
//					hookType: selectedFridaHookType.rawValue,
//					apiKey: apiKey
//				)
//
//				await MainActor.run {
//					aiFridaScriptResult = result
//					isGeneratingFridaScript = false
//				}
//			} catch {
//				await MainActor.run {
//					fridaScriptError = error.localizedDescription
//					isGeneratingFridaScript = false
//				}
//			}
//		}
	}

	func generateFridaFromSecurityAnalysis(_ securityResult: SecurityAnalysisResult) {
//		// Pre-configure the generator with security analysis results
//		selectedFridaHookType = .bypass
//		preConfiguredBypassTechniques = securityResult.bypassTechniques
//		preConfiguredPatchPoints = securityResult.patchPoints
//
//		// Generate with AI if available, otherwise basic
//		if hasAIAPIKey {
//			generateFridaScriptWithAI()
//		} else {
//			generateFridaScript()
//		}
	}

	func generateMultiFunctionFridaScript() {
//		guard let binary = selectedBinary else {
//			fridaScriptError = "No binary loaded"
//			showFridaScript = true
//			return
//		}
//
//		guard !functions.isEmpty else {
//			fridaScriptError = "No functions found. Run analysis first."
//			showFridaScript = true
//			return
//		}
//
//		isGeneratingFridaScript = true
//		fridaScriptResult = nil
//		aiFridaScriptResult = nil
//		fridaScriptError = nil
//		showFridaScript = true
//
//		Task {
//			// Use first 10 functions for multi-hook
//			let targetFunctions = Array(functions.prefix(10))
//			let result = fridaGenerator.generateMultiHookScript(
//				functions: targetFunctions,
//				binary: binary,
//				platform: selectedFridaPlatform
//			)
//
//			await MainActor.run {
//				fridaScriptResult = result
//				isGeneratingFridaScript = false
//			}
//		}
	}

	// MARK: - Disassembly

	@ObservationIgnored var disassembled = RangeSet<UInt64>()
	/// Which binary the disassembly cache belongs to (its `persistentModelID`).
	/// The cache is flushed when it doesn't match the selected binary, so a
	/// re-Load never serves stale pre-Load instructions.
	@ObservationIgnored var disassembledFor: PersistentIdentifier?
	/// Monotonically increasing cache generation; bumped by `resetDisassemblyCache()`
	/// so a disassembly suspended at an `await` can detect a reset mid-flight.
	@ObservationIgnored var disassemblyCacheGeneration = 0
	var instructionMap: [UInt64: Int] = [:]
	@ObservationIgnored var instructions: [Instruction] = []
	@ObservationIgnored var pcode: [Pcode] = []

	/// Clears the transient disassembly cache (address ranges, instructions,
	/// p-code). Called from the Load path: after a re-Load the bytes backing
	/// the addresses may have changed, and an in-memory cache is union-only,
	/// so it must be dropped rather than kept. Also drops the operand symbol
	/// lookups (Task 10): the re-Load keeps the same `BinaryModel`, but its
	/// symbol rows are re-parsed, so a persistentModelID-keyed cache would
	/// serve stale entries.
	func resetDisassemblyCache() {
		disassembled = RangeSet()
		disassembledFor = nil
		disassemblyCacheGeneration &+= 1
		instructionMap.removeAll()
		instructions.removeAll()
		pcode.removeAll()
		operandSymbolsByAddress.removeAll()
		operandSymbolsByName.removeAll()
		operandLookupsFor = nil
	}

	func instruction(at address: UInt64) -> Instruction? {
		instructionMap[address].map { instructions[$0] }
	}

	func instructions(in range: Range<UInt64>) -> ArraySlice<Instruction> {
		guard let lowerBound = instructionMap[range.lowerBound] else { return [] }
		var upperBound = lowerBound
		var remaining = range.count
		while upperBound < instructions.endIndex {
			let c = instructions[upperBound].addressRange.count
			// Compare before subtracting: `remaining - c >= 0` traps on
			// integer underflow when the instruction extends past the
			// requested range (e.g. an instruction from a later cached
			// function sits right after the requested one).
			guard c <= remaining else { break }
			remaining -= c
			upperBound += 1
		}
		return instructions[lowerBound..<upperBound]
	}

	private func disassembleIfNecessary(_ addresses: Range<UInt64>) async {
		guard let selectedBinary else { return }
		// Invalidate the cache if it was built for a different binary
		// (e.g. the selected binary was re-Loaded: `persistentModelID`
		// survives the reset-first re-parse, so also compare against an
		// explicit reset from the Load path).
		if disassembledFor != nil, disassembledFor != selectedBinary.persistentModelID {
			resetDisassemblyCache()
		}
		// The address ranges that haven't been disassembled yet
		let requestedSet = RangeSet(addresses)
		let remaining = requestedSet.subtracting(disassembled)
		let generation = disassemblyCacheGeneration
		for range in remaining.ranges {
			// Skip ranges not fully backed by the file data (e.g. addresses
			// that fall outside any mapped segment). Deliberately NOT marked
			// disassembled: a later Load can back the range, and a permanent
			// skip would wedge these addresses forever.
			guard let bytes = selectedBinary.data(in: range) else { continue }
			// disassemble the range
			var result = await disassembler.disassemble(
				data: bytes,
				address: range.lowerBound,
				architecture: selectedBinary.architecture
			)
			guard !result.instructions.isEmpty else { continue }
			// The disassembler is an actor: a `resetDisassemblyCache()` (e.g.
			// from a re-Load) may have run while we were suspended. Dropping
			// the stale result keeps the fresh cache from being poisoned.
			guard generation == disassemblyCacheGeneration else { return }
			instructionMap.reserveCapacity(instructionMap.count + result.instructions.count)
			// locate the insertion index in order to remain sorted
			let instructionsIndex = instructions.lastIndex { $0.address < range.lowerBound } ?? 0
			let pcodesIndex = instructions.isEmpty ? 0 : instructions[instructionsIndex].pcode.lowerBound
			// patch the pcode offsets
			for i in result.instructions.indices {
				result.instructions[i].pcode.advance(by: pcodesIndex)
				for addr in result.instructions[i].addressRange {
					instructionMap[addr] = instructionsIndex + i
				}
			}
			// cache the disassembly
			instructions.insert(contentsOf: result.instructions, at: instructionsIndex)
			pcode.insert(contentsOf: result.pcode, at: pcodesIndex)
			disassembled.formUnion(RangeSet(range))
		}
		disassembledFor = selectedBinary.persistentModelID
	}

	func disassemble(section: SectionModel) async -> ArraySlice<Instruction> {
		await disassembleIfNecessary(section.addressRange)
		return instructions(in: section.addressRange)
	}

	func disassembleFunction(_ function: ProcedureModel) async -> ArraySlice<Instruction> {
		await disassembleIfNecessary(function.symbol.addressRange)
		return instructions(in: function.symbol.addressRange)
	}

	func disassembleRange(start: UInt64, end: UInt64) async -> ArraySlice<Instruction> {
		await disassembleIfNecessary(start..<end)
		return instructions(in: start..<end)
	}

	// MARK: - Operand Symbol Resolution (Task 10)

	/// The symbol at an address, for call/branch operand display.
	/// Procedure-backed symbols win when both cover the address, so a
	/// function target shows the function's display name.
	func operandSymbol(at address: UInt64) -> SymbolModel? {
		ensureOperandSymbolLookups()
		return operandSymbolsByAddress[address]
	}

	/// The symbol whose name (current or original `identifier`) matches an
	/// operand's text, for operands emitted as a symbol name.
	func operandSymbol(named name: String) -> SymbolModel? {
		ensureOperandSymbolLookups()
		return operandSymbolsByName[name]
	}

	private func ensureOperandSymbolLookups() {
		guard let binary = selectedBinary else { return }
		if operandLookupsFor == binary.persistentModelID { return }
		operandSymbolsByAddress.removeAll()
		operandSymbolsByName.removeAll()
		// Plain symbols first; procedures overwrite at the same address so
		// the function's display name is preferred (it also falls back to
		// `sub_<addr>` for unnamed procedures, which plain symbols don't).
		for symbol in binary.symbols {
			operandSymbolsByAddress[symbol.address] = symbol
			if !symbol.name.isEmpty {
				operandSymbolsByName[symbol.name] = symbol
				if !symbol.identifier.isEmpty, symbol.identifier != symbol.name {
					operandSymbolsByName[symbol.identifier] = symbol
				}
			}
		}
		for procedure in binary.procedures {
			operandSymbolsByAddress[procedure.symbol.address] = procedure.symbol
		}
		operandLookupsFor = binary.persistentModelID
	}

	// MARK: - Rename Functions/Symbols
	//
	// A rename writes SymbolModel.name (the original name stays in
	// `identifier`); empty name restores `identifier` (un-rename).

	private func symbol(at address: UInt64, preferProcedure: Bool) -> SymbolModel? {
		guard let binary = selectedBinary else { return nil }
		if preferProcedure {
			return binary.procedures.first { $0.symbol.address == address }?.symbol
				?? binary.symbols.first { $0.address == address }
		}
		return binary.symbols.first { $0.address == address }
			?? binary.procedures.first { $0.symbol.address == address }?.symbol
	}

	private func rename(_ address: UInt64, to newName: String, preferProcedure: Bool) {
		guard let symbol = symbol(at: address, preferProcedure: preferProcedure) else { return }
		let oldName = symbol.name
		let applied = newName.isEmpty ? symbol.identifier : newName
		registerUndoRedo {
			symbol.name = oldName
		} redo: {
			symbol.name = applied
		}
	}

	func renameFunction(at address: UInt64, to newName: String) {
		rename(address, to: newName, preferProcedure: true)
	}

	func renameSymbol(at address: UInt64, to newName: String) {
		rename(address, to: newName, preferProcedure: false)
	}

	// MARK: - Comments

	func setComment(at address: UInt64, comment: String) {
		guard let context = modelContext, let binary = selectedBinary else { return }
		let existing = binary.annotations.first { $0.address == address }

		if comment.isEmpty {
			// Remove the comment at this address.
			guard let existing else { return }
			let text = existing.text
			let kind = existing.kind
			registerUndoRedo {
				let restored = AnnotationModel(text, at: address, in: binary)
				restored.kind = kind
				context.insert(restored)
			} redo: {
				context.delete(existing)
			}
		} else if let existing {
			let oldText = existing.text
			registerUndoRedo {
				existing.text = oldText
			} redo: {
				existing.text = comment
			}
		} else {
			let annotation = AnnotationModel(comment, at: address, in: binary)
			registerUndoRedo {
				context.delete(annotation)
			} redo: {
				context.insert(annotation)
			}
		}
	}

	func getComment(at address: UInt64) -> String? {
		selectedBinary?.annotations.first { $0.address == address }?.text
	}

	// MARK: - Bookmarks

	func addBookmark(at address: UInt64, name: String, description: String = "") {
		guard let context = modelContext, let binary = selectedBinary else { return }
		let bookmark = BookmarkModel(name, at: address, in: binary)
		bookmark.summary = description
		registerUndoRedo {
			context.delete(bookmark)
		} redo: {
			context.insert(bookmark)
		}
	}

	func removeBookmark(at address: UInt64) {
		guard let context = modelContext, let binary = selectedBinary,
			  let bookmark = binary.bookmarks.first(where: { $0.address == address }) else { return }
		let name = bookmark.name
		let summary = bookmark.summary
		registerUndoRedo {
			let restored = BookmarkModel(name, at: address, in: binary)
			restored.summary = summary
			context.insert(restored)
		} redo: {
			context.delete(bookmark)
		}
	}

	// MARK: - Cross References

	func getXRefsTo(address: UInt64) -> [CrossReference] {
		[]
	}

	func getXRefsFrom(address: UInt64) -> [CrossReference] {
		[]
	}

	// MARK: - Undo/Redo

	func registerUndoRedo(
		undo: @escaping () -> Void,
		redo: @escaping () -> Void,
	) {
		guard let undoManager else { return }
		undoManager.registerUndo(withTarget: undoManager) { [undo, redo] undoManager in
			undoManager.registerUndo(withTarget: undoManager) { [redo] _ in redo() }
			undo()
		}
		redo()
	}
}
