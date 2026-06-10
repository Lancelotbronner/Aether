//
//  Swift+.swift
//  Aether
//
//  Created by Christophe Bronner on 2026-06-09.
//

nonisolated public extension String {
	@inlinable
	init(cString buffer: UnsafeRawBufferPointer, maxLength: Int = .max) {
		let len = Swift.min(buffer.firstIndex(of: 0) ?? buffer.count, maxLength)
		let span = buffer.bindMemory(to: UInt8.self).span.extracting(first: len)
		let utf8 = UTF8Span(unchecked: span, isKnownASCII: true)
		self.init(copying: utf8)
	}
}
