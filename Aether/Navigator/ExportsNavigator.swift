//
//  ExportsNavigator.swift
//  Aether
//
//  Created by Christophe Bronner on 2026-06-04.
//

import SwiftUI

struct ExportsListView: View {
	@Environment(AppState.self) private var appState
	@State private var searchText = ""

	var filteredExports: [Symbol] {
		let exports = appState.exports
		if searchText.isEmpty {
			return exports
		}
		return exports.filter {
			$0.displayName.localizedCaseInsensitiveContains(searchText)
		}
	}

	var body: some View {
		VStack(alignment: .leading) {
			TextField("Search", text: $searchText, prompt: Text("Filter"))
			
			List(filteredExports) { symbol in
				SymbolRow(symbol: symbol)
			}
		}
	}
}
