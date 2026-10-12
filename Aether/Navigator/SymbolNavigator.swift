import SwiftUI
import SwiftData

struct SymbolsListView: View {
	@Environment(AppState.self) private var appState
	@Query private var symbols: [SymbolModel]
	@State private var searchText = ""

//	var filteredSymbols: [Symbol] {
//		if searchText.isEmpty {
//			return appState.symbols
//		}
//		return appState.symbols.filter {
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

struct SymbolRow: View {
	@Environment(AppState.self) private var appState
	let model: SymbolModel

	var body: some View {
		Button {
			appState.goToAddress(model.address)
		} label: {
			VStack(alignment: .leading) {
				Label {
					Text(model.displayName)
				} icon: {
					Image(systemName: model.type.icon)
						.foregroundColor(symbolColor)
				}
				.font(.caption)

				Text("0x\(String(model.address, radix: 16))")
					.font(.caption2)
						.foregroundColor(.secondary)
			}
			.monospaced()
			.lineLimit(1)
		}
		.buttonStyle(.plain)
	}

	private var symbolColor: Color {
		switch model.type {
		case .function: .accent
		case .data, .object: .green
		default: .secondary
		}
	}
}
