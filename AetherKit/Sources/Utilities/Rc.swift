@propertyWrapper
public nonisolated final class Rc<T: ~Copyable> {
	public var wrappedValue: T

	public init(_ value: consuming T) {
		wrappedValue = value
	}
}
