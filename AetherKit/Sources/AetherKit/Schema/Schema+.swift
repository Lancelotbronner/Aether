import Foundation

public extension SymbolType {
	/// Fixed element width in bytes; 0 for NUL-terminated strings and
	/// untyped data (their extent is discovered, not fixed).
	var byteWidth: Int {
		switch self {
		case .u8: 1
		case .u16, .utf16: 2
		case .u32: 4
		case .u64, .ptr: 8
		case .u128: 16
		case .ascii, .utf8, .function, .unknown: 0
		}
	}

	var isString: Bool {
		self == .ascii || self == .utf8 || self == .utf16
	}
}

public extension BinaryModel {
	func load<T: BitwiseCopyable>(_ type: T.Type, at address: UInt64) -> T {
		let byteOffset = Int(address - baseAddress)
		return data.bytes.unsafeLoadUnaligned(fromByteOffset: byteOffset, as: T.self)
	}

	func ascii(at address: UInt64, maxLength: Int = .max) -> String {
		String(cString: span(at: address), maxLength: maxLength, isKnownASCII: true)
	}

	func unicode(at address: UInt64, maxLength: Int = .max) -> String {
		String(cString: span(at: address), maxLength: maxLength)
	}

	@_lifetime(borrow self)
	func bytes(at address: UInt64) -> RawSpan {
		span(at: address).bytes
	}

	@_lifetime(borrow self)
	func span(at address: UInt64) -> Span<UInt8> {
		let lowerBound = Int(address - baseAddress)
		let span = data.span.extracting(lowerBound...)
		return _overrideLifetime(span, borrowing: self)
	}

	@_lifetime(borrow self)
	func bytes(in range: Range<UInt64>) -> RawSpan {
		span(in: range).bytes
	}

	/// The bytes backing `range`, clamped to the loaded data. Portions of the
	/// range that fall outside the file (e.g. addresses not backed by any
	/// segment) are dropped.
	@_lifetime(borrow self)
	func span(in range: Range<UInt64>) -> Span<UInt8> {
		let count = data.count
		guard range.lowerBound >= baseAddress else {
			let span = data.span.extracting(0..<0)
			return _overrideLifetime(span, borrowing: self)
		}
		let lowerBound = min(Int(range.lowerBound - baseAddress), count)
		let upperBound = min(lowerBound + range.count, count)
		let span = data.span.extracting(lowerBound..<upperBound)
		return _overrideLifetime(span, borrowing: self)
	}

	/// The file data backing `range`, or `nil` if the range is not fully
	/// contained in the loaded data (e.g. it references addresses outside any
	/// mapped segment).
	func data(in range: Range<UInt64>) -> Data? {
		guard range.lowerBound >= baseAddress else { return nil }
		let lowerBound = Int(range.lowerBound - baseAddress)
		let upperBound = lowerBound + range.count
		guard upperBound <= data.count else { return nil }
		return data[lowerBound..<upperBound]
	}

	func format(hex range: Range<UInt64>) -> String {
		let span = span(in: range)
		return span.indices
			.map { String(format: "%02X", span[$0]) }
			.joined(separator: " ")
	}

	static func hex(bytes: consuming Span<UInt8>) -> String {
		bytes.indices
			.map { String(format: "%02X", bytes[$0]) }
			.joined(separator: " ")
	}

	/// Find section containing address
	func section(containing address: UInt64) -> SectionModel? {
		sections.first { $0.contains(address: address) }
	}

	/// Find segment containing address
	func segment(containing address: UInt64) -> SegmentModel? {
		segments.first { $0.contains(address: address) }
	}

	/// Read `count` bytes at virtual `address`. The address is mapped to a
	/// file offset via `baseAddress` (like `data(in:)`); returns `nil` if
	/// the range is not fully contained in the loaded data.
	func read(at address: UInt64, count: Int) -> Data? {
		guard count >= 0 else { return nil }
		let start = data.startIndex
		return data(in: address..<(address + UInt64(count)))?.subdata(in: start..<start + count)
	}

	/// Read null-terminated string at virtual `address` (up to `maxLength`
	/// bytes). Returns `nil` if `address` is not backed by loaded data.
	func readString(at address: UInt64, maxLength: Int = 1024) -> String? {
		// Clamped view: the first byte is file-backed (data(in:) succeeded),
		// but the string may run to the end of the file without a terminator.
		guard let head = data(in: address..<(address + 1)) else { return nil }
		let end = min(head.count + maxLength - 1, data.count)
		let view = data[head.startIndex..<end]
		var i = view.startIndex
		while i < view.endIndex, view[i] != 0 {
			i = view.index(after: i)
		}
		return String(data: view[..<i], encoding: .utf8)
	}
}

public extension SectionModel {
	var addressRange: Range<UInt64> { address..<(address + size) }

	var fullName: String { "\(segmentName),\(name)" }

	var isExecutable: Bool {
		// Mach-O: S_ATTR_PURE_INSTRUCTIONS or S_ATTR_SOME_INSTRUCTIONS
		// PE: IMAGE_SCN_MEM_EXECUTE (0x20000000) or IMAGE_SCN_CNT_CODE (0x20)
		flags & 0x80000000 != 0 || flags & 0x00000400 != 0 ||
		flags & 0x20000000 != 0 || flags & 0x00000020 != 0
	}

	var isZeroFill: Bool {
		// S_ZEROFILL
		(flags & 0xFF) == 1
	}

	var containsCode: Bool {
		isExecutable || name == "__text" || name == ".text" || name == ".code"
	}

	func contains(address addr: UInt64) -> Bool {
		addr >= address && addr < (address + size)
	}
}

public extension SymbolModel {
	var addressRange: Range<UInt64> { address..<(address + size) }

	var isImported: Bool {
		binding == .external && address == 0
	}

	var isExported: Bool {
		binding == .global && address != 0
	}

	var isLocal: Bool {
		binding == .local
	}

	func refresh() {
		isImport = isImported
		isExport = isExported
		name = identifier
	}

	var displayName: String {
		// Demangle if needed
		if name.hasPrefix("_$s") || name.hasPrefix("$s") {
			return demangleSwift(name) ?? name
		} else if name.hasPrefix("__Z") || name.hasPrefix("_Z") {
			return demangleCPP(name) ?? name
		}
		return name.hasPrefix("_") ? String(name.dropFirst()) : name
	}

	/// Basic Swift demangling (simplified)
	private func demangleSwift(_ mangled: String) -> String? {
		// Use swift-demangle if available, otherwise return nil
		// This is a placeholder - real implementation would call swift-demangle
		return nil
	}

	/// Basic C++ demangling (simplified)
	private func demangleCPP(_ mangled: String) -> String? {
		// Use c++filt if available, otherwise return nil
		// This is a placeholder - real implementation would call c++filt
		return nil
	}
}

public extension ProcedureModel {
	func contains(address: UInt64) -> Bool {
		let range = symbol.addressRange
		return range.contains(address)
	}

	var displayName: String {
		if symbol.name.isEmpty {
			return String(format: "sub_%llX", symbol.address)
		}
		// Strip leading underscore for display
		if symbol.name.hasPrefix("_") && !symbol.name.hasPrefix("__") {
			return String(symbol.name.dropFirst())
		}
		return symbol.name
	}

	/// Short display name for headers/UI - formats Java signatures nicely
	var shortDisplayName: String {
		if symbol.name.isEmpty {
			return String(format: "sub_%llX", symbol.address)
		}

		// Check if this looks like a Java method signature
		// Format: className.methodName(descriptor)returnType
		// Detect by: has parenthesis AND has at least 2 dot-separated parts before it
		if let parenIndex = symbol.name.firstIndex(of: "(") {
			let beforeParen = String(symbol.name[..<parenIndex])
			let parts = beforeParen.split(separator: ".")

			// If we have package.class.method format (2+ parts), it's likely Java
			if parts.count >= 2 {
				let className = String(parts[parts.count - 2])
				let methodName = String(parts[parts.count - 1])

				// Parse descriptor to get simple parameter types
				let afterParen = String(symbol.name[parenIndex...])
				let params = parseJavaParams(afterParen)

				if methodName == "<init>" {
					return "\(className)(\(params))"
				} else if methodName == "<clinit>" {
					return "\(className).<clinit>"
				} else {
					return "\(className).\(methodName)(\(params))"
				}
			}
		}

		// For native functions, strip underscore
		if symbol.name.hasPrefix("_") && !symbol.name.hasPrefix("__") {
			return String(symbol.name.dropFirst())
		}

		return symbol.name
	}

	/// Parse Java method descriptor to extract simple parameter types
	private func parseJavaParams(_ descriptor: String) -> String {
		guard let startIdx = descriptor.firstIndex(of: "("),
			  let endIdx = descriptor.firstIndex(of: ")") else {
			return ""
		}

		let paramsStr = String(descriptor[descriptor.index(after: startIdx)..<endIdx])
		if paramsStr.isEmpty { return "" }

		var params: [String] = []
		var idx = paramsStr.startIndex

		while idx < paramsStr.endIndex {
			let c = paramsStr[idx]
			switch c {
			case "B": params.append("byte"); idx = paramsStr.index(after: idx)
			case "C": params.append("char"); idx = paramsStr.index(after: idx)
			case "D": params.append("double"); idx = paramsStr.index(after: idx)
			case "F": params.append("float"); idx = paramsStr.index(after: idx)
			case "I": params.append("int"); idx = paramsStr.index(after: idx)
			case "J": params.append("long"); idx = paramsStr.index(after: idx)
			case "S": params.append("short"); idx = paramsStr.index(after: idx)
			case "Z": params.append("boolean"); idx = paramsStr.index(after: idx)
			case "[":
				// Array - skip to get base type
				idx = paramsStr.index(after: idx)
				continue
			case "L":
				// Object type - find the semicolon
				if let semiIdx = paramsStr[idx...].firstIndex(of: ";") {
					let fullType = String(paramsStr[paramsStr.index(after: idx)..<semiIdx])
					// Get simple class name
					let typeParts = fullType.split(separator: "/")
					params.append(String(typeParts.last ?? Substring(fullType)))
					idx = paramsStr.index(after: semiIdx)
				} else {
					idx = paramsStr.index(after: idx)
				}
			default:
				idx = paramsStr.index(after: idx)
			}
		}

		return params.joined(separator: ", ")
	}
}
