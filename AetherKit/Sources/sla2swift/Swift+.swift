//
//  Swift+.swift
//  AetherKit
//
//  Created by Christophe Bronner on 2026-08-02.
//

extension Int {
	func roundedTowardZero(toMultipleOf m: Self) -> Self {
		return self - (self % m)
	}

	func roundedAwayFromZero(toMultipleOf m: Self) -> Self {
		let x = self.roundedTowardZero(toMultipleOf: m)
		if x == self { return x }
		return (m.signum() == self.signum()) ? (x + m) : (x - m)
	}

	func roundedDown(toMultipleOf m: Self) -> Self {
		return (self < 0) ? self.roundedAwayFromZero(toMultipleOf: m)
		: self.roundedTowardZero(toMultipleOf: m)
	}

	func roundedUp(toMultipleOf m: Self) -> Self {
		return (self > 0) ? self.roundedAwayFromZero(toMultipleOf: m)
		: self.roundedTowardZero(toMultipleOf: m)
	}
}
