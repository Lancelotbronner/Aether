//
//  AetherScene.swift
//  Aether
//
//  Created by Christophe Bronner on 2026-06-04.
//

import SwiftUI
import UniformTypeIdentifiers

struct AetherScene: Scene {
	var body: some Scene {
		DocumentGroup(newDocument: AetherProject.init) { config in
			AetherContentView()
				.environment(config.document.appState)
				.focusedSceneValue(config.document.appState)
		}
		.commands {
			AetherCommands()
			ToolbarCommands()
			SidebarCommands()
			InspectorCommands()
		}
	}
}
