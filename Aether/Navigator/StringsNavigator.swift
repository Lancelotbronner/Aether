import SwiftUI
import SwiftData
import AetherKit

struct StringsListView: View {
	@Environment(AppState.self) private var appState
	@State private var searchText = ""

	@Query private var symbols: [SymbolModel]

	// Strings are now `SymbolModel` rows with a string `type`.
	var strings: [SymbolModel] {
		symbols.filter { $0.type.isString }
	}

	// MUST be in-memory: filtering on a computed/display value, matching
	// the other navigators.
	var filteredStrings: [SymbolModel] {
		guard !searchText.isEmpty else { return strings }
		return strings.filter {
			$0.stringValue.localizedCaseInsensitiveContains(searchText)
		}
	}

	var body: some View {
		VStack(alignment: .leading) {
			TextField("Search", text: $searchText, prompt: Text("Filter"))

			List(filteredStrings) { str in
				Button {
					appState.goToAddress(str.address)
				} label: {
					VStack(alignment: .leading) {
						Text(str.stringValue)
							.font(.caption)
						Spacer()
						Text("0x\(String(str.address, radix: 16))")
							.font(.caption2)
							.foregroundColor(.secondary)
					}
					.monospaced()
					.lineLimit(1)
				}
				.buttonStyle(.plain)
			}
		}
	}
}
