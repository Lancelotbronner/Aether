import SwiftUI

struct HexView: View {
	@Environment(AppState.self) private var appState
	@State private var data: Data = Data()
	@State private var baseAddress: UInt64 = 0
	@State private var bytesPerRow = 16

	var body: some View {
		VStack(spacing: 0) {
			// Header
			HStack {
				Image(systemName: "number")
					.foregroundColor(.accent)
				Text("Hex View")
					.font(.headline)
				Spacer()

				// Bytes per row selector
				Picker("", selection: $bytesPerRow) {
					Text("8").tag(8)
					Text("16").tag(16)
					Text("32").tag(32)
				}
				.pickerStyle(.segmented)
				.frame(width: 120)
			}
			.padding(.horizontal, 12)
			.padding(.vertical, 8)
			.background(Color.sidebar)

			Divider()

			// Hex content
			if data.isEmpty {
				ContentUnavailableView("No data", systemImage: "number.square", description: Text("Select a section to view hex dump"))
					.frame(maxWidth: .infinity, maxHeight: .infinity)
			} else {
				ScrollViewReader { proxy in
					ScrollView {
						LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
							SwiftUI::Section {
								ForEach(0..<rowCount, id: \.self) { rowIndex in
									let start = rowIndex * bytesPerRow
									let end = min(start + bytesPerRow, data.count)
									HexRow(
										data: data,
										byteOffsets: start..<end,
										baseAddress: baseAddress
									)
								}
							} header: {
								HexHeader(bytesPerRow: bytesPerRow)
									.padding(2)
									.background(.windowBackground, in: .rect)
							}
						}
						.scrollTargetLayout()
						.padding(4)
					}
					.scrollTargetBehavior(.viewAligned)
					.onChange(of: appState.selectedAddress) { _, newAddress in
						let rowAddress = (newAddress / UInt64(bytesPerRow)) * UInt64(bytesPerRow)
						withAnimation {
							proxy.scrollTo(rowAddress, anchor: .center)
						}
					}
				}
			}
		}
		.onChange(of: appState.selectedSection, initial: true) {
			if let section = appState.selectedSection {
				data = section.data
				baseAddress = section.address
			} else {
				data = Data()
				baseAddress = 0
			}
		}
	}

	private var rowCount: Int {
		(data.count + bytesPerRow - 1) / bytesPerRow
	}
}

private struct HexHeader: View {
	let bytesPerRow: Int

	var body: some View {
		HStack(spacing: 16) {
			Text("Address")
				.frame(width: 80, alignment: .leading)
			HStack(spacing: 0) {
				ForEach(0..<bytesPerRow, id: \.self) { i in
					Text(String(format: "%02X", i))
						.padding(2)
				}
			}
			Text("ASCII")
			Spacer()
		}
		.monospaced()
		.foregroundColor(.secondary)
	}
}

private struct HexRow: View {
	@Environment(AppState.self) private var appState
	let data: Data
	let byteOffsets: Range<Int>
	let baseAddress: UInt64

	private func address(at offset: Int) -> UInt64 {
		baseAddress + UInt64(byteOffsets[offset])
	}

	private func byte(at offset: Int) -> UInt8 {
		let i = byteOffsets[offset]
		return data[data.startIndex + i]
	}

	var body: some View {
		let rowAddress = baseAddress + UInt64(byteOffsets.first ?? 0)
		HStack(spacing: 16) {
			// Address
			Text(String(format: "%08llX", rowAddress))
				.foregroundColor(.addressColor)
				.frame(width: 80, alignment: .leading)

			// Hex bytes
			HStack(spacing: 0) {
				ForEach(byteOffsets, id: \.self) { i in
					let byteAddress = baseAddress + UInt64(i)
					let isHighlighted = appState.selectedAddressRange.contains(byteAddress)
					let byte = byte(at: i)
					let tint: AnyShapeStyle = switch true {
					case isHighlighted: AnyShapeStyle(Color.accent)
					case byte == 0: AnyShapeStyle(.tertiary)
					default: AnyShapeStyle(.primary)
					}
					Text(String(format: "%02X", byte))
						.foregroundStyle(tint)
						.padding(2)
						.contentShape(.rect)
						.onTapGesture { appState.goToAddress(byteAddress) }
				}
			}
			
			// ASCII representation
			HStack(spacing: 0) {
				ForEach(byteOffsets, id: \.self) { i in
					let byte = byte(at: i)
					let isPrintable = isprint(Int32(byte)) != 0
					let char = isPrintable ? Character(UnicodeScalar(byte)) : "."
					Text(String(char))
						.foregroundStyle(isPrintable ? .primary : .quaternary)
					Text(verbatim: " ")
				}
			}
		}
		.monospaced()
		.id(rowAddress)
	}
}
