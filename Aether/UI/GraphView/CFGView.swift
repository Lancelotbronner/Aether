import SwiftUI
import AppKit
import AetherKit

struct CFGView: View {
	@Environment(AppState.self) private var appState
	@State private var scale: CGFloat = 1.0
	@State private var offset: CGSize = .zero
	var showOpenInWindowButton: Bool = true

	// MARK: - Open in Window

	private func openCFGWindow() {
		let window = NSWindow(
			contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
			styleMask: [.titled, .closable, .resizable, .miniaturizable],
			backing: .buffered,
			defer: false
		)

		let functionName = appState.selectedFunction?.symbol.name ?? "CFG"
		window.title = "Control Flow Graph - \(functionName)"
		window.center()
		window.setFrameAutosaveName("CFGWindow")
		window.isReleasedWhenClosed = false
		window.minSize = NSSize(width: 600, height: 400)

		// Create CFG view without the "open in window" button
		let cfgView = CFGView(showOpenInWindowButton: false)
			.environment(appState)
			.focusedSceneValue(appState)

		window.contentView = NSHostingView(rootView: cfgView)
		window.makeKeyAndOrderFront(nil)

		// Store reference to prevent deallocation
		CFGWindowManager.shared.addWindow(window)
	}

	var body: some View {
		VStack(spacing: 0) {
			// Header
			HStack {
				Image(systemName: "point.3.connected.trianglepath.dotted")
					.foregroundColor(.accent)
				Text("Control Flow Graph")
					.font(.headline)

				if let function = appState.selectedFunction {
					Text("- \(function.symbol.name)")
						.font(.subheadline)
						.foregroundColor(.secondary)
						.lineLimit(1)
				}

				Spacer()

				// Zoom controls
				HStack(spacing: 8) {
					Button {
						withAnimation { scale = max(0.25, scale - 0.25) }
					} label: {
						Image(systemName: "minus.magnifyingglass")
					}
					.buttonStyle(.plain)

					Text("\(Int(scale * 100))%")
						.font(.caption)
						.frame(width: 40)

					Button {
						withAnimation { scale = min(2.0, scale + 0.25) }
					} label: {
						Image(systemName: "plus.magnifyingglass")
					}
					.buttonStyle(.plain)

					Button {
						withAnimation {
							scale = 1.0
							offset = .zero
						}
					} label: {
						Image(systemName: "arrow.counterclockwise")
					}
					.buttonStyle(.plain)
					.help("Reset view")

					if showOpenInWindowButton {
						Divider()
							.frame(height: 16)

						Button {
							openCFGWindow()
						} label: {
							Image(systemName: "arrow.up.left.and.arrow.down.right")
						}
						.buttonStyle(.plain)
						.help("Open in separate window")
					}
				}
			}
			.padding(.horizontal, 12)
			.padding(.vertical, 8)
			.background(Color.sidebar)

			Divider()

			// Graph content
			if let function = appState.selectedFunction, !function.blocks.isEmpty {
//				GeometryReader { geometry in
//					ZStack {
//						// Edges
//						ForEach(function.blocks) { block in
//							ForEach(block.successors, id: \.self) { successor in
//								if let startPos = nodePositions[block.startAddress],
//								   let endPos = nodePositions[successor] {
//									EdgeView(
//										from: startPos,
//										to: endPos,
//										isConditional: block.type == .conditional
//									)
//								}
//							}
//						}
//
//						// Nodes
//						ForEach(function.basicBlocks) { block in
//							if let position = nodePositions[block.startAddress] {
//								CFGNodeView(block: block, isSelected: appState.selectedAddress >= block.startAddress && appState.selectedAddress < block.endAddress)
//									.position(position)
//									.onTapGesture {
//										appState.goToAddress(block.startAddress)
//									}
//							}
//						}
//					}
//					.scaleEffect(scale)
//					.offset(offset)
//					.gesture(
//						DragGesture()
//							.onChanged { value in
//								offset = CGSize(
//									width: offset.width + value.translation.width / scale,
//									height: offset.height + value.translation.height / scale
//								)
//							}
//					)
//					.gesture(
//						MagnificationGesture()
//							.onChanged { value in
//								scale = min(max(0.25, scale * value), 2.0)
//							}
//					)
//					.onAppear {
//						layoutGraph(in: geometry.size, blocks: function.basicBlocks)
//					}
//					.onChange(of: function.basicBlocks) { _, newBlocks in
//						layoutGraph(in: geometry.size, blocks: newBlocks)
//					}
//				}
//				.clipped()
			} else {
				ContentUnavailableView("No CFG Available", systemImage: "point.3.connected.trianglepath.dotted", description: Text("Select a function to view its control flow graph"))
					.frame(maxWidth: .infinity, maxHeight: .infinity)
			}
		}
		.background(Color.background)
	}
}

// MARK: - CFG Window Manager

class CFGWindowManager: NSObject, NSWindowDelegate {
	static let shared = CFGWindowManager()

	private var windows: [NSWindow] = []

	private override init() {
		super.init()
	}

	func addWindow(_ window: NSWindow) {
		window.delegate = self
		windows.append(window)
	}

	func windowWillClose(_ notification: Notification) {
		guard let window = notification.object as? NSWindow else { return }
		windows.removeAll { $0 === window }
	}
}
