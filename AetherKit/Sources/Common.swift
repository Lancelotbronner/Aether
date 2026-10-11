//
//  Common.swift
//  AetherKit
//
//  Created by Christophe Bronner on 2026-06-06.
//

public typealias UserInfo = [String: any Codable & Sendable]

public struct ArchitectureId: RawRepresentable, Sendable {
	public var rawValue: String

	public init(rawValue: String) {
		self.rawValue = rawValue
	}
}

public extension ArchitectureId {
	static let x86 = Self(rawValue: "x86")
	static let x86_64 = Self(rawValue: "x86_64")
	static let aarch64 = Self(rawValue: "aarch64")
}

public struct CpuMode: RawRepresentable, Sendable {
	public var rawValue: UInt8

	public init(rawValue: UInt8) {
		self.rawValue = rawValue
	}

	public static let `default` = Self(rawValue: 0)
}
