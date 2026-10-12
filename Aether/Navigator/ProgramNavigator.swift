import SwiftUI
import SwiftData
import OSLog
import AetherKit

struct ProgramNavigator: View {
	@Environment(\.modelContext) private var modelContext
	@Environment(AppState.self) private var appState
	@Query var binaries: [BinaryModel]

	var body: some View {
		@Bindable var appState = appState
		List(binaries) { binary in
			ProgramRow(model: binary)
				.listRowSeparator(.hidden)
				.contextMenu {
					Button("Load...") {
						do {
							try MachOLoader.load(binary)
						} catch {
							Logger.app.error("Failed to load \(binary.name) binary: \(error)")
						}
					}
					Button("Delete") {
						modelContext.delete(binary)
					}
				}
		}
	}
}

private struct ProgramRow: View {
	let model: BinaryModel

	var body: some View {
		if model.segments.isEmpty && model.sections.isEmpty {
			BinaryLabel(model: model)
		} else {
			DisclosureGroup {
				ForEach(model.segments) { segment in
					SegmentRow(model: segment)
						.listRowSeparator(.hidden)
				}
			} label: {
				BinaryLabel(model: model)
			}
		}
	}
}

struct BinaryLabel: View {
	let model: BinaryModel

	var body: some View {
		Text(model.name)
			.monospaced()
	}
}

private struct SegmentRow: View {
	let model: SegmentModel

	var body: some View {
		if model.sections.isEmpty {
			SegmentLabel(model: model)
		} else {
			DisclosureGroup {
				ForEach(model.sections) { section in
					SectionRow(model: section)
						.listRowSeparator(.hidden)
				}
			} label: {
				SegmentLabel(model: model)
			}
		}
	}
}

struct SegmentLabel: View {
	let model: SegmentModel

	var body: some View {
		Text(model.name)
			.monospaced()
	}
}

private struct SectionRow: View {
	let model: SectionModel

	var body: some View {
		SectionLabel(model: model)
	}
}

struct SectionLabel: View {
	let model: SectionModel

	var body: some View {
		Label {
			VStack(alignment: .leading) {
				Text(model.name)
				HStack(alignment: .firstTextBaseline) {
					Text("0x\(String(model.address, radix: 16))")
					Spacer()
					Text(Int64(model.size), format: .byteCount(style: .memory))
				}
				.font(.caption2)
				.foregroundColor(.secondary)
			}
			.monospaced()
		} icon: {
			Image(systemName: model.isExecutable ? "apple.terminal" : "document")
		}
		.lineLimit(1)
	}
}
