import SwiftUI

struct EntropyView: View {
	@Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var entropyResult: EntropyResult?
    @State private var isAnalyzing = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "chart.bar")
                    .font(.title2)
                    .foregroundColor(.blue)
                Text("Entropy Analysis")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()

                if !isAnalyzing {
                    Button("Refresh") { runAnalysis() }
                }

                Button("Close") { dismiss() }
                    .keyboardShortcut(.escape)
            }
            .padding()

            Divider()

            if isAnalyzing {
                VStack {
                    ProgressView()
                    Text("Calculating entropy...")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let result = entropyResult {
                ScrollView {
                    VStack(spacing: 20) {
                        // Overall entropy
                        GroupBox("Overall Entropy") {
                            HStack {
                                Text(String(format: "%.4f / 8.0", result.overallEntropy))
                                    .font(.system(.title2, design: .monospaced))
                                    .fontWeight(.bold)
                                Spacer()
                                EntropyBar(entropy: result.overallEntropy)
                                    .frame(width: 200, height: 20)
                            }
                            .padding(8)
                        }

                        // Section entropies bar chart
                        GroupBox("Section Entropy") {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(result.sectionEntropies) { se in
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text(se.name)
                                                .font(.system(.caption, design: .monospaced))
                                                .frame(width: 100, alignment: .leading)

                                            EntropyBar(entropy: se.entropy)

                                            Text(String(format: "%.4f", se.entropy))
                                                .font(.system(.caption, design: .monospaced))
                                                .frame(width: 60, alignment: .trailing)
                                        }

                                        HStack {
                                            Text(formatSize(se.size))
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                            Spacer()
                                            Text(se.assessment)
                                                .font(.caption2)
                                                .foregroundColor(entropyColor(se.entropy))
                                        }
                                    }
                                }
                            }
                            .padding(8)
                        }

                        // Entropy heatmap
                        GroupBox("Entropy Heatmap (256-byte blocks)") {
                            EntropyHeatmapView(blocks: result.heatmap)
                                .padding(8)
                        }
                    }
                    .padding()
                }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("Click 'Refresh' to calculate entropy")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 600, minHeight: 400)
        .frame(idealWidth: 750, idealHeight: 600)
        .onAppear { runAnalysis() }
    }

    private func runAnalysis() {
        guard let binary = appState.currentFile else { return }
        isAnalyzing = true
        Task.detached(priority: .userInitiated) {
            let analyzer = EntropyAnalyzer()
            let result = analyzer.analyze(binary: binary)
            await MainActor.run {
                self.entropyResult = result
                self.isAnalyzing = false
            }
        }
    }

    private func formatSize(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    private func entropyColor(_ entropy: Double) -> Color {
        if entropy > 7.5 { return .red }
        if entropy > 7.0 { return .orange }
        if entropy > 6.0 { return .yellow }
        return .green
    }
}

// MARK: - Entropy Heatmap

struct EntropyHeatmapView: View {
    let blocks: [EntropyBlock]

    private let cellSize: CGFloat = 4

    var body: some View {
        let columns = 64
        let rows = max(1, (blocks.count + columns - 1) / columns)

        VStack(alignment: .leading, spacing: 4) {
            // Legend
            HStack(spacing: 8) {
                HStack(spacing: 2) {
                    Rectangle().fill(.blue).frame(width: 12, height: 12)
                    Text("0-3").font(.caption2)
                }
                HStack(spacing: 2) {
                    Rectangle().fill(.green).frame(width: 12, height: 12)
                    Text("3-6").font(.caption2)
                }
                HStack(spacing: 2) {
                    Rectangle().fill(.yellow).frame(width: 12, height: 12)
                    Text("6-7").font(.caption2)
                }
                HStack(spacing: 2) {
                    Rectangle().fill(.red).frame(width: 12, height: 12)
                    Text("7-8").font(.caption2)
                }
                Spacer()
                Text("\(blocks.count) blocks")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            // Heatmap grid
            Canvas { context, size in
                for (idx, block) in blocks.enumerated() {
                    let col = idx % columns
                    let row = idx / columns
                    let x = CGFloat(col) * cellSize
                    let y = CGFloat(row) * cellSize
                    let rect = CGRect(x: x, y: y, width: cellSize, height: cellSize)
                    context.fill(Path(rect), with: .color(heatmapColor(block.entropy)))
                }
            }
            .frame(width: CGFloat(columns) * cellSize, height: CGFloat(rows) * cellSize)
        }
    }

    private func heatmapColor(_ entropy: Double) -> Color {
        if entropy > 7.0 { return .red }
        if entropy > 6.0 { return .yellow }
        if entropy > 3.0 { return .green }
        return .blue
    }
}
