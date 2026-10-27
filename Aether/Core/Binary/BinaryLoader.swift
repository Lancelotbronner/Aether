import Foundation
import AetherKit

/// Protocol for binary file loaders
nonisolated protocol BinaryLoaderProtocol {
	func canLoad(data: Data) -> Bool
	func load(data: Data) throws -> BinaryFile
}

