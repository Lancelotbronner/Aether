//
//  SectionsNavigator.swift
//  Aether
//
//  Created by Christophe Bronner on 2026-06-04.
//

import SwiftUI

struct SectionsListView: View {
	@Environment(AppState.self) private var appState

	var body: some View {
		@Bindable var appState = appState
		List(appState.currentFile?.sections ?? [], selection: $appState.sectionNavigator) { section in
			SectionRow(section: section)
				.tag(section)
		}
	}
}

struct SectionRow: View {
	let section: Section

	var body: some View {
		VStack(alignment: .leading, spacing: 2) {
			Label(section.fullName, systemImage: section.isExecutable ? "apple.terminal" : "document")
				.font(.caption)
			HStack(alignment: .firstTextBaseline) {
				Text("0x\(String(section.address, radix: 16))")
				Spacer()
				Text(Int64(section.size), format: .byteCount(style: .memory))
			}
			.font(.caption2)
			.foregroundColor(.secondary)
		}
		.monospaced()
		.lineLimit(1)
	}
}
