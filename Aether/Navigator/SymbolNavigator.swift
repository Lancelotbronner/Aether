//
//  SymbolNavigator.swift
//  Aether
//
//  Created by Christophe Bronner on 2026-06-04.
//

import SwiftUI

struct SymbolsListView: View {
	@Environment(AppState.self) private var appState
	@State private var searchText = ""

	var filteredSymbols: [Symbol] {
		if searchText.isEmpty {
			return appState.symbols
		}
		return appState.symbols.filter {
			$0.displayName.localizedCaseInsensitiveContains(searchText)
		}
	}

	var body: some View {
		VStack(alignment: .leading) {
			TextField("Search", text: $searchText, prompt: Text("Filter"))
			
			List(filteredSymbols) { symbol in
				SymbolRow(symbol: symbol)
			}
		}
	}
}

struct SymbolRow: View {
	@Environment(AppState.self) private var appState
	let symbol: Symbol

	var body: some View {
		Button {
			appState.goToAddress(symbol.address)
		} label: {
			VStack(alignment: .leading) {
				Label {
					Text(symbol.displayName)
				} icon: {
					Image(systemName: symbol.type.icon)
						.foregroundColor(symbolColor)
				}
				.font(.caption)

				Text("0x\(String(symbol.address, radix: 16))")
					.font(.caption2)
						.foregroundColor(.secondary)
			}
			.monospaced()
			.lineLimit(1)
		}
		.buttonStyle(.plain)
	}

	private var symbolColor: Color {
		switch symbol.type {
		case .function: .accent
		case .data, .object: .green
		default: .secondary
		}
	}
}
