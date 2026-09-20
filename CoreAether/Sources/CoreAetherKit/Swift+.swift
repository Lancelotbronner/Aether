//
//  Swift+.swift
//  CoreAether
//
//  Created by Christophe Bronner on 2026-06-28.
//

extension Array {
	subscript(_ position: some FixedWidthInteger, defaultValue defaultValue: @autoclosure () -> Element) -> Element {
		let i = Int(position)
		return indices.contains(i) ? self[i] : defaultValue()
	}
}

/// An unreachable code path.
///
/// This can be used for whenever the compiler can't determine that a
/// path is unreachable, such as dynamically terminating an iterator.
@inline(always)
public func unreachable() -> Never {
	unsafeBitCast((), to: Never.self)
}
