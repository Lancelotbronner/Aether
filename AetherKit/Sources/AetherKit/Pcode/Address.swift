//
//  Address.swift
//  AetherKit
//
//  Created by Christophe Bronner on 2026-06-10.
//

public typealias Address = UInt64

public enum AddressSpace: UInt8 {
	case mem, reg, stack, const
}
