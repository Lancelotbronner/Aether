import SwiftUI
import SwiftData

struct StringsListView: View {
	@Environment(AppState.self) private var appState
	@State private var searchText = ""

	@Query private var strings: [StringModel]

	// MUST be in-memory (Task 7, handoff 07 §4): `StringModel.value` derives
	// from `@Transient cached`, which is not persisted, so a #Predicate
	// cannot query it.
	var filteredStrings: [StringModel] {
		guard !searchText.isEmpty else { return strings }
		return strings.filter {
			$0.value.localizedCaseInsensitiveContains(searchText)
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
