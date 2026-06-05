//
//  SettingsScene.swift
//  Aether
//
//  Created by Christophe Bronner on 2026-06-04.
//

import SwiftUI

struct SettingsScene: Scene {
	var body: some Scene {
		Settings {
			SettingsView()
		}
	}
}

private struct SettingsView: View {
	@Environment(AppState.self) private var appState

	var body: some View {
		TabView {
			Tab("General", systemImage: "gear") {
				GeneralSettingsView()
			}
			Tab("Appearance", systemImage: "paintbrush") {
				AppearanceSettingsView()
			}
			Tab("Analysis", systemImage: "cpu") {
				AnalysisSettingsView()
			}
			Tab("AI", systemImage: "brain") {
				AssistantSettings()
			}
		}
		.frame(width: 500, height: 350)
	}
}

struct GeneralSettingsView: View {
	@AppStorage("autoAnalyze") private var autoAnalyze = true
	@AppStorage("showHexView") private var showHexView = true

	var body: some View {
		Form {
			Toggle("Auto-analyze on file open", isOn: $autoAnalyze)
			Toggle("Show Hex View by default", isOn: $showHexView)
		}
		.padding()
	}
}

struct AppearanceSettingsView: View {
	@AppStorage("fontSize") private var fontSize = 13.0
	@AppStorage("fontName") private var fontName = "SF Mono"

	var body: some View {
		Form {
			Picker("Font", selection: $fontName) {
				Text("SF Mono").tag("SF Mono")
				Text("Menlo").tag("Menlo")
				Text("Monaco").tag("Monaco")
				Text("Courier New").tag("Courier New")
			}

			Slider(value: $fontSize, in: 10...20, step: 1) {
				Text("Font Size: \(Int(fontSize))")
			}
		}
		.padding()
	}
}

struct AnalysisSettingsView: View {
	@AppStorage("deepAnalysis") private var deepAnalysis = false
	@AppStorage("analyzeStrings") private var analyzeStrings = true
	@AppStorage("analyzeXRefs") private var analyzeXRefs = true

	var body: some View {
		Form {
			Toggle("Deep analysis (slower)", isOn: $deepAnalysis)
			Toggle("Analyze strings", isOn: $analyzeStrings)
			Toggle("Analyze cross-references", isOn: $analyzeXRefs)
		}
		.padding()
	}
}
