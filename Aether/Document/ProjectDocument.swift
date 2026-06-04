//
//  ProjectDocument.swift
//  Aether
//
//  Created by Christophe Bronner on 2026-06-04.
//

@preconcurrency import SwiftUI
import Combine
import UniformTypeIdentifiers

@preconcurrency
final class AetherProject: ReferenceFileDocument {
	static let readableContentTypes: [UTType] = [.project, .executable]
	static let writableContentTypes: [UTType] = [.project]

	let objectWillChange = ObservableObjectPublisher()
	let appState = AppState()

	init() {}

	init(configuration: ReadConfiguration) throws {
		switch true {
		case configuration.contentType == .project:
			Task {
				let data = configuration.file.regularFileContents ?? Data()
				try await appState.loadProject(data: data)
			}

		case configuration.contentType.conforms(to: .executable):
			Task {
				let data = configuration.file.regularFileContents ?? Data()
				await appState.loadFile(data: data)
			}

		default:
			preconditionFailure()
		}
	}

	func snapshot(contentType: UTType) throws -> AppState {
		appState
	}
	
	func fileWrapper(snapshot: AppState, configuration: WriteConfiguration) throws -> FileWrapper {
		configuration.existingFile ?? FileWrapper(regularFileWithContents: Data())
	}
}

extension UTType {
	static let project = UTType(exportedAs: "com.lancelotbronner.aether.project", conformingTo: .json)
}
