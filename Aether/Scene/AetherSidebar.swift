//
//  AetherSidebar.swift
//  Aether
//
//  Created by Christophe Bronner on 2026-06-04.
//

import SwiftUI

struct AetherSidebar: View {
	@Environment(AppState.self) private var appState

	var body: some View {
		@Bindable var appState = appState

		Picker("Tab", selection: $appState.sidebarSelection) {
			ForEach(NavigatorTab.allCases) { item in
				Label(item.title, systemImage: item.icon)
					.help("Show the \(item.title) navigator")
			}
			.labelStyle(.iconOnly)
		}
		.pickerStyle(.segmented)
		.labelsHidden()

		SidebarTab(tab: appState.sidebarSelection)
			.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
			.listStyle(.plain)
			.scrollContentBackground(.hidden)
	}
}

enum NavigatorTab: Hashable, Identifiable, CaseIterable {
	case functions
	case strings
	case imports
	case exports
	case symbols
	case sections

	var id: Self { self }

	var title: LocalizedStringResource {
		switch self {
		case .functions: "Functions"
		case .strings: "Strings"
		case .imports: "Imports"
		case .exports: "Exports"
		case .symbols: "Symbols"
		case .sections: "Sections"
		}
	}

	var icon: String {
		switch self {
		case .functions: return "function"
		case .strings: return "text.quote"
		case .imports: return "arrow.down.square"
		case .exports: return "arrow.up.square"
		case .symbols: return "tag"
		case .sections: return "square.stack.3d.up"
		}
	}
}


private struct SidebarTab: View {
	let tab: NavigatorTab

	var body: some View {
		switch tab {
		case .functions:
			FunctionsTab()
		case .strings:
			StringsListView()
		case .imports:
			ImportsListView()
		case .exports:
			ExportsListView()
		case .symbols:
			SymbolsListView()
		case .sections:
			SectionsListView()
		}
	}
}


// MARK: - Rename Sheet

struct RenameSheet: View {
	let title: String
	let currentName: String
	@Binding var newName: String
	let onSave: (String) -> Void

	@Environment(\.dismiss) private var dismiss

	var body: some View {
		VStack(spacing: 16) {
			Text(title)
				.font(.headline)

			VStack(alignment: .leading, spacing: 4) {
				Text("Current name:")
					.font(.caption)
					.foregroundColor(.secondary)

				Text(currentName)
					.font(.system(.body, design: .monospaced))
					.foregroundColor(.secondary)
			}

			VStack(alignment: .leading, spacing: 4) {
				Text("New name:")
					.font(.caption)
					.foregroundColor(.secondary)

				TextField("Enter new name...", text: $newName)
					.font(.system(.body, design: .monospaced))
					.textFieldStyle(.roundedBorder)
			}

			HStack {
				Button("Cancel") {
					dismiss()
				}
				.keyboardShortcut(.escape)

				Spacer()

				Button("Reset") {
					newName = ""
					onSave("")
					dismiss()
				}

				Button("Rename") {
					onSave(newName)
					dismiss()
				}
				.keyboardShortcut(.return)
				.buttonStyle(.borderedProminent)
				.disabled(newName.isEmpty || newName == currentName)
			}
		}
		.padding(20)
		.frame(width: 400)
	}
}
