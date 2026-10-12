import SwiftUI
import SwiftData

struct ExportsListView: View {
	@Environment(AppState.self) private var appState
	@State private var searchText = ""

	@Query(filter: #Predicate<SymbolModel> { $0.isExport })
	private var symbols: [SymbolModel]

//	var filteredExports: [Symbol] {
//		let exports = appState.exports
//		if searchText.isEmpty {
//			return exports
//		}
//		return exports.filter {
//			$0.displayName.localizedCaseInsensitiveContains(searchText)
//		}
//	}

	var body: some View {
		VStack(alignment: .leading) {
			TextField("Search", text: $searchText, prompt: Text("Filter"))
			
			List(symbols) { symbol in
				SymbolRow(model: symbol)
			}
		}
	}
}
