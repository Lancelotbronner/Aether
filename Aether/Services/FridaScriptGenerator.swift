import Foundation

// MARK: - Enums

enum FridaPlatform: String, CaseIterable, Identifiable {
    case iOS = "iOS"
    case macOS = "macOS"

    var id: String { rawValue }
}

enum FridaHookType: String, CaseIterable, Identifiable {
    case trace = "Trace"
    case bypass = "Bypass"
    case intercept = "Intercept"
    case dump = "Memory Dump"
    case stringPatch = "String Patch"
    case antiDebug = "Anti-Debug"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .trace: return "eye"
        case .bypass: return "shield.slash"
        case .intercept: return "arrow.left.arrow.right"
        case .dump: return "memorychip"
        case .stringPatch: return "textformat"
        case .antiDebug: return "ladybug"
        }
    }
}

// MARK: - Result Structures

struct FridaScriptResult: Identifiable {
    let id = UUID()
    let script: String
    let platform: FridaPlatform
    let hookType: FridaHookType
    let targetFunctions: [String]
    let description: String
    let moduleName: String
    let offsets: [UInt64]
}

struct AIFridaScriptResult: Identifiable {
    let id = UUID()
    let script: String
    let explanation: String
    let hookPoints: [String]
    let bypassImplemented: [String]
    let warnings: [String]
}

