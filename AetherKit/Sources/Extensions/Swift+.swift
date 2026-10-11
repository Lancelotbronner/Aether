//
//  Swift+.swift
//  Aether
//
//  Created by Christophe Bronner on 2026-06-09.
//

nonisolated public extension String {
	@inlinable
	init(cString buffer: UnsafeRawBufferPointer, maxLength: Int = .max, isKnownASCII: Bool = false) {
		self.init(cString: buffer.bindMemory(to: UInt8.self).span, maxLength: maxLength, isKnownASCII: isKnownASCII)
	}

	@inlinable
	init(cString span: Span<UInt8>, maxLength: Int = .max, isKnownASCII: Bool = false) {
		let len = Swift.min(span.firstIndex { $0 == 0 } ?? span.count, maxLength)
		let utf8 = UTF8Span(unchecked: span.extracting(first: len), isKnownASCII: isKnownASCII)
		self.init(copying: utf8)
	}

	var quoted: String {
		"\"\(replacing("\"", with: "\\\"").replacing("\\", with: "\\\\"))\""
	}
}

nonisolated public extension Range {
	mutating func advance(by offset: Bound) where Bound: AdditiveArithmetic {
		self = advanced(by: offset)
	}

	func advanced(by offset: Bound) -> Range where Bound: AdditiveArithmetic {
		Range(uncheckedBounds: (lowerBound + offset, upperBound + offset))
	}
}

nonisolated public extension Span {
	func firstIndex(where predicate: (Element) -> Bool) -> Int? {
		for i in indices where predicate(self[i]) {
			return i
		}
		return nil
	}
}
