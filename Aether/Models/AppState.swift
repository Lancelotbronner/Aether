import SwiftUI
import Combine
import UniformTypeIdentifiers
import AetherKit

@Observable
final class AppState {
	// MARK: - File State
	var currentFile: BinaryFile?
	var isLoading = false
	var loadingProgress: Double = 0
	var loadingMessage = ""
	var errorMessage: String?
	var showError = false

	// MARK: - Navigation State

	var selectedAddress: UInt64 {
		get { selectedAddressRange.lowerBound }
		set { selectedAddressRange = newValue..<(newValue + 1) }
	}
	var selectedAddressRange: Range<UInt64> = 0..<0
	var selectedFunction: Function?
	var selectedSection: Section?

	var functionNavigator: Function? {
		get { selectedFunction }
		set {
			guard let selectedFunction else { return }
			goToAddress(selectedFunction.startAddress)
		}
	}

	var sectionNavigator: Section? {
		get { selectedSection }
		set {
			guard let selectedSection else { return }
			goToAddress(selectedSection.address)
		}
	}

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

	// MARK: - Analysis Results
	var functions: [Function] = []
	var strings: [StringReference] = []
	var imports: [Symbol] = []
	var exports: [Symbol] = []
	var symbols: [Symbol] { currentFile?.symbols ?? [] }
	var xrefs: [CrossReference] = []

	// MARK: - Lookup Caches (for O(1) access)
	@ObservationIgnored var symbolsByAddress: [UInt64: Symbol] = [:]
	@ObservationIgnored var symbolsByName: [String: Symbol] = [:]
	@ObservationIgnored var functionsByAddress: [UInt64: Function] = [:]

	// MARK: - Disassembly Cache
	var decompilerOutput: String = ""

	// MARK: - Patching State
	var patcher: BinaryPatcher?
	var patches: [BinaryPatcher.Patch] = []
	var hasUnsavedChanges = false

	// MARK: - User Annotations
	var renamedFunctions: [UInt64: String] = [:]
	var renamedSymbols: [UInt64: String] = [:]
	var comments: [UInt64: String] = [:]
	var bookmarks: [UInt64: Bookmark] = [:]

	// MARK: - Search State
	var searchResults: [SearchResult] = []
	var isSearching = false

	// MARK: - Services
	@ObservationIgnored var undoManager: UndoManager?
	private let binaryLoader = BinaryLoader()
	private let disassembler = DisassemblerEngine()
	private let functionAnalyzer = FunctionAnalyzer()
	private let stringAnalyzer = StringAnalyzer()
	private let xrefAnalyzer = XRefAnalyzer()
	private let decompiler = Decompiler()
	private let javaDecompiler = JavaDecompiler()
	private let fridaGenerator = FridaScriptGenerator()

	// MARK: - File Operations

	func openFile() {
		print(">>> openFile() called!")
		let panel = NSOpenPanel()
		panel.allowsMultipleSelection = false
		panel.canChooseDirectories = false
		panel.canChooseFiles = true
		panel.message = "Select a binary file to analyze"

		let result = panel.runModal()
		print(">>> Panel result: \(result == .OK ? "OK" : "Cancel")")

		if result == .OK, let url = panel.url {
			print(">>> Selected file: \(url.path)")
			Task {
				let data = try Data(contentsOf: url)
				await loadFile(data: data)
			}
		}
	}

	func closeFile() {
		currentFile = nil
		selectedSection = nil
		selectedFunction = nil
		selectedAddress = 0
		functions = []
		strings = []
		decompilerOutput = ""
		errorMessage = nil

		// Clear malware state
		malwareReport = nil
		isAnalyzingMalware = false
		malwareFlowResult = nil
		isAnalyzingMalwareFlow = false
		malwareFlowError = nil

		// Clear caches
		symbolsByAddress = [:]
		symbolsByName = [:]
		functionsByAddress = [:]

		// Clear user annotations
		renamedFunctions = [:]
		renamedSymbols = [:]
		comments = [:]
		bookmarks = [:]
	}

	private var loadTask: Task<Void, Never>?

	func cancelLoading() {
		loadTask?.cancel()
		loadTask = nil
		isLoading = false
		loadingMessage = "Cancelled"
	}

	func loadFile(data: Data) async {
		// Cancel any previous load
		loadTask?.cancel()

		isLoading = true
		loadingProgress = 0
		loadingMessage = "Loading file..."
		errorMessage = nil

		let loader = binaryLoader
		let strAnalyzer = stringAnalyzer

		let task = Task { @concurrent () -> (BinaryFile, [Symbol], [Symbol], [Function], [UInt64: Symbol], [String: Symbol], [UInt64: Function], [StringReference]) in
			// Load binary (synchronous, no deadlock)
			let binary = try loader.load(from: data)

			try Task.checkCancellation()

			// Process symbols
			let imports = binary.symbols.filter { $0.isImport }
			let exports = binary.symbols.filter { $0.isExport }
			let symbols = binary.symbols

			try Task.checkCancellation()

			// Get functions from symbols
			let functions = binary.symbols.lazy
				.filter { $0.type == .function && $0.address != 0 }
				.map { Function(name: $0.name, startAddress: $0.address, endAddress: $0.address + max($0.size, 256)) }
				.sorted { $0.startAddress < $1.startAddress }

			try Task.checkCancellation()

			// Build lookup caches
			let symbolsByAddress = symbols.reduce(into: [UInt64: Symbol]()) { dict, symbol in
				if symbol.address != 0 && dict[symbol.address] == nil {
					dict[symbol.address] = symbol
				}
			}
			let symbolsByName = symbols.reduce(into: [String: Symbol]()) { dict, symbol in
				if dict[symbol.name] == nil {
					dict[symbol.name] = symbol
				}
			}
			let functionsByAddress = functions.reduce(into: [UInt64: Function]()) { dict, func_ in
				if dict[func_.startAddress] == nil {
					dict[func_.startAddress] = func_
				}
			}

			try Task.checkCancellation()

			// Extract strings
//			let strings = strAnalyzer.analyze(binary: binary)

			return (binary, imports, exports, functions, symbolsByAddress, symbolsByName, functionsByAddress, /*strings*/[])
		}

		loadTask = Task {
			do {
				loadingMessage = "Parsing binary format..."
				loadingProgress = 0.1

				let result = try await task.value

				guard !Task.isCancelled else { return }

				loadingMessage = "Finalizing..."
				loadingProgress = 0.9

				let (binary, imports, exports, functions, symbolsByAddress, symbolsByName, functionsByAddress, strings) = result

				self.currentFile = binary
				self.selectedSection = binary.sections.first { $0.containsCode }
				self.imports = imports
				self.exports = exports
				self.functions = functions
				self.symbolsByAddress = symbolsByAddress
				self.symbolsByName = symbolsByName
				self.functionsByAddress = functionsByAddress
				self.strings = strings

				self.patcher = BinaryPatcher(binary: binary)
				self.patches = []
				self.hasUnsavedChanges = false

				loadingProgress = 1.0
				loadingMessage = "Ready"
				isLoading = false

			} catch is CancellationError {
				isLoading = false
				loadingMessage = "Cancelled"
			} catch {
				print("ERROR: \(error)")
				errorMessage = error.localizedDescription
				showError = true
				loadingMessage = "Error: \(error.localizedDescription)"
				isLoading = false
			}
		}

		await loadTask?.value
	}

	// MARK: - Malware Analysis

	func analyzeMalware() {
		guard let binary = currentFile else { return }
		isAnalyzingMalware = true

		Task.detached(priority: .userInitiated) {
			let analyzer = MalwareAnalyzer()
			let report = analyzer.analyze(binary: binary)
			await MainActor.run { [weak self] in
				self?.malwareReport = report
				self?.isAnalyzingMalware = false
			}
		}
	}

	// MARK: - Malware Flow Analysis

	var apiKey: String {
		KeychainHelper.load(key: "AIAPIKey") ?? ""
	}

	func analyzeMalwareFlow() {
		guard let binary = currentFile else { return }
		guard let apiKey = KeychainHelper.load(key: "AIAPIKey"), !apiKey.isEmpty else {
			malwareFlowError = "No API key configured. Please add your AI API key in Settings."
			return
		}

		isAnalyzingMalwareFlow = true
		malwareFlowResult = nil
		malwareFlowError = nil

		// Run malware analysis first if not done yet
		if malwareReport == nil {
			let analyzer = MalwareAnalyzer()
			malwareReport = analyzer.analyze(binary: binary)
		}

		let report = malwareReport!

		Task {
			do {
				let sectionData = binary.sections.map { section -> (name: String, size: UInt64, entropy: Double, permissions: String) in
					let sectionEntropy = report.entropyResult.sectionEntropies.first { $0.name == section.name }
					// PE flags: R=0x40000000, W=0x80000000, X=0x20000000
					let r = (section.flags & 0x40000000 != 0) || !section.isExecutable // default readable
					let w = section.flags & 0x80000000 != 0
					let x = section.isExecutable
					let perms = "\(r ? "R" : "-")\(w ? "W" : "-")\(x ? "X" : "-")"
					return (
						name: section.name,
						size: section.size,
						entropy: sectionEntropy?.entropy ?? 0,
						permissions: perms
					)
				}

				let importNames = imports.map { $0.name }
				let exportNames = exports.map { $0.name }
				let stringValues = strings.prefix(100).map { $0.value }
				let anomalyDescs = report.anomalies.map { "\($0.severity.rawValue): \($0.title) - \($0.description)" }

				let result = try await aiClient.analyzeMalwareFlowAsync(
					binaryName: binary.name,
					sections: sectionData,
					imports: importNames,
					exports: exportNames,
					strings: Array(stringValues),
					entropyOverall: report.entropyResult.overallEntropy,
					anomalies: anomalyDescs,
					apiKey: apiKey
				)

				await MainActor.run {
					self.malwareFlowResult = result
					self.isAnalyzingMalwareFlow = false
				}
			} catch {
				await MainActor.run {
					self.malwareFlowError = error.localizedDescription
					self.isAnalyzingMalwareFlow = false
				}
			}
		}
	}

	// MARK: - Analysis

	func analyzeAll() {
		guard currentFile != nil else { return }
		Task {
			await performAnalysis()
		}
	}

	private func performAnalysis() async {
		guard let binary = currentFile else { return }

		isLoading = true

		// Find functions
		loadingMessage = "Analyzing functions..."
		loadingProgress = 0.4
		self.functions = await functionAnalyzer.analyze(binary: binary, disassembler: disassembler)

		// Find strings
		loadingMessage = "Extracting strings..."
		loadingProgress = 0.6
		self.strings = stringAnalyzer.analyze(binary: binary)

		// Build cross-references
		loadingMessage = "Building cross-references..."
		loadingProgress = 0.8
		self.xrefs = await xrefAnalyzer.analyze(binary: binary, functions: functions, disassembler: disassembler)

		// Extract imports/exports
		loadingMessage = "Processing symbols..."
		loadingProgress = 0.9
		self.imports = binary.symbols.filter { $0.isImport }
		self.exports = binary.symbols.filter { $0.isExport }

		loadingProgress = 1.0
		loadingMessage = "Analysis complete"
		isLoading = false
	}

	func findFunctions() {
		guard let binary = currentFile else { return }
		Task {
			isLoading = true
			loadingMessage = "Finding functions..."
			self.functions = await functionAnalyzer.analyze(binary: binary, disassembler: disassembler)
			isLoading = false
		}
	}

	// MARK: - Advanced Analysis

	func runCryptoDetection() {
		guard let binary = currentFile else { return }
		Task {
			isLoading = true
			loadingMessage = "Detecting cryptographic patterns..."
			let detector = AdvancedCryptoDetector()
			self.cryptoFindings = detector.scan(binary: binary)
			isLoading = false
			showCryptoDetection = true
		}
	}

	func runDeobfuscation() {
		guard let binary = currentFile, let function = selectedFunction else { return }
		Task {
			isLoading = true
			loadingMessage = "Analyzing obfuscation..."
			let deobfuscator = Deobfuscator()
			let instructions = await disassembleFunction(function)

			// Build basic blocks for analysis
			var basicBlocks: [BasicBlock] = []
			if !instructions.isEmpty {
				let bb = BasicBlock(startAddress: function.startAddress, endAddress: function.endAddress, instructions: instructions)
				basicBlocks.append(bb)
			}

			var func_ = function
			func_.basicBlocks = basicBlocks
			let findings = deobfuscator.analyze(function: func_, binary: binary)
			let result = deobfuscator.deobfuscate(function: func_, binary: binary)

			self.deobfuscationReport = DeobfuscationReportWrapper.from(result, findings: findings)
			isLoading = false
			showDeobfuscation = true
		}
	}

	func runTypeRecovery() {
		guard let binary = currentFile, let function = selectedFunction else { return }
		Task {
			isLoading = true
			loadingMessage = "Recovering types..."
			let recovery = TypeRecovery()
			let instructions = await disassembleFunction(function)

			var basicBlocks: [BasicBlock] = []
			if !instructions.isEmpty {
				let bb = BasicBlock(startAddress: function.startAddress, endAddress: function.endAddress, instructions: instructions)
				basicBlocks.append(bb)
			}

			self.recoveredTypes = recovery.recoverTypes(function: function, blocks: basicBlocks, binary: binary)
			isLoading = false
			showTypeRecovery = true
		}
	}

	func runIdiomRecognition() {
		guard let function = selectedFunction else { return }
		Task {
			isLoading = true
			loadingMessage = "Recognizing code idioms..."
			let recognizer = IdiomRecognizer()
			let instructions = await disassembleFunction(function)

			var basicBlocks: [BasicBlock] = []
			if !instructions.isEmpty {
				let bb = BasicBlock(startAddress: function.startAddress, endAddress: function.endAddress, instructions: instructions)
				basicBlocks.append(bb)
			}

			var func_ = function
			func_.basicBlocks = basicBlocks
			self.recognizedIdioms = recognizer.recognize(function: func_)
			isLoading = false
			showIdiomRecognition = true
		}
	}

	func generateStructuredCode() {
		guard let binary = currentFile, let function = selectedFunction else { return }
		Task {
			isLoading = true
			loadingMessage = "Generating structured code..."
			let instructions = await disassembleFunction(function)

			guard !instructions.isEmpty else {
				self.structuredCode = "// No instructions found for function"
				isLoading = false
				showPseudoCode = true
				return
			}

			// Build proper basic blocks by splitting at control flow instructions
			let basicBlocks = buildBasicBlocks(from: instructions, function: function)

			var func_ = function
			func_.basicBlocks = basicBlocks

			// Generate pseudo-code directly from instructions
			self.structuredCode = generatePseudoCodeFromInstructions(instructions, function: func_, binary: binary)
			isLoading = false
			showPseudoCode = true
		}
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
		guard let binary = currentFile else { return }
		Task {
			isLoading = true
			loadingMessage = "Exporting to \(format.rawValue)..."
			let exporter = ExportManager()
			do {
				try exporter.export(binary: binary, functions: functions, symbols: symbols, to: url, format: format)
				loadingMessage = "Export complete!"
			} catch {
				errorMessage = "Export failed: \(error.localizedDescription)"
				showError = true
			}
			isLoading = false
		}
	}

	// MARK: - Navigation

	func goToAddress(_ address: UInt64) {
		guard let currentFile else { return }
		// Update section if necessary
		if let selectedSection, selectedSection.contains(address: address) {} else {
			self.selectedSection = currentFile.sections.first { $0.contains(address: address) }
		}
		// Update function if necessary
		if let selectedFunction, selectedFunction.contains(address: address) {} else {
			self.selectedFunction = functions.first { $0.contains(address: address) }
		}
		// Update selection range
		selectedAddress = address
	}

	func select(_ range: Range<UInt64>) {
		goToAddress(range.lowerBound)
		selectedAddressRange = range
	}

	func selectFunction(_ function: Function) {
		functionNavigator = function
	}

	// MARK: - Decompilation

	func decompileCurrentFunction() {
		guard let function = selectedFunction,
			  let binary = currentFile else { return }

		// Check if this is a Java class file
		if let javaClasses = binary.javaClasses, !javaClasses.isEmpty {
			decompileJavaMethod(function: function, javaClasses: javaClasses)
			return
		}

		decompilerOutput = "// Decompiling..."

		Task {
			let instructions = await disassembleFunction(function)

			// Run heavy decompilation off the main thread
			let decomp = self.decompiler
			let output = await Task.detached(priority: .userInitiated) {
				return decomp.decompile(
					function: function,
					instructions: instructions,
					binary: binary
				)
			}.value

			// Update UI on main thread (automatic via @MainActor)
			if self.selectedFunction?.startAddress == function.startAddress {
				self.decompilerOutput = output
			}
		}
	}

	private func decompileJavaMethod(function: Function, javaClasses: [JARLoader.JavaClass]) {
		let functionName = function.name

		// Find matching class and method - use exact matching
		for javaClass in javaClasses {
			let className = javaClass.thisClass.replacingOccurrences(of: "/", with: ".")

			for method in javaClass.methods {
				let methodFullName = "\(className).\(method.name)\(method.descriptor)"

				if methodFullName == functionName {
					// Found the exact method - decompile just this method
					let decompiledMethod = javaDecompiler.decompileMethod(method, in: javaClass)

					var output = "// Function at 0x\(String(format: "%X", function.startAddress))\n"
					output += "// Size: \(method.code?.code.count ?? 0) bytes (bytecode)\n"
					output += "// Class: \(className)\n"
					output += "// Method: \(method.name)\(method.descriptor)\n\n"
					output += "\(decompiledMethod.signature) {\n"

					let bodyLines = decompiledMethod.body.split(separator: "\n", omittingEmptySubsequences: false)
					for line in bodyLines {
						if !line.isEmpty {
							output += "    \(line)\n"
						} else {
							output += "\n"
						}
					}
					output += "}\n"

					decompilerOutput = output
					return
				}
			}
		}

		// Fallback: couldn't find the method
		decompilerOutput = "// Could not find Java method for: \(functionName)\n// Available methods in loaded classes:\n"
		for javaClass in javaClasses.prefix(5) {
			let className = javaClass.thisClass.replacingOccurrences(of: "/", with: ".")
			for method in javaClass.methods.prefix(3) {
				decompilerOutput += "//   \(className).\(method.name)\(method.descriptor)\n"
			}
		}
	}

	// MARK: - AI Security Analysis

	var hasAIAPIKey: Bool {
		KeychainHelper.load(key: "AIAPIKey") != nil
	}

	func analyzeWithAI() {
		guard let apiKey = KeychainHelper.load(key: "AIAPIKey") else {
			securityAnalysisError = "No API key configured. Please add your AI API key in Settings."
			showSecurityAnalysis = true
			return
		}

		guard let function = selectedFunction else {
			securityAnalysisError = "Please select a function to analyze."
			showSecurityAnalysis = true
			return
		}

		isAnalyzingWithAI = true
		securityAnalysisResult = nil
		securityAnalysisError = nil
		showSecurityAnalysis = true

		Task {
			do {
				// Get disassembly for the function
				let instructions = await disassembleFunction(function)
				let disassembly = instructions.prefix(200).map { insn in
					String(format: "0x%llX: %@ %@", insn.address, insn.mnemonic, insn.operands)
				}.joined(separator: "\n")

				// Get relevant strings
				let relevantStrings = strings.filter { str in
					str.address >= function.startAddress && str.address < function.endAddress
				}.map { $0.value }

				// Get imports
				let importNames = imports.map { $0.name }

				// Call AI API
				let result = try await aiClient.analyzeSecurityAsync(
					functionName: function.displayName,
					decompiledCode: decompilerOutput,
					disassembly: disassembly,
					strings: relevantStrings + Array(strings.prefix(30).map { $0.value }),
					imports: importNames,
					apiKey: apiKey
				)

				await MainActor.run {
					securityAnalysisResult = result
					isAnalyzingWithAI = false
				}
			} catch {
				await MainActor.run {
					securityAnalysisError = error.localizedDescription
					isAnalyzingWithAI = false
				}
			}
		}
	}

	func analyzeBinaryWithAI() {
		guard let apiKey = KeychainHelper.load(key: "AIAPIKey") else {
			securityAnalysisError = "No API key configured. Please add your AI API key in Settings."
			showSecurityAnalysis = true
			return
		}

		guard let binary = currentFile else {
			securityAnalysisError = "No binary loaded."
			showSecurityAnalysis = true
			return
		}

		isAnalyzingWithAI = true
		securityAnalysisResult = nil
		securityAnalysisError = nil
		showSecurityAnalysis = true

		Task {
			do {
				let functionNames = functions.map { $0.displayName }
				let stringValues = strings.map { $0.value }
				let importNames = imports.map { $0.name }
				let exportNames = exports.map { $0.name }

				let result = try await aiClient.analyzeBinaryAsync(
					binaryName: binary.name,
					functions: functionNames,
					strings: stringValues,
					imports: importNames,
					exports: exportNames,
					apiKey: apiKey
				)

				await MainActor.run {
					securityAnalysisResult = result
					isAnalyzingWithAI = false
				}
			} catch {
				await MainActor.run {
					securityAnalysisError = error.localizedDescription
					isAnalyzingWithAI = false
				}
			}
		}
	}

	// MARK: - AI Chat

	func sendChatMessage(_ message: String) {
		guard let apiKey = KeychainHelper.load(key: "AIAPIKey") else {
			chatError = "No API key configured. Please add your AI API key in Settings."
			return
		}

		// Add user message
		let userMessage = ChatMessage(role: "user", content: message)
		chatMessages.append(userMessage)
		isChatLoading = true
		chatError = nil

		Task {
			do {
				// Build context
				let context = BinaryContext(
					name: currentFile?.name ?? "Unknown",
					architecture: currentFile?.architecture.rawValue ?? "Unknown",
					functionCount: functions.count,
					currentFunction: selectedFunction?.displayName,
					decompiledCode: decompilerOutput.isEmpty ? nil : decompilerOutput,
					relevantStrings: strings.prefix(30).map { $0.value }
				)

				let response = try await aiClient.chatAsync(
					messages: chatMessages,
					context: context,
					apiKey: apiKey
				)

				await MainActor.run {
					let assistantMessage = ChatMessage(role: "assistant", content: response)
					chatMessages.append(assistantMessage)
					isChatLoading = false
				}
			} catch {
				await MainActor.run {
					chatError = error.localizedDescription
					isChatLoading = false
				}
			}
		}
	}

	func clearChat() {
		chatMessages = []
		chatError = nil
	}

	// MARK: - AI Explain Code

	func explainCurrentFunction() {
		guard let apiKey = KeychainHelper.load(key: "AIAPIKey") else {
			explainError = "No API key configured. Please add your AI API key in Settings."
			showExplainCode = true
			return
		}

		guard let function = selectedFunction else {
			explainError = "Please select a function to explain."
			showExplainCode = true
			return
		}

		isExplainingCode = true
		codeExplanation = nil
		explainError = nil
		showExplainCode = true

		Task {
			do {
				let instructions = await disassembleFunction(function)
				let disassembly = instructions.prefix(100).map { insn in
					String(format: "0x%llX: %@ %@", insn.address, insn.mnemonic, insn.operands)
				}.joined(separator: "\n")

				let result = try await aiClient.explainCodeAsync(
					functionName: function.displayName,
					decompiledCode: decompilerOutput,
					disassembly: disassembly,
					apiKey: apiKey
				)

				await MainActor.run {
					codeExplanation = result
					isExplainingCode = false
				}
			} catch {
				await MainActor.run {
					explainError = error.localizedDescription
					isExplainingCode = false
				}
			}
		}
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
		guard let binary = currentFile, let function = selectedFunction else {
			fridaScriptError = "Please select a function first"
			showFridaScript = true
			return
		}

		isGeneratingFridaScript = true
		fridaScriptResult = nil
		aiFridaScriptResult = nil
		fridaScriptError = nil
		showFridaScript = true

		Task {
			let result = fridaGenerator.generateHookScript(
				function: function,
				binary: binary,
				platform: selectedFridaPlatform,
				hookType: selectedFridaHookType,
				bypassTechniques: preConfiguredBypassTechniques,
				patchPoints: preConfiguredPatchPoints
			)

			await MainActor.run {
				fridaScriptResult = result
				isGeneratingFridaScript = false
			}
		}
	}

	func generateFridaScriptWithAI() {
		guard let apiKey = KeychainHelper.load(key: "AIAPIKey") else {
			// Fallback to basic generation
			generateFridaScript()
			return
		}

		guard currentFile != nil, let function = selectedFunction else {
			fridaScriptError = "Please select a function first"
			showFridaScript = true
			return
		}

		isGeneratingFridaScript = true
		fridaScriptResult = nil
		aiFridaScriptResult = nil
		fridaScriptError = nil
		showFridaScript = true

		Task {
			do {
				let instructions = await disassembleFunction(function)
				let disassembly = instructions.prefix(150).map { insn in
					String(format: "0x%llX: %@ %@", insn.address, insn.mnemonic, insn.operands)
				}.joined(separator: "\n")

				// Use security findings if available
				let securityFindings = securityAnalysisResult?.findings.map { $0.description } ?? []
				let bypassTechniques = preConfiguredBypassTechniques.isEmpty
				? (securityAnalysisResult?.bypassTechniques ?? [])
				: preConfiguredBypassTechniques

				let result = try await aiClient.generateFridaScriptAsync(
					functionName: function.displayName,
					decompiledCode: decompilerOutput,
					disassembly: disassembly,
					securityFindings: securityFindings,
					bypassTechniques: bypassTechniques,
					platform: selectedFridaPlatform.rawValue,
					hookType: selectedFridaHookType.rawValue,
					apiKey: apiKey
				)

				await MainActor.run {
					aiFridaScriptResult = result
					isGeneratingFridaScript = false
				}
			} catch {
				await MainActor.run {
					fridaScriptError = error.localizedDescription
					isGeneratingFridaScript = false
				}
			}
		}
	}

	func generateFridaFromSecurityAnalysis(_ securityResult: SecurityAnalysisResult) {
		// Pre-configure the generator with security analysis results
		selectedFridaHookType = .bypass
		preConfiguredBypassTechniques = securityResult.bypassTechniques
		preConfiguredPatchPoints = securityResult.patchPoints

		// Generate with AI if available, otherwise basic
		if hasAIAPIKey {
			generateFridaScriptWithAI()
		} else {
			generateFridaScript()
		}
	}

	func generateMultiFunctionFridaScript() {
		guard let binary = currentFile else {
			fridaScriptError = "No binary loaded"
			showFridaScript = true
			return
		}

		guard !functions.isEmpty else {
			fridaScriptError = "No functions found. Run analysis first."
			showFridaScript = true
			return
		}

		isGeneratingFridaScript = true
		fridaScriptResult = nil
		aiFridaScriptResult = nil
		fridaScriptError = nil
		showFridaScript = true

		Task {
			// Use first 10 functions for multi-hook
			let targetFunctions = Array(functions.prefix(10))
			let result = fridaGenerator.generateMultiHookScript(
				functions: targetFunctions,
				binary: binary,
				platform: selectedFridaPlatform
			)

			await MainActor.run {
				fridaScriptResult = result
				isGeneratingFridaScript = false
			}
		}
	}

	// MARK: - Patching

	func patchBytes(at address: UInt64, newBytes: [UInt8], description: String) {
		guard let patcher = patcher else { return }

		do {
			let patch = try patcher.createPatch(at: address, newBytes: newBytes, description: description)
			try patcher.applyPatch(patch)
			patches = patcher.getAllPatches()
			hasUnsavedChanges = true

			// Clear cache for affected section
			clearDisassemblyCache(in: address..<(address + UInt64(newBytes.count)))
		} catch {
			errorMessage = error.localizedDescription
			showError = true
		}
	}

	func nopInstruction(at address: UInt64, size: Int) {
		guard let patcher = patcher else { return }

		do {
			let patch = try patcher.createNOPPatch(at: address, size: size, description: "NOP at \(String(format: "0x%llX", address))")
			try patcher.applyPatch(patch)
			patches = patcher.getAllPatches()
			hasUnsavedChanges = true
			clearDisassemblyCache(in: address..<(address + UInt64(size)))
		} catch {
			errorMessage = error.localizedDescription
			showError = true
		}
	}

	func revertPatch(_ patch: BinaryPatcher.Patch) {
		guard let patcher = patcher else { return }

		do {
			try patcher.revertPatch(patch)
			patches = patcher.getAllPatches()
			hasUnsavedChanges = patches.contains { $0.isApplied }
			clearDisassemblyCache(in: patch.address..<(patch.address + UInt64(patch.newBytes.count)))
		} catch {
			errorMessage = error.localizedDescription
			showError = true
		}
	}

	func saveFile() {
		guard currentFile != nil else { return }
		preconditionFailure("cannot save without URL")
	}

	func saveFileAs() {
		let panel = NSSavePanel()
		panel.allowedContentTypes = [.data]
		panel.nameFieldStringValue = currentFile?.name ?? "patched_binary"
		panel.message = "Save patched binary"

		if panel.runModal() == .OK, let url = panel.url {
			saveFile(to: url)
		}
	}

	func saveFile(to url: URL) {
		guard let patcher = patcher else { return }

		do {
			try patcher.save(to: url)
			hasUnsavedChanges = false
			loadingMessage = "Saved to \(url.lastPathComponent)"
		} catch {
			errorMessage = "Failed to save: \(error.localizedDescription)"
			showError = true
		}
	}

	// MARK: - Disassembly

	@ObservationIgnored var disassembled = RangeSet<UInt64>()
	@ObservationIgnored var instructionMap: [UInt64: Int] = [:]
	@ObservationIgnored var instructions: [Instruction] = []
	@ObservationIgnored var pcode: [Pcode] = []

	func instruction(at address: UInt64) -> Instruction? {
		instructionMap[address].map { instructions[$0] }
	}

	func clearDisassemblyCache(in range: Range<UInt64>) {
		let lowerBoundI = instructionMap[range.lowerBound, default: 0]
		let upperBoundI = instructionMap[range.upperBound, default: 0]
		let lowerBoundP = instructions[lowerBoundI].pcode.lowerBound
		let upperBoundP = instructions[upperBoundI].pcode.upperBound
		instructions.removeSubrange(lowerBoundI..<upperBoundI)
		pcode.removeSubrange(lowerBoundP..<upperBoundP)
	}

	func instructions(in range: Range<UInt64>) -> ArraySlice<Instruction> {
		let lowerBound = instructionMap[range.lowerBound, default: 0]
		let slice = instructions[lowerBound...].prefix(range.count)
		return slice
	}

	private func disassembleIfNecessary(_ addresses: Range<UInt64>) async {
		guard let currentFile else { return }
		// The address ranges that haven't been disassembled yet
		let requestedSet = RangeSet(addresses)
		let remaining = requestedSet.subtracting(disassembled)
		disassembled.formUnion(requestedSet)
		for range in remaining.ranges {
			// disassemble the range
			var result = await disassembler.disassemble(
				data: currentFile.bytes(in: range),
				address: range.lowerBound,
				architecture: currentFile.architecture
			)
			guard !result.instructions.isEmpty else { continue }
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
		}
	}

	func disassemble(section: Section) async -> ArraySlice<Instruction> {
		await disassembleIfNecessary(section.addressRange)
		return instructions(in: section.addressRange)
	}

	func disassembleFunction(_ function: Function) async -> ArraySlice<Instruction> {
		await disassembleIfNecessary(function.addressRange)
		return instructions(in: function.addressRange)
	}

	func disassembleRange(start: UInt64, end: UInt64) async -> ArraySlice<Instruction> {
		await disassembleIfNecessary(start..<end)
		return instructions(in: start..<end)
	}

	// MARK: - Rename Functions/Symbols

	func renameFunction(at address: UInt64, to newName: String) {
		let oldName = renamedFunctions[address]
		let newName = newName.isEmpty ? nil : newName
		registerUndoRedo {
			self.renamedFunctions[address] = oldName
		} redo: {
			self.renamedFunctions[address] = newName
		}
		hasUnsavedChanges = true
	}

	func renameSymbol(at address: UInt64, to newName: String) {
		let oldName = renamedSymbols[address]
		let newName = newName.isEmpty ? nil : newName
		registerUndoRedo {
			self.renamedSymbols[address] = oldName
		} redo: {
			self.renamedSymbols[address] = newName
		}
		hasUnsavedChanges = true
	}

	func getDisplayName(forFunctionAt address: UInt64) -> String {
		if let renamed = renamedFunctions[address] {
			return renamed
		}
		if let func_ = functionsByAddress[address] {
			return func_.name
		}
		return String(format: "sub_%llX", address)
	}

	func getDisplayName(forSymbolAt address: UInt64) -> String {
		if let renamed = renamedSymbols[address] {
			return renamed
		}
		if let symbol = symbolsByAddress[address] {
			return symbol.displayName
		}
		return String(format: "loc_%llX", address)
	}

	// MARK: - Comments

	func setComment(at address: UInt64, comment: String) {
		let oldComment = comments[address]
		let newComment = comment.isEmpty ? nil : comment
		registerUndoRedo {
			self.comments[address] = oldComment
		} redo: {
			self.comments[address] = newComment
		}
		hasUnsavedChanges = true
	}

	func getComment(at address: UInt64) -> String? {
		return comments[address]
	}

	// MARK: - Bookmarks

	func addBookmark(at address: UInt64, name: String, description: String = "") {
		let bookmark = Bookmark(name: name, description: description)
		registerUndoRedo {
			self.bookmarks[address] = nil
		} redo: {
			self.bookmarks[address] = bookmark
		}
		hasUnsavedChanges = true
	}

	func removeBookmark(at address: UInt64) {
		guard let bookmark = bookmarks[address] else { return }
		registerUndoRedo {
			self.bookmarks[address] = bookmark
		} redo: {
			self.bookmarks[address] = nil
		}
		hasUnsavedChanges = true
	}

	// MARK: - Search

	func search(query: String, type: SearchType) async {
		guard let binary = currentFile else { return }

		isSearching = true
		searchResults = []

		switch type {
		case .all:
			await searchAll(query: query, binary: binary)
		case .functions:
			searchResults = searchFunctions(query: query)
		case .strings:
			searchResults = searchStrings(query: query)
		case .symbols:
			searchResults = searchSymbols(query: query)
		case .bytes:
			searchResults = await searchBytes(query: query, binary: binary)
		case .address:
			if let address = parseAddress(query) {
				searchResults = [SearchResult(name: String(format: "0x%llX", address), address: address, type: .address)]
			}
		}

		isSearching = false
	}

	private func searchAll(query: String, binary: BinaryFile) async {
		var results: [SearchResult] = []

		// Search functions
		results.append(contentsOf: searchFunctions(query: query))

		// Search strings
		results.append(contentsOf: searchStrings(query: query))

		// Search symbols
		results.append(contentsOf: searchSymbols(query: query))

		// Check if it's an address
		if let address = parseAddress(query) {
			results.insert(SearchResult(name: String(format: "0x%llX", address), address: address, type: .address), at: 0)
		}

		searchResults = results
	}

	private func searchFunctions(query: String) -> [SearchResult] {
		let lowercaseQuery = query.lowercased()
		return functions.filter {
			$0.displayName.lowercased().contains(lowercaseQuery) ||
			getDisplayName(forFunctionAt: $0.startAddress).lowercased().contains(lowercaseQuery)
		}.map {
			SearchResult(name: getDisplayName(forFunctionAt: $0.startAddress), address: $0.startAddress, type: .function)
		}
	}

	private func searchStrings(query: String) -> [SearchResult] {
		let lowercaseQuery = query.lowercased()
		return strings.filter {
			$0.value.lowercased().contains(lowercaseQuery)
		}.map {
			SearchResult(name: $0.value, address: $0.address, type: .string)
		}
	}

	private func searchSymbols(query: String) -> [SearchResult] {
		let lowercaseQuery = query.lowercased()
		return symbols.filter {
			$0.displayName.lowercased().contains(lowercaseQuery)
		}.map {
			SearchResult(name: $0.displayName, address: $0.address, type: .symbol)
		}
	}

	private func searchBytes(query: String, binary: BinaryFile) async -> [SearchResult] {
		// Parse hex bytes
		let hexParts = query.uppercased().components(separatedBy: .whitespaces).filter { !$0.isEmpty }
		var bytes: [UInt8] = []

		for hex in hexParts {
			if let byte = UInt8(hex, radix: 16) {
				bytes.append(byte)
			}
		}

		guard !bytes.isEmpty else { return [] }

		var results: [SearchResult] = []

		for section in binary.sections {
			let data = section.data
			let bytesData = Data(bytes)

			var searchRange = data.startIndex..<data.endIndex
			while let range = data.range(of: bytesData, options: [], in: searchRange) {
				let offset = data.distance(from: data.startIndex, to: range.lowerBound)
				let address = section.address + UInt64(offset)
				results.append(SearchResult(
					name: bytes.map { String(format: "%02X", $0) }.joined(separator: " "),
					address: address,
					type: .bytes
				))
				searchRange = range.upperBound..<data.endIndex

				if results.count >= 100 { break } // Limit results
			}
			if results.count >= 100 { break }
		}

		return results
	}

	private func parseAddress(_ string: String) -> UInt64? {
		let clean = string.trimmingCharacters(in: .whitespaces)
		if clean.hasPrefix("0x") || clean.hasPrefix("0X") {
			return UInt64(clean.dropFirst(2), radix: 16)
		}
		return UInt64(clean, radix: 16)
	}

	// MARK: - Cross References

	func getXRefsTo(address: UInt64) -> [CrossReference] {
		return xrefs.filter { $0.toAddress == address }
	}

	func getXRefsFrom(address: UInt64) -> [CrossReference] {
		return xrefs.filter { $0.fromAddress == address }
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

	// MARK: - Project Save/Load

	func saveProject(to url: URL) throws {
		let project = ProjectData(
			binaryData: currentFile?.data ?? Data(),
			renamedFunctions: renamedFunctions,
			renamedSymbols: renamedSymbols,
			comments: comments,
			bookmarks: bookmarks,
			patches: patches.map { PatchData(address: $0.address, bytes: $0.newBytes, description: $0.description) }
		)

		let encoder = JSONEncoder()
		encoder.outputFormatting = .prettyPrinted
		let data = try encoder.encode(project)
		try data.write(to: url)
		hasUnsavedChanges = false
	}

	func loadProject(data: Data) async throws {
		let decoder = JSONDecoder()
		let project = try decoder.decode(ProjectData.self, from: data)

		// Load the binary first
		await loadFile(data: project.binaryData)

		// Restore annotations
		renamedFunctions = project.renamedFunctions
		renamedSymbols = project.renamedSymbols
		comments = project.comments
		bookmarks = project.bookmarks

		// Re-apply patches
		for patchData in project.patches {
			patchBytes(at: patchData.address, newBytes: patchData.bytes, description: patchData.description)
		}

		hasUnsavedChanges = false
	}

	func openProject() {
		let panel = NSOpenPanel()
		panel.allowedContentTypes = [.json]
		panel.message = "Open Aether Project"

		if panel.runModal() == .OK, let url = panel.url {
			Task {
				let data = try Data(contentsOf: url)
				try? await loadProject(data: data)
			}
		}
	}

	func saveProjectAs() {
		let panel = NSSavePanel()
		panel.allowedContentTypes = [.json]
		panel.nameFieldStringValue = "\(currentFile?.name ?? "project").dproj"
		panel.message = "Save Aether Project"

		if panel.runModal() == .OK, let url = panel.url {
			try? saveProject(to: url)
		}
	}
}

// MARK: - Supporting Types

// Using Bookmark from Project.swift

struct SearchResult: Identifiable {
	let id = UUID()
	let name: String
	let address: UInt64
	let type: SearchResultType
}

enum SearchResultType {
	case function
	case string
	case symbol
	case bytes
	case address
}

enum SearchType: String, CaseIterable {
	case all = "All"
	case functions = "Functions"
	case strings = "Strings"
	case symbols = "Symbols"
	case bytes = "Bytes"
	case address = "Address"
}

enum UndoAction {
	case renameFunction(address: UInt64, oldName: String?, newName: String?)
	case renameSymbol(address: UInt64, oldName: String?, newName: String?)
	case setComment(address: UInt64, oldComment: String?, newComment: String?)
	case addBookmark(bookmark: Bookmark)
	case removeBookmark(bookmark: Bookmark)
	case patchBytes(address: UInt64, oldBytes: [UInt8], newBytes: [UInt8])
}

struct ProjectData: Codable {
	let binaryData: Data
	let renamedFunctions: [UInt64: String]
	let renamedSymbols: [UInt64: String]
	let comments: [UInt64: String]
	let bookmarks: [UInt64: Bookmark]
	let patches: [PatchData]
}

struct PatchData: Codable {
	let address: UInt64
	let bytes: [UInt8]
	let description: String
}
