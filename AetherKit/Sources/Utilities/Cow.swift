//
//  Cow.swift
//  AetherKit
//
//  Created by Christophe Bronner on 2026-06-12.
//

@propertyWrapper
public struct Cow<T: Copyable> {
	@usableFromInline var _storage: Storage

	@usableFromInline
	final class Storage {
		@usableFromInline
		var value: T

		@usableFromInline
		init(_ value: T) {
			self.value = value
		}
	}

	@inlinable @_transparent
	public init(wrappedValue: T) {
		_storage = Storage(wrappedValue)
	}

	public var wrappedValue: T {
		@inlinable @_transparent
		_read {
			yield _storage.value
		}
		@inlinable @_transparent
		_modify {
			if !isKnownUniquelyReferenced(&_storage) {
				_storage = Storage(_storage.value)
			}
			yield &_storage.value
		}
	}
}
