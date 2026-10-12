import SwiftUI
import SwiftData

struct FunctionsTab: View {
	@Environment(AppState.self) private var appState
	@State private var searchText = ""

	@Query private var procedures: [ProcedureModel]

//	var filteredFunctions: [Function] {
//		if searchText.isEmpty {
//			return appState.functions
//		}
//		return appState.functions.filter {
//			$0.name.localizedCaseInsensitiveContains(searchText) ||
//			$0.shortDisplayName.localizedCaseInsensitiveContains(searchText)
//		}
//	}

	var body: some View {
		@Bindable var appState = appState
		VStack(alignment: .leading) {
			TextField("Search", text: $searchText, prompt: Text("Filter"))
			
			List(procedures, selection: $appState.selectedFunction) { func_ in
				FunctionRow(function: func_, isSelected: appState.selectedFunction == func_)
					.tag(func_)
					.id(func_.symbol.address)
					.listRowSeparator(.hidden)
			}
		}
	}
}

struct FunctionRow: View {
	let function: ProcedureModel
	let isSelected: Bool
	@Environment(AppState.self) private var appState
	@State private var showRenameSheet = false
	@State private var newName = ""

	var displayName: String {
		appState.renamedFunctions[function.symbol.address] ?? function.shortDisplayName
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 2) {
			Label(displayName, systemImage: function.isLeaf ? "leaf" : "function")
				.font(.caption)
			HStack(alignment: .firstTextBaseline) {
				Text("0x\(String(function.symbol.address, radix: 16))")
					.font(.caption2)
					.foregroundColor(.secondary)
				Spacer()
				Text(Int64(function.symbol.size), format: .byteCount(style: .memory))
					.font(.caption2)
					.foregroundColor(.secondary)
			}
		}
		.monospaced()
		.lineLimit(1)
		.contextMenu {
			Button("Rename...") {
				newName = displayName
				showRenameSheet = true
			}

			Button("Go to address") {
				appState.goToAddress(function.symbol.address)
			}

			Divider()

			Button("Copy name") {
				NSPasteboard.general.clearContents()
				NSPasteboard.general.setString(displayName, forType: .string)
			}

			Button("Copy address") {
				NSPasteboard.general.clearContents()
				NSPasteboard.general.setString(String(format: "0x%llX", function.symbol.address), forType: .string)
			}
		}
		.sheet(isPresented: $showRenameSheet) {
			RenameSheet(
				title: "Rename Function",
				currentName: displayName,
				newName: $newName,
				onSave: { name in
					appState.renameFunction(at: function.symbol.address, to: name)
				}
			)
		}
	}
}
