//
//  Inspector.swift
//  Aether
//
//  Created by Christophe Bronner on 2026-06-05.
//

import SwiftUI
import AetherKit

struct Inspector: View {
	@Environment(AppState.self) private var appState

	var body: some View {
		let selectedInstruction = appState.selectedInstruction
		switch true {
		case selectedInstruction != nil:
			InstructionInspector(instruction: selectedInstruction!)
		default:
			ContentUnavailableView("No Selection", systemImage: "magnifyingglass")
				.frame(maxWidth: .infinity, maxHeight: .infinity)
		}
	}
}

private struct InstructionInspector: View {
	@Environment(AppState.self) private var appState
	let instruction: Instruction

	var body: some View {
		Form {
			LabeledContent {
				Text(String(format: "%08llX", instruction.address))
					.foregroundColor(.addressColor)
					.monospaced()
			} label: {
				Text("Address")
			}
			LabeledContent {
				Text(appState.currentFile!.format(hex: instruction.addressRange))
//					.foregroundColor(.secondary)
					.monospaced()
			} label: {
				Text("Bytes")
			}
			LabeledContent {
				HStack {
					Text(instruction.mnemonic)
						.monospaced()
						.fontWeight(instruction.isControlFlow ? .bold : .regular)
					//				.foregroundColor(enhancedMnemonicColor)
//					EnhancedOperandsView(instruction: instruction, branchInfo: branchInfo)
				}
			} label: {
				Text("Assembly")
			}
			LabeledContent {
				VStack(alignment: .leading) {
					let pcode = appState.pcode[instruction.pcode]
					ForEach(pcode.indices, id: \.self) { i in
						PcodeLabel(pcode: pcode[i])
					}
				}
			} label: {
				Text("Pcode")
			}
			// Branch probability badge
//			if let branch = branchInfo, instruction.type == .conditionalJump {
//				ProbabilityBadge(probability: branch.probability)
//					.padding(.horizontal, 4)
//			}
			// Comment
//			if let userComment = appState.comments[instruction.address] {
//				Text("; \(userComment)")
//					.font(.system(.caption, design: .monospaced))
//					.foregroundColor(.yellow)
//			} else if let comment = instruction.comment {
//				Text("; \(comment)")
//					.font(.system(.caption, design: .monospaced))
//					.foregroundColor(.commentColor)
//			}
		}
	}
}

private struct PcodeLabel: View {
	let pcode: Pcode

	var body: some View {
		Text(String(describing: pcode))
			.monospaced()
	}
}
