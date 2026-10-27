import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import OSLog
import AetherKit

struct AetherContentView: View {
	@Environment(\.undoManager) private var undoManager
	@Environment(\.modelContext) private var modelContext
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
		.onAppear {
			appState.undoManager = undoManager
			appState.modelContext = modelContext
		}
		.modifier(GoToAddressSheetModifier())
		.modifier(SearchSheetModifier())
		.modifier(CallGraphModifier())
//		.sheet(isPresented: $appState.showCryptoDetection) {
//			CryptoDetectionView()
//		}
//		.sheet(isPresented: $appState.showDeobfuscation) {
//			DeobfuscationView()
//		}
//		.sheet(isPresented: $appState.showTypeRecovery) {
//			TypeRecoveryView()
//		}
//		.sheet(isPresented: $appState.showIdiomRecognition) {
//			IdiomRecognitionView()
//		}
//		.sheet(isPresented: $appState.showPseudoCode) {
//			PseudoCodeView()
//		}
//		.sheet(isPresented: $appState.showExportSheet) {
//			ExportSheetView()
//		}
//		.sheet(isPresented: $appState.showSecurityAnalysis) {
//			SecurityAnalysisView(
//				result: appState.securityAnalysisResult,
//				isLoading: appState.isAnalyzingWithAI,
//				error: appState.securityAnalysisError
//			)
//		}
//		.sheet(isPresented: $appState.showFridaScript) {
//			FridaScriptView()
//		}
//		.sheet(isPresented: $appState.showAIChat) {
//			AIChatView()
//		}
//		.sheet(isPresented: $appState.showExplainCode) {
//			ExplainCodeView()
//		}
//		.sheet(isPresented: $appState.showAIRename) {
//			AIRenameView()
//		}
//		.sheet(isPresented: $appState.showMalwareDashboard) {
//			MalwareDashboardView()
//		}
//		.sheet(isPresented: $appState.showImportExportBrowser) {
//			ImportExportBrowserView()
//		}
//		.sheet(isPresented: $appState.showEntropyView) {
//			EntropyView()
//		}
//		.sheet(isPresented: $appState.showMalwareFlow) {
//			MalwareFlowView()
//		}
//		.alert("Error", isPresented: $appState.showError) {
//			Button("OK") {
//				appState.showError = false
//			}
//		} message: {
//			Text(appState.errorMessage ?? "Unknown error")
//		}
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

				Group {
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

private struct GoToAddressSheetModifier: ViewModifier {
	@Environment(AppState.self) private var appState

	func body(content: Content) -> some View {
		@Bindable var appState = appState
		content.sheet(isPresented: $appState.showGoToAddress) {
			GoToAddressSheet()
		}
	}
}

private struct SearchSheetModifier: ViewModifier {
	@Environment(AppState.self) private var appState

	func body(content: Content) -> some View {
		@Bindable var appState = appState
		content.sheet(isPresented: $appState.showSearch) {
			SearchSheet()
		}
	}
}

private struct CallGraphModifier: ViewModifier {
	@Environment(AppState.self) private var appState

	func body(content: Content) -> some View {
		@Bindable var appState = appState
		content.sheet(isPresented: $appState.showCallGraph) {
			CallGraphWindowView()
		}
	}
}
