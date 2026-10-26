import SwiftUI
import SwiftData
import AetherKit

struct StringsListView: View {
	@Environment(AppState.self) private var appState
	@State private var searchText = ""

	@Query private var strings: [StringModel]

//	var filteredStrings: [StringReference] {
//		if searchText.isEmpty {
//			return appState.strings
//		}
//		return appState.strings.filter {
//			$0.value.localizedCaseInsensitiveContains(searchText)
//		}
//	}

	var body: some View {
		VStack(alignment: .leading) {
			TextField("Search", text: $searchText, prompt: Text("Filter"))
			
			List(strings) { str in
				Button {
					appState.goToAddress(str.address)
				} label: {
					VStack(alignment: .leading) {
						Text(str.value)
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
