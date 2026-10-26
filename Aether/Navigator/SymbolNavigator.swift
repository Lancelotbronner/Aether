import SwiftUI
import SwiftData
import AetherKit

struct SymbolsListView: View {
	@Environment(AppState.self) private var appState
	@Query private var symbols: [SymbolModel]
	@State private var searchText = ""

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
