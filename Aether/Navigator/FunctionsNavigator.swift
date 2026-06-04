//
//  FunctionsNavigator.swift
//  Aether
//
//  Created by Christophe Bronner on 2026-06-04.
//

import SwiftUI

struct FunctionsTab: View {
	@Environment(AppState.self) private var appState
	@State private var searchText = ""

	var filteredFunctions: [Function] {
		if searchText.isEmpty {
			return appState.functions
		}
		return appState.functions.filter {
			$0.name.localizedCaseInsensitiveContains(searchText) ||
			$0.shortDisplayName.localizedCaseInsensitiveContains(searchText)
		}
	}

	var body: some View {
		@Bindable var appState = appState
		VStack(alignment: .leading) {
			TextField("Search", text: $searchText, prompt: Text("Filter"))
			
			List(filteredFunctions, selection: $appState.functionNavigator) { func_ in
				FunctionRow(function: func_, isSelected: appState.selectedFunction == func_)
					.tag(func_)
					.id(func_.startAddress)
					.listRowSeparator(.hidden)
			}
		}
	}
}

struct FunctionRow: View {
	let function: Function
	let isSelected: Bool
	@Environment(AppState.self) private var appState
	@State private var showRenameSheet = false
	@State private var newName = ""

	var displayName: String {
		appState.renamedFunctions[function.startAddress] ?? function.shortDisplayName
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 2) {
			Label(displayName, systemImage: function.isLeaf ? "leaf" : "function")
				.font(.caption)
			HStack(alignment: .firstTextBaseline) {
				Text("0x\(String(function.startAddress, radix: 16))")
					.font(.caption2)
					.foregroundColor(.secondary)
				Spacer()
				Text(Int64(function.size), format: .byteCount(style: .memory))
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
				appState.goToAddress(function.startAddress)
			}

			Divider()

			Button("Copy name") {
				NSPasteboard.general.clearContents()
				NSPasteboard.general.setString(displayName, forType: .string)
			}

			Button("Copy address") {
				NSPasteboard.general.clearContents()
				NSPasteboard.general.setString(String(format: "0x%llX", function.startAddress), forType: .string)
			}
		}
		.sheet(isPresented: $showRenameSheet) {
			RenameSheet(
				title: "Rename Function",
				currentName: displayName,
				newName: $newName,
				onSave: { name in
					appState.renameFunction(at: function.startAddress, to: name)
				}
			)
		}
	}
}
