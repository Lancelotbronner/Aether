import SwiftUI
import SwiftData
import OSLog
import UniformTypeIdentifiers
import AetherKit

struct AetherCommands: Commands {
	@FocusedValue(\.modelContext) private var modelContext
	@FocusedValue(AppState.self) private var appState
	@State private var isImportingBinary = false

	var body: some Commands {
		CommandGroup(after: .newItem) {
			Button("Import Binary...") {
				isImportingBinary = true
			}
			.keyboardShortcut("o", modifiers: [.command, .shift])
			.disabled(modelContext == nil)
			.fileImporter(isPresented: $isImportingBinary, allowedContentTypes: [.executable]) { result in
				do {
					let url = try result.get()
					guard let modelContext else { return }

					url.startAccessingSecurityScopedResource()
					defer { url.stopAccessingSecurityScopedResource() }

					let binary = BinaryModel()
					binary.data = try Data(contentsOf: url, options: .mappedIfSafe)
					binary.fileURL = url
					binary.name = url.lastPathComponent
					modelContext.insert(binary)
				} catch {
					Logger.app.error("failed to import binary: \(error)")
				}
			}
		}
		CommandMenu("Analysis") {
			Button("Analyze All") {
				appState?.analyzeAll()
			}
			.keyboardShortcut("a", modifiers: [.command, .shift])
			.disabled(appState?.selectedBinary == nil)

			Button("Find Functions") {
				appState?.findFunctions()
			}
			.keyboardShortcut("f", modifiers: [.command, .shift])
			.disabled(appState?.selectedBinary == nil)

			Divider()

			Button("Show CFG") {
				appState?.showCFG = true
			}
			.keyboardShortcut("g", modifiers: .command)
			.disabled(appState?.selectedFunction == nil)

			Button("Decompile") {
				guard let appState else { return }
				Task { @concurrent in
					await appState.decompileCurrentFunction()
				}
			}
			.keyboardShortcut("d", modifiers: [.command, .shift])
			.disabled(appState?.selectedFunction == nil)

			Button("Generate Pseudo-Code") {
				appState?.generateStructuredCode()
			}
			.keyboardShortcut("p", modifiers: [.command, .shift])
			.disabled(appState?.selectedFunction == nil)

			Divider()

			Button("Call Graph") {
				appState?.showCallGraph = true
			}
			.keyboardShortcut("G", modifiers: .command)
			.disabled(appState?.selectedBinary == nil)

			Button("Crypto Detection") {
				appState?.runCryptoDetection()
			}
			.disabled(appState?.selectedBinary == nil)

			Button("Deobfuscation Analysis") {
				appState?.runDeobfuscation()
			}
			.disabled(appState?.selectedFunction == nil)

			Button("Type Recovery") {
				appState?.runTypeRecovery()
			}
			.disabled(appState?.selectedFunction == nil)

			Button("Idiom Recognition") {
				appState?.runIdiomRecognition()
			}
			.disabled(appState?.selectedFunction == nil)

			Divider()

			Button("Show Jump Table") {
				appState?.showJumpTable = true
			}
			.keyboardShortcut("j", modifiers: [.command, .shift])
			.disabled(appState?.selectedFunction == nil)
		}

		CommandMenu("Export") {
			Button("Export to IDA Python...") {
				appState?.showExportSheet = true
			}
			.disabled(appState?.selectedBinary == nil)

			Button("Export to Ghidra XML...") {
				exportWithFormat(.ghidraXML)
			}
			.disabled(appState?.selectedBinary == nil)

			Button("Export to Radare2...") {
				exportWithFormat(.radare2)
			}
			.disabled(appState?.selectedBinary == nil)

			Button("Export to Binary Ninja...") {
				exportWithFormat(.binaryNinja)
			}
			.disabled(appState?.selectedBinary == nil)

			Divider()

			Button("Export to JSON...") {
				exportWithFormat(.json)
			}
			.disabled(appState?.selectedBinary == nil)

			Button("Export to CSV...") {
				exportWithFormat(.csv)
			}
			.disabled(appState?.selectedBinary == nil)

			Button("Export to HTML Report...") {
				exportWithFormat(.html)
			}
			.disabled(appState?.selectedBinary == nil)

			Button("Export to Markdown...") {
				exportWithFormat(.markdown)
			}
			.disabled(appState?.selectedBinary == nil)

			Button("Export C Header...") {
				exportWithFormat(.cHeader)
			}
			.disabled(appState?.selectedBinary == nil)
		}
		CommandMenu("Navigate") {
			Button("Go to Address...") {
				appState?.showGoToAddress = true
			}
			.keyboardShortcut("g", modifiers: [.command, .shift])

			Button("Search...") {
				appState?.showSearch = true
			}
			.keyboardShortcut("f", modifiers: .command)
		}
	}

	private func exportWithFormat(_ format: ExportManager.ExportFormat) {
		guard let appState else { return }
		let panel = NSSavePanel()
		panel.allowedContentTypes = [.data]
		panel.nameFieldStringValue = "\(appState.selectedBinary?.name ?? "export").\(format.fileExtension)"

		if panel.runModal() == .OK, let url = panel.url {
			appState.exportTo(format: format, url: url)
		}
	}
}
