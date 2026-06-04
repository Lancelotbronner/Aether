//
//  AetherToolbar.swift
//  Aether
//
//  Created by Christophe Bronner on 2026-06-04.
//

import SwiftUI

struct AetherToolbar: ToolbarContent {
	@Environment(AppState.self) private var appState
	@Environment(\.openSettings) private var openSettings

	var body: some ToolbarContent {
		@Bindable var appState = appState
		Group {
			ToolbarItemGroup {
				Button("Open", systemImage: "doc.badge.plus") {
					appState.openFile()
				}
				.keyboardShortcut("O", modifiers: .command)

				Button("Save", systemImage: "square.and.arrow.down") {
					appState.saveFileAs()
				}
				.keyboardShortcut("S", modifiers: .command)
				.disabled(appState.currentFile == nil)

				Button("Close", systemImage: "xmark.circle") {
					appState.closeFile()
				}
				.keyboardShortcut("W", modifiers: .command)
				.disabled(appState.currentFile == nil)

				if appState.hasUnsavedChanges {
					Circle()
						.fill(Color.orange)
						.frame(width: 8, height: 8)
						.help("Unsaved changes")
				}
			}

			ToolbarSpacer()

			ToolbarItemGroup {
				Button("Analyze", systemImage: "cpu") {
					appState.analyzeAll()
				}
				.keyboardShortcut("A", modifiers: .command)
				.disabled(appState.currentFile == nil)

				Button("Functions", systemImage: "function") {
					appState.findFunctions()
				}
			} label: {
				Text("Analysis")
			}

			ToolbarSpacer()

			ToolbarItemGroup {
				Toggle("Decompiler", systemImage: "rectangle.split.2x1", isOn: $appState.showDecompiler)
				Toggle("Hex View", systemImage: "rectangle.bottomhalf.filled", isOn: $appState.showHexView)

				Button("CFG", systemImage: "point.3.connected.trianglepath.dotted") {
					appState.analyzeAll()
				}
				.keyboardShortcut("G", modifiers: .command)
				.disabled(appState.selectedFunction == nil)
			} label: {
				Text("View")
			}

			ToolbarSpacer()
		}

		ToolbarItemGroup {
			Menu("AI", systemImage: "brain") {
				if appState.hasAIAPIKey {
					// Chat
					Button {
						appState.showAIChat = true
					} label: {
						Label("Chat with AI...", systemImage: "bubble.left.and.bubble.right")
					}

					Divider()

					// Code Understanding
					Button {
						appState.explainCurrentFunction()
					} label: {
						Label("Explain Function", systemImage: "text.bubble")
					}
					.disabled(appState.selectedFunction == nil)

					Button {
						appState.suggestVariableNames()
					} label: {
						Label("Rename Variables", systemImage: "textformat.abc")
					}
					.disabled(appState.selectedFunction == nil || appState.decompilerOutput.isEmpty)

					Divider()

					// Security Analysis
					Button {
						appState.analyzeWithAI()
					} label: {
						Label("Security Analysis", systemImage: "shield.lefthalf.filled")
					}
					.disabled(appState.selectedFunction == nil)

					Button {
						appState.analyzeBinaryWithAI()
					} label: {
						Label("Analyze Binary", systemImage: "doc.viewfinder")
					}
					.disabled(appState.currentFile == nil)

					Divider()

					// Malware Flow
					Button {
						appState.showMalwareFlow = true
					} label: {
						Label("Malware Behavior Flow", systemImage: "arrow.triangle.branch")
					}
					.disabled(appState.currentFile == nil)
				} else {
					Button {
						openSettings()
					} label: {
						Label("Set API Key in Settings...", systemImage: "key")
					}
				}
			}
			.disabled(!appState.hasAIAPIKey)

			Menu("Malware", systemImage: "shield.lefthalf.filled") {
				Button {
					appState.showMalwareDashboard = true
					if appState.malwareReport == nil {
						appState.analyzeMalware()
					}
				} label: {
					Label("Malware Dashboard", systemImage: "shield.lefthalf.filled")
				}

				Button {
					appState.analyzeMalware()
					appState.showMalwareDashboard = true
				} label: {
					Label("Run Analysis", systemImage: "play.fill")
				}

				Divider()

				Button {
					appState.showEntropyView = true
				} label: {
					Label("Entropy Analysis", systemImage: "chart.bar")
				}

				Button {
					appState.showMalwareFlow = true
				} label: {
					Label("AI Behavior Flow", systemImage: "arrow.triangle.branch")
				}
				.disabled(!appState.hasAIAPIKey)

				Button {
					appState.showImportExportBrowser = true
				} label: {
					Label("Import/Export Browser", systemImage: "arrow.left.arrow.right")
				}
			}
			.disabled(appState.currentFile == nil)
		} label: {
			Text("Assistant")
		}

		ToolbarSpacer()

		ToolbarItemGroup {
			Menu("Plugins", systemImage: "hammer.fill") {
				Button {
					appState.generateFridaScript()
				} label: {
					Label("Generate Basic Script", systemImage: "doc.text")
				}
				.disabled(appState.selectedFunction == nil)

				if appState.hasAIAPIKey {
					Button {
						appState.generateFridaScriptWithAI()
					} label: {
						Label("Generate with AI", systemImage: "brain")
					}
					.disabled(appState.selectedFunction == nil)
				}

				Button {
					appState.generateMultiFunctionFridaScript()
				} label: {
					Label("Hook Multiple Functions", systemImage: "list.bullet")
				}
				.disabled(appState.functions.isEmpty)

				Divider()

				// Platform submenu
				Menu("Platform") {
					ForEach(FridaPlatform.allCases) { platform in
						Button {
							appState.selectedFridaPlatform = platform
						} label: {
							HStack {
								Text(platform.rawValue)
								if appState.selectedFridaPlatform == platform {
									Image(systemName: "checkmark")
								}
							}
						}
					}
				}

				// Hook type submenu
				Menu("Hook Type") {
					ForEach(FridaHookType.allCases) { type in
						Button {
							appState.selectedFridaHookType = type
						} label: {
							HStack {
								Label(type.rawValue, systemImage: type.icon)
								if appState.selectedFridaHookType == type {
									Image(systemName: "checkmark")
								}
							}
						}
					}
				}
			}
			.disabled(appState.currentFile == nil)
		}

		ToolbarSpacer()

		ToolbarItemGroup {
			Button("Search", systemImage: "magnifyingglass") {
				appState.showSearch = true
			}
		}

		ToolbarSpacer()

		ToolbarItemGroup {
			Button("Go to", systemImage: "arrow.right.circle") {
				appState.showGoToAddress = true
			}
			.keyboardShortcut("G")
			.disabled(appState.currentFile == nil)
		}
	}
}
