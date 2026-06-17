//
//  LoadPlugin.swift
//  AetherKit
//
//  Created by Christophe Bronner on 2026-06-06.
//

import Foundation

public typealias LoadPlugin = @concurrent (any LoadContext) async throws -> Void

public protocol LoadContext {
	var data: Data { get }
	var userInfo: UserInfo { get }
	var progress: Progress { get }
	func boolean(for key: String) -> Bool?
	func string(for key: String) -> String?

	var baseAddress: UInt64 { get set }
	func submit(_ entry: EntryDescriptor)
	func submit(_ procedure: ProcedureDescriptor)
	func submit(_ segment: SegmentDescriptor)
	func submit(_ section: SectionDescriptor)
}

//TODO: Load context should provide access to `any Binary` on which you can edit sections, segments, procedures, etc.

public struct EntryDescriptor {
	public var address: UInt64
	public var mode: CpuMode?

	public init(at address: UInt64, mode: CpuMode? = nil) {
		self.address = address
		self.mode = mode
	}
}

public struct ProcedureDescriptor {
	public var address: UInt64
	public var mode: CpuMode?

	public init(at address: UInt64, mode: CpuMode? = nil) {
		self.address = address
		self.mode = mode
	}
}

public struct SectionDescriptor {
	public var name: String
	public var address: UInt64
	public var kind: Kind

	public init(_ name: String, at address: UInt64, is kind: Kind) {
		self.name = name
		self.address = address
		self.kind = kind
	}

	public enum Kind {
		case mapped(Data)
		case virtual(size: UInt64)
	}
}


public struct SegmentDescriptor {
	public var name: String
	public var address: UInt64
	public var size: UInt64

	public init(_ name: String, at address: UInt64, size: UInt64) {
		self.name = name
		self.address = address
		self.size = size
	}
}
