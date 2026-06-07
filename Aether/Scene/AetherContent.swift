//
//  AetherContentView.swift
//  Aether
//
//  Created by Christophe Bronner on 2026-06-04.
//

import SwiftUI
import UniformTypeIdentifiers

struct AetherContentView: View {
	@Environment(\.undoManager) private var undoManager
	@State private var isTargeted = false
	@Environment(AppState.self) private var appState

	var body: some View {
		@Bindable var appState = appState
		NavigationSplitView {
			AetherSidebar()
				.frame(minWidth: 240)
		} detail: {
			DetailView()
				.toolbar {
					AetherToolbar()
				}
		}
		.inspector(isPresented: $appState.isInspectorPresented) {
			Inspector()
		}
		.onAppear { appState.undoManager = undoManager }
		.sheet(isPresented: $appState.showGoToAddress) {
			GoToAddressSheet()
		}
		.sheet(isPresented: $appState.showSearch) {
			SearchView()
		}
		.sheet(isPresented: $appState.showCallGraph) {
			CallGraphWindowView()
		}
		.sheet(isPresented: $appState.showCryptoDetection) {
			CryptoDetectionView()
		}
		.sheet(isPresented: $appState.showDeobfuscation) {
			DeobfuscationView()
		}
		.sheet(isPresented: $appState.showTypeRecovery) {
			TypeRecoveryView()
		}
		.sheet(isPresented: $appState.showIdiomRecognition) {
			IdiomRecognitionView()
		}
		.sheet(isPresented: $appState.showPseudoCode) {
			PseudoCodeView()
		}
		.sheet(isPresented: $appState.showExportSheet) {
			ExportSheetView()
		}
		.sheet(isPresented: $appState.showSecurityAnalysis) {
			SecurityAnalysisView(
				result: appState.securityAnalysisResult,
				isLoading: appState.isAnalyzingWithAI,
				error: appState.securityAnalysisError
			)
		}
		.sheet(isPresented: $appState.showFridaScript) {
			FridaScriptView()
		}
		.sheet(isPresented: $appState.showAIChat) {
			AIChatView()
		}
		.sheet(isPresented: $appState.showExplainCode) {
			ExplainCodeView()
		}
		.sheet(isPresented: $appState.showAIRename) {
			AIRenameView()
		}
		.sheet(isPresented: $appState.showMalwareDashboard) {
			MalwareDashboardView()
		}
		.sheet(isPresented: $appState.showImportExportBrowser) {
			ImportExportBrowserView()
		}
		.sheet(isPresented: $appState.showEntropyView) {
			EntropyView()
		}
		.sheet(isPresented: $appState.showMalwareFlow) {
			MalwareFlowView()
		}
		.onDrop(of: [UTType.fileURL], isTargeted: $isTargeted) { providers in
			handleDrop(providers: providers)
		}
		.overlay {
			if appState.isLoading {
				LoadingOverlay(
					message: appState.loadingMessage,
					progress: appState.loadingProgress
				)
			}

			// Show welcome message when no file is loaded
			if appState.currentFile == nil && !appState.isLoading {
				WelcomeView()
			}
		}
		.alert("Error", isPresented: $appState.showError) {
			Button("OK") {
				appState.showError = false
			}
		} message: {
			Text(appState.errorMessage ?? "Unknown error")
		}
	}

	private func handleDrop(providers: [NSItemProvider]) -> Bool {
		print(">>> handleDrop called with \(providers.count) providers")
		guard let provider = providers.first else {
			print(">>> No provider found")
			return false
		}

		print(">>> Loading URL from provider...")
		_ = provider.loadObject(ofClass: URL.self) { url, error in
			if let url = url {
				print(">>> Got URL: \(url.path)")
				Task { @MainActor in
					let data = try Data(contentsOf: url)
					await appState.loadFile(data: data)
				}
			} else if let error = error {
				print(">>> Drop error: \(error)")
			}
		}

		return true
	}
}

private struct DetailView: View {
	@State private var bottomPanelHeight: CGFloat = 200
	@Environment(AppState.self) var appState

	var body: some View {
		VStack(spacing: 0) {
			HSplitView {
				DisassemblyView()
					.frame(minWidth: 240)

				if appState.showDecompiler {
					DecompilerView()
						.frame(minWidth: 240)
				}
			}

			if appState.showHexView || appState.showCFG {
				Divider()

				ZStack {
					if appState.showCFG {
						CFGView()
					} else if appState.showHexView {
						HexView()
					}
				}
				.frame(minHeight: 100, idealHeight: bottomPanelHeight, maxHeight: 400)
			}
			
			StatusBarView()
		}
	}
}
