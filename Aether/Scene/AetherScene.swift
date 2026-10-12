import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct AetherScene: Scene {
	var body: some Scene {
		DocumentGroup(editing: .project, contentType: .project) {
			AetherRootView()
		} prepareDocument: { context in
			// seed new documents
		}
		.commands {
			AetherCommands()
			ToolbarCommands()
			SidebarCommands()
			InspectorCommands()
		}
	}
}

private struct AetherRootView: View {
	@Environment(\.modelContext) private var context
	@State private var session = AppState()

	var body: some View {
		AetherContentView()
			.environment(session)
			.focusedSceneValue(session)
			.focusedSceneValue(\.modelContext, context)
			.task {
				// load binary, kick off analysis if needed
//				await session.bootstrap(context: context)
			}
	}
}

extension UTType {
	static let project = UTType(exportedAs: "com.lancelotbronner.aetherproj", conformingTo: .package)
}
