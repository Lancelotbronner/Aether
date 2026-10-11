//
//  OpenPlugin.swift
//  Aether
//
//  Created by Christophe Bronner on 2026-06-05.
//

import Foundation

public typealias OpenPlugin = @concurrent (any OpenContext) async throws -> Void

public protocol OpenContext {
	/// The data to analyze.
	var data: Data { get }
	/// Ask Aether to load a slice of data as a standalone binary within a container.
	/// - Parameters:
	///   - slice: The data to load.
	///   - container: The container in which this slice is placed.
	func load(_ slice: Data)
	/// Submits a detected binary.
	/// - Parameter binary: The binary that was detected
	func submit(_ binary: BinaryDescriptor)
}

public struct BinaryDescriptor {
	public init() {}

	public var userInfo: UserInfo = [:]

	/// The title of this binary, this is what the user will see in the picker.
	public var title: LocalizedStringResource?
	/// Text to be displayed when the binary is selected by the user.
	public var summary: LocalizedStringResource?
	/// The architecture of the binary.
	public var architecture: ArchitectureId?
	/// Additional options for the user.
	public private(set) var options: [String: AnyControl] = [:]
}

public extension BinaryDescriptor {
	mutating func control(_ key: String, is control: some Control) {
		options[key] = control.toAnyControl
	}
}
