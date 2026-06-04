import SwiftUI

struct ImportExportBrowserView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.title2)
                Text("Import / Export Browser")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.escape)
            }
            .padding()

            Divider()

            // Tabs
            Picker("View", selection: $selectedTab) {
                Text("Imports (\(appState.imports.count))").tag(0)
                Text("Exports (\(appState.exports.count))").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            // Search
            TextField("Search", text: $searchText, prompt: Text("Filter"))

            Divider()

            // Content
            if selectedTab == 0 {
                ImportTreeView(imports: filteredImports, onNavigate: { addr in
                    appState.goToAddress(addr)
                    dismiss()
                })
            } else {
                ExportListView(exports: filteredExports, onNavigate: { addr in
                    appState.goToAddress(addr)
                    dismiss()
                })
            }
        }
        .frame(minWidth: 500, minHeight: 400)
        .frame(idealWidth: 600, idealHeight: 500)
    }

    private var filteredImports: [Symbol] {
        if searchText.isEmpty { return appState.imports }
        return appState.imports.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private var filteredExports: [Symbol] {
        if searchText.isEmpty { return appState.exports }
        return appState.exports.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
}

// MARK: - Import Tree View (grouped by DLL)

struct ImportTreeView: View {
    let imports: [Symbol]
    let onNavigate: (UInt64) -> Void

    var groupedImports: [(String, [Symbol])] {
        var groups: [String: [Symbol]] = [:]
        for sym in imports {
            let parts = sym.name.split(separator: "!", maxSplits: 1)
            let dll = parts.count > 1 ? String(parts[0]) : "unknown"
            groups[dll, default: []].append(sym)
        }
        return groups.sorted { $0.key < $1.key }
    }

    var body: some View {
        List {
            ForEach(groupedImports, id: \.0) { dll, symbols in
                DisclosureGroup {
                    ForEach(symbols) { sym in
                        Button {
                            onNavigate(sym.address)
                        } label: {
                            HStack {
                                Image(systemName: "f.square")
                                    .foregroundColor(.blue)
                                    .font(.caption)

                                let funcName = sym.name.split(separator: "!", maxSplits: 1).last.map(String.init) ?? sym.name
                                Text(funcName)
                                    .font(.system(.caption, design: .monospaced))

                                Spacer()

                                if sym.address != 0 {
                                    Text(String(format: "0x%llX", sym.address))
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } label: {
                    HStack {
                        Image(systemName: "shippingbox")
                            .foregroundColor(.orange)
                        Text(dll)
                            .fontWeight(.medium)
                        Text("(\(symbols.count))")
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .listStyle(.plain)
    }
}

// MARK: - Export List View

struct ExportListView: View {
    let exports: [Symbol]
    let onNavigate: (UInt64) -> Void

    var body: some View {
        List(exports) { sym in
            Button {
                onNavigate(sym.address)
            } label: {
                HStack {
                    Image(systemName: "arrow.up.square")
                        .foregroundColor(.green)
                        .font(.caption)

                    Text(sym.displayName)
                        .font(.system(.caption, design: .monospaced))

                    Spacer()

                    Text(String(format: "0x%llX", sym.address))
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)
        }
        .listStyle(.plain)
    }
}
