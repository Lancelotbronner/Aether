//
//  Codable+.swift
//  AetherKit
//
//  Created by Christophe Bronner on 2026-06-30.
//

extension UnkeyedDecodingContainer {
	var remainingCount: Int {
		(count ?? 0) - currentIndex
	}

	private func expect<T: Decodable, R>(
		_ value: T,
		as transform: (T) -> R?
	) throws -> R {
		if let r = transform(value) {
			return r
		}
		let context = DecodingError.Context(
			codingPath: codingPath,
			debugDescription: "Expected \(codingPath.last?.stringValue ?? "")[\(currentIndex)] to be \(R.self) but got \(value)")
		throw DecodingError.valueNotFound(R.self, context)
	}

	mutating func decode<T: Decodable, R>(_ type: T.Type, as transform: (T) -> R?) throws -> R {
		try expect(decode(T.self), as: transform)
	}

	mutating func decodeFirst<T: Decodable>(
		_ type: T.Type,
		count: Int
	) throws -> [T] {
		var tmp: [T] = []
		tmp.reserveCapacity(count)
		while !isAtEnd && tmp.count < count {
			tmp.append(try decode(T.self))
		}
		return tmp
	}

	mutating func decodeFirst<T: Decodable, R>(
		_ type: T.Type,
		count: Int,
		as transform: (T) -> R?
	) throws -> [R] {
		var tmp: [R] = []
		tmp.reserveCapacity(count)
		while !isAtEnd && tmp.count < count {
			tmp.append(try decode(T.self, as: transform))
		}
		return tmp
	}

	mutating func decodeWhile<T: Decodable, R>(
		_ type: T.Type,
		is transform: (T) -> R?
	) throws -> [R] {
		guard !isAtEnd else { return [] }
		var tmp: [R] = []
		tmp.reserveCapacity(remainingCount)
		while !isAtEnd {
			let t = try decode(T.self)
			guard let next = transform(t) else {
				assertionFailure("dropped element")
				break
			}
			tmp.append(next)
		}
		return tmp
	}

	mutating func decodeWhile<T: Decodable, R1, R2>(
		_ type: T.Type,
		is transform1: (T) -> R1?,
		_ transform2: (T) -> R2?
	) throws -> ([R1], [R2]) {
		guard !isAtEnd else { return ([], []) }
		var r1: [R1] = []
		var r2: [R2] = []
		let count = remainingCount
		defer { assert(r1.count + r2.count == count, "dropped elements") }
		r1.reserveCapacity(remainingCount)
		while !isAtEnd {
			let t = try decode(T.self)
			if let t1 = transform1(t) {
				r1.append(t1)
			} else if let t2 = transform2(t) {
				r2.reserveCapacity(remainingCount)
				r2.append(t2)
				break
			}
		}
		while !isAtEnd {
			r2.append(try decode(T.self, as: transform2))
		}
		return (r1, r2)
	}

	mutating func decodeWhile<T: Decodable, R1, R2>(
		_ type: T.Type,
		is transform1: (T) -> R1?,
		_ transform2: (T) -> R2?
	) throws -> ([R1], R2) {
		guard !isAtEnd else {
			// Note: will always throw
			return ([], try decode(T.self, as: transform2))
		}
		var r1: [R1] = []
		var r2: R2?
		let count = remainingCount
		defer { assert(r1.count + (r2 == nil ? 0 : 1) == count, "dropped elements") }
		r1.reserveCapacity(remainingCount)
		while !isAtEnd {
			let t = try decode(T.self)
			if let t1 = transform1(t) {
				r1.append(t1)
			} else if let t2 = transform2(t) {
				r2 = t2
				return (r1, t2)
			}
		}
		r2 = try decode(T.self, as: transform2)
		return (r1, r2!)
	}

	mutating func decodeWhile<T: Decodable, R1, R2, R3>(
		_ type: T.Type,
		is transform1: (T) -> R1?,
		_ transform2: (T) -> R2?,
		_ transform3: (T) -> R3?,
	) throws -> ([R1], [R2], [R3]) {
		guard !isAtEnd else { return ([], [], []) }
		var r1: [R1] = []
		var r2: [R2] = []
		var r3: [R3] = []
		let count = remainingCount
		defer { assert(r1.count + r2.count + r3.count == count, "dropped elements") }
		r1.reserveCapacity(remainingCount)
		while !isAtEnd {
			let t = try decode(T.self)
			if let t1 = transform1(t) {
				r1.append(t1)
			} else if let t2 = transform2(t) {
				r2.reserveCapacity(remainingCount)
				r2.append(t2)
				break
			}
		}
		while !isAtEnd {
			let t = try decode(T.self)
			if let t2 = transform2(t) {
				r2.append(t2)
			} else if let t3 = transform3(t) {
				r3.reserveCapacity(remainingCount)
				r3.append(t3)
				break
			}
		}
		while !isAtEnd {
			r3.append(try decode(T.self, as: transform3))
		}
		return (r1, r2, r3)
	}

	mutating func decodeWhile<T: Decodable, R1, R2, R3, R4>(
		_ type: T.Type,
		is transform1: (T) -> R1?,
		_ transform2: (T) -> R2?,
		_ transform3: (T) -> R3?,
		_ transform4: (T) -> R4?
	) throws -> ([R1], [R2], [R3], [R4]) {
		guard !isAtEnd else { return ([], [], [], []) }
		var r1: [R1] = []
		var r2: [R2] = []
		var r3: [R3] = []
		var r4: [R4] = []
		let count = remainingCount
		defer { assert(r1.count + r2.count + r3.count + r4.count == count, "dropped elements") }
		r1.reserveCapacity(remainingCount)
		while !isAtEnd {
			let t = try decode(T.self)
			if let t1 = transform1(t) {
				r1.append(t1)
				continue
			}
			if let t2 = transform2(t) {
				r2.reserveCapacity(remainingCount)
				r2.append(t2)
			} else if let t3 = transform3(t) {
				r3.reserveCapacity(remainingCount)
				r3.append(t3)
			} else if let t4 = transform4(t) {
				r4.reserveCapacity(remainingCount)
				r4.append(t4)
			}
			break
		}
		if !r2.isEmpty {
			while !isAtEnd {
				let t = try decode(T.self)
				if let t2 = transform2(t) {
					r2.append(t2)
					continue
				}
				if let t3 = transform3(t) {
					r3.reserveCapacity(remainingCount)
					r3.append(t3)
				} else if let t4 = transform4(t) {
					r4.reserveCapacity(remainingCount)
					r4.append(t4)
				}
				break
			}
		}
		if !r3.isEmpty {
			while !isAtEnd {
				let t = try decode(T.self)
				if let t3 = transform3(t) {
					r3.append(t3)
					continue
				}
				if let t4 = transform4(t) {
					r4.reserveCapacity(remainingCount)
					r4.append(t4)
				}
				break
			}
		}
		while !isAtEnd {
			r4.append(try decode(T.self, as: transform4))
		}
		return (r1, r2, r3, r4)
	}

	mutating func decodeRemaining<T: Decodable, R>(
		_ type: T.Type,
		as transform: (T) -> R?
	) throws -> [R] {
		var tmp: [R] = []
		tmp.reserveCapacity(remainingCount)
		while !isAtEnd {
			tmp.append(try decode(T.self, as: transform))
		}
		return tmp
	}
}
