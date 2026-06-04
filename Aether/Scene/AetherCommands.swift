//
//  AetherCommands.swift
//  Aether
//
//  Created by Christophe Bronner on 2026-06-04.
//

import SwiftUI
import UniformTypeIdentifiers

struct AetherCommands: Commands {
	@FocusedValue(AppState.self) private var appState

	var body: some Commands {
		CommandGroup(after: .newItem) {
			Button("Open Binary...") {
				appState?.openFile()
			}
			.keyboardShortcut("o", modifiers: .command)

			Button("Open Project...") {
				appState?.openProject()
			}
			.keyboardShortcut("o", modifiers: [.command, .shift])

			Divider()

			Button("Save Binary As...") {
				appState?.saveFileAs()
			}
			.keyboardShortcut("s", modifiers: .command)
			.disabled(appState?.currentFile == nil)

			Button("Save Project As...") {
				appState?.saveProjectAs()
			}
			.keyboardShortcut("s", modifiers: [.command, .shift])
			.disabled(appState?.currentFile == nil)

			Divider()

			Button("Close") {
				appState?.closeFile()
			}
			.keyboardShortcut("w", modifiers: .command)
			.disabled(appState?.currentFile == nil)
		}
		CommandMenu("Analysis") {
			Button("Analyze All") {
				appState?.analyzeAll()
			}
			.keyboardShortcut("a", modifiers: [.command, .shift])
			.disabled(appState?.currentFile == nil)

			Button("Find Functions") {
				appState?.findFunctions()
			}
			.keyboardShortcut("f", modifiers: [.command, .shift])
			.disabled(appState?.currentFile == nil)

			Divider()

			Button("Show CFG") {
				appState?.showCFG = true
			}
			.keyboardShortcut("g", modifiers: .command)
			.disabled(appState?.selectedFunction == nil)

			Button("Decompile") {
				appState?.decompileCurrentFunction()
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
			.disabled(appState?.currentFile == nil)

			Button("Crypto Detection") {
				appState?.runCryptoDetection()
			}
			.disabled(appState?.currentFile == nil)

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
			.disabled(appState?.currentFile == nil)

			Button("Export to Ghidra XML...") {
				exportWithFormat(.ghidraXML)
			}
			.disabled(appState?.currentFile == nil)

			Button("Export to Radare2...") {
				exportWithFormat(.radare2)
			}
			.disabled(appState?.currentFile == nil)

			Button("Export to Binary Ninja...") {
				exportWithFormat(.binaryNinja)
			}
			.disabled(appState?.currentFile == nil)

			Divider()

			Button("Export to JSON...") {
				exportWithFormat(.json)
			}
			.disabled(appState?.currentFile == nil)

			Button("Export to CSV...") {
				exportWithFormat(.csv)
			}
			.disabled(appState?.currentFile == nil)

			Button("Export to HTML Report...") {
				exportWithFormat(.html)
			}
			.disabled(appState?.currentFile == nil)

			Button("Export to Markdown...") {
				exportWithFormat(.markdown)
			}
			.disabled(appState?.currentFile == nil)

			Button("Export C Header...") {
				exportWithFormat(.cHeader)
			}
			.disabled(appState?.currentFile == nil)
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
		panel.nameFieldStringValue = "\(appState.currentFile?.name ?? "export").\(format.fileExtension)"

		if panel.runModal() == .OK, let url = panel.url {
			appState.exportTo(format: format, url: url)
		}
	}
}
