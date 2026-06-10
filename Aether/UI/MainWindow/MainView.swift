import SwiftUI
import UniformTypeIdentifiers

// MARK: - Welcome View

struct WelcomeView: View {
	var body: some View {
		VStack(spacing: 20) {
			Image(systemName: "cpu")
				.font(.system(size: 64))
				.foregroundColor(.secondary)

			Text("Aether")
				.font(.largeTitle)
				.fontWeight(.bold)

			Text("Drag and drop a binary file here\nor use File → Open Binary (⌘O)")
				.multilineTextAlignment(.center)
				.foregroundColor(.secondary)

			HStack(spacing: 16) {
				FormatBadge(name: "Mach-O", icon: "apple.logo")
				FormatBadge(name: "ELF", icon: "penguin")
				FormatBadge(name: "PE", icon: "window.badge.plus")
			}
			.padding(.top)
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.background(Color.background)
	}
}

struct FormatBadge: View {
	let name: String
	let icon: String

	var body: some View {
		VStack {
			Image(systemName: icon)
				.font(.title2)
			Text(name)
				.font(.caption)
		}
		.padding(12)
		.background(Color.sidebar)
		.cornerRadius(8)
	}
}

// MARK: - Loading Overlay

struct LoadingOverlay: View {
	let message: String
	let progress: Double

	var body: some View {
		ZStack {
			Color.black.opacity(0.5)

			VStack(spacing: 16) {
				ProgressView()
					.scaleEffect(1.5)
					.progressViewStyle(CircularProgressViewStyle(tint: .accent))

				Text(message)
					.font(.headline)
					.foregroundColor(.white)

				ProgressView(value: progress)
					.frame(width: 200)
					.tint(.accent)
			}
			.padding(32)
			.background(Color.sidebar)
			.cornerRadius(16)
		}
		.ignoresSafeArea()
	}
}

// MARK: - Go To Address Sheet

struct GoToAddressSheet: View {
	@Environment(AppState.self) private var appState
	@Environment(\.dismiss) var dismiss
	@State private var addressText = ""
	@FocusState private var isFocused: Bool

	var body: some View {
		VStack(spacing: 16) {
			Text("Go to Address")
				.font(.headline)

			TextField("Address (hex)", text: $addressText)
				.textFieldStyle(.roundedBorder)
				.focused($isFocused)
				.onSubmit {
					goToAddress()
				}

			HStack {
				Button("Cancel") {
					dismiss()
				}
				.keyboardShortcut(.cancelAction)

				Button("Go") {
					goToAddress()
				}
				.keyboardShortcut(.defaultAction)
				.disabled(parseAddress() == nil)
			}
		}
		.padding()
		.frame(width: 300)
		.onAppear {
			isFocused = true
		}
	}

	private func parseAddress() -> UInt64? {
		var text = addressText.trimmingCharacters(in: .whitespaces)
		if text.hasPrefix("0x") {
			text = String(text.dropFirst(2))
		}
		return UInt64(text, radix: 16)
	}

	private func goToAddress() {
		if let address = parseAddress() {
			appState.goToAddress(address)
			dismiss()
		}
	}
}

// MARK: - Search Sheet

struct SearchSheet: View {
	@Environment(AppState.self) private var appState
	@Environment(\.dismiss) var dismiss
	@State private var searchText = ""
	@State private var searchType: SearchType = .symbols
	@State private var results: [SearchResult] = []
	@FocusState private var isFocused: Bool

	enum SearchType: String, CaseIterable {
		case symbols = "Symbols"
		case strings = "Strings"
		case functions = "Functions"
		case addresses = "Addresses"
	}

	struct SearchResult: Identifiable {
		let id = UUID()
		let name: String
		let address: UInt64
		let type: String
	}

	var body: some View {
		VStack(spacing: 0) {
			// Search header
			VStack(spacing: 12) {
				HStack {
					Image(systemName: "magnifyingglass")
						.foregroundColor(.secondary)

					TextField("Search...", text: $searchText)
						.textFieldStyle(.plain)
						.focused($isFocused)
						.onChange(of: searchText) { _, newValue in
							performSearch()
						}
				}
				.padding(8)
				.background(Color.background)
				.cornerRadius(8)

				Picker("Type", selection: $searchType) {
					ForEach(SearchType.allCases, id: \.self) { type in
						Text(type.rawValue).tag(type)
					}
				}
				.pickerStyle(.segmented)
				.onChange(of: searchType) { _, _ in
					performSearch()
				}
			}
			.padding()

			Divider()

			// Results
			List(results) { result in
				Button {
					appState.goToAddress(result.address)
					dismiss()
				} label: {
					HStack {
						Text(result.name)
							.lineLimit(1)
						Spacer()
						Text(String(format: "0x%llX", result.address))
							.font(.system(.caption, design: .monospaced))
							.foregroundColor(.secondary)
					}
				}
				.buttonStyle(.plain)
			}
			.listStyle(.plain)
		}
		.frame(width: 500, height: 400)
		.onAppear {
			isFocused = true
		}
	}

	private func performSearch() {
		guard !searchText.isEmpty else {
			results = []
			return
		}

		let query = searchText.lowercased()

		switch searchType {
		case .symbols:
			results = appState.symbols
				.filter { $0.name.lowercased().contains(query) }
				.prefix(50)
				.map { SearchResult(name: $0.displayName, address: $0.address, type: "Symbol") }

		case .strings:
			results = appState.strings
				.filter { $0.value.lowercased().contains(query) }
				.prefix(50)
				.map { SearchResult(name: $0.value, address: $0.address, type: "String") }

		case .functions:
			results = appState.functions
				.filter { $0.name.lowercased().contains(query) || $0.shortDisplayName.lowercased().contains(query) }
				.prefix(50)
				.map { SearchResult(name: $0.shortDisplayName, address: $0.startAddress, type: "Function") }

		case .addresses:
			if let addr = UInt64(query.replacingOccurrences(of: "0x", with: ""), radix: 16) {
				results = [SearchResult(name: String(format: "0x%llX", addr), address: addr, type: "Address")]
			} else {
				results = []
			}
		}
	}
}
