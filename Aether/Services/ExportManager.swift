import Foundation
import AetherKit

// MARK: - Export Manager

/// Handles exporting analysis results to various formats.
///
/// The concrete exporters were legacy (they consumed `BinaryFile` /
/// `Function` / `StringReference`) and were removed in Task 12b — their only
/// caller was the commented-out `AppState.exportTo` body. `ExportFormat` is
/// kept because the Export menu (`AetherCommands`) enumerates the formats.
class ExportManager {

	// MARK: - Export Formats

	enum ExportFormat: String, CaseIterable {
		case idaPython = "IDA Python Script"
		case ghidraXML = "Ghidra XML"
		case radare2 = "Radare2 Script"
		case binaryNinja = "Binary Ninja Script"
		case json = "JSON"
		case csv = "CSV"
		case markdown = "Markdown Report"
		case html = "HTML Report"
		case cHeader = "C Header File"

		var fileExtension: String {
			switch self {
			case .idaPython: return "py"
			case .ghidraXML: return "xml"
			case .radare2: return "r2"
			case .binaryNinja: return "py"
			case .json: return "json"
			case .csv: return "csv"
			case .markdown: return "md"
			case .html: return "html"
			case .cHeader: return "h"
			}
		}
	}
}
