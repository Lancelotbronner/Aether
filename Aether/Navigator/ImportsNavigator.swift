import SwiftUI
import SwiftData

struct ImportsListView: View {
	@Environment(AppState.self) private var appState
	@State private var searchText = ""

	@Query(filter: #Predicate<SymbolModel> { $0.isImport })
	private var symbols: [SymbolModel]

//	var filteredImports: [Symbol] {
//		let imports = appState.imports
//		if searchText.isEmpty {
//			return imports
//		}
//		return imports.filter {
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
