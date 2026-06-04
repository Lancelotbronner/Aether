//
//  ImportsNavigator.swift
//  Aether
//
//  Created by Christophe Bronner on 2026-06-04.
//

import SwiftUI

struct ImportsListView: View {
	@Environment(AppState.self) private var appState
	@State private var searchText = ""

	var filteredImports: [Symbol] {
		let imports = appState.imports
		if searchText.isEmpty {
			return imports
		}
		return imports.filter {
			$0.displayName.localizedCaseInsensitiveContains(searchText)
		}
	}

	var body: some View {
		VStack(alignment: .leading) {
			TextField("Search", text: $searchText, prompt: Text("Filter"))
			
			List(filteredImports) { symbol in
				SymbolRow(symbol: symbol)
			}
		}
	}
}
