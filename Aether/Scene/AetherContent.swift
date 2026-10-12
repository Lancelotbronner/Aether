import SwiftUI
import UniformTypeIdentifiers
import OSLog
import AetherKit

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
		Logger.app.debug("handleDrop: \(providers.count) provider(s)")
		guard let provider = providers.first else {
			Logger.app.debug("handleDrop: no provider")
			return false
		}

		_ = provider.loadObject(ofClass: URL.self) { url, error in
			if let url {
				Logger.app.info("Drop: loading \(url.lastPathComponent)")
				Task {
					do {
						// Read off the main actor so large files don't freeze the UI
						let start = ContinuousClock.now
						let data = try await Task.detached(priority: .userInitiated) {
							try Data(contentsOf: url)
						}.value
						Logger.app.info("Drop: read \(data.count) bytes in \(start.duration(to: .now).logDescription)")
						await appState.loadFile(data: data)
					} catch {
						Logger.app.error("Drop: failed to read \(url.lastPathComponent): \(error.localizedDescription)")
					}
				}
			} else if let error {
				Logger.app.error("Drop: \(error.localizedDescription)")
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
					.frame(minWidth: 350)

				if appState.showDecompiler {
					DecompilerView()
						.frame(minWidth: 350)
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
