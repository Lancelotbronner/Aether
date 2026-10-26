import SwiftUI
import SwiftData

struct ExportsListView: View {
	@Environment(AppState.self) private var appState
	@State private var searchText = ""

	@Query(filter: #Predicate<SymbolModel> { $0.isExport })
	private var symbols: [SymbolModel]

	// In-memory filter (Task 7): on the *display* name (computed,
	// underscore-stripped), matching what the row shows.
	var filteredSymbols: [SymbolModel] {
		guard !searchText.isEmpty else { return symbols }
		return symbols.filter {
			$0.displayName.localizedCaseInsensitiveContains(searchText)
		}
	}

	var body: some View {
		VStack(alignment: .leading) {
			TextField("Search", text: $searchText, prompt: Text("Filter"))

			List(filteredSymbols) { symbol in
				SymbolRow(model: symbol)
			}
		}
	}
}
