import SwiftUI
import UniformTypeIdentifiers
import AetherKit

// MARK: - Call Graph Window View

struct CallGraphWindowView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "arrow.triangle.branch")
                    .foregroundColor(.accent)
                Text("Call Graph")
                    .font(.headline)
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()
            .background(Color.sidebar)

            Divider()

			CallGraphView()
        }
        .frame(width: 900, height: 600)
    }
}
