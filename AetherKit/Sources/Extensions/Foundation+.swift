import Foundation

public extension Data {
	func readUInt8(at offset: Int) -> UInt8? {
		guard indices.contains(offset) else { return nil }
		return self[startIndex + offset]
	}

	func readUInt16LE(at offset: Int) -> UInt16? {
		guard offset >= 0, offset + 2 <= count else { return nil }
		return bytes.unsafeLoadUnaligned(fromByteOffset: offset, as: UInt16.self)
	}

	func readUInt16BE(at offset: Int) -> UInt16? {
		readUInt16LE(at: offset)?.byteSwapped
	}

	func readUInt32LE(at offset: some FixedWidthInteger) -> UInt32? {
		guard offset >= 0, offset + 4 <= count else { return nil }
		return bytes.unsafeLoadUnaligned(fromByteOffset: Int(offset), as: UInt32.self)
	}

	func readUInt32BE(at offset: Int) -> UInt32? {
		readUInt32LE(at: offset)?.byteSwapped
	}

	func readUInt64LE(at offset: Int) -> UInt64? {
		guard offset >= 0, offset + 8 <= count else { return nil }
		return bytes.unsafeLoadUnaligned(fromByteOffset: offset, as: UInt64.self)
	}

	func readUInt64BE(at offset: Int) -> UInt64? {
		readUInt64LE(at: offset)?.byteSwapped
	}

	func readInt32LE(at offset: Int) -> Int32? {
		guard let unsigned = readUInt32LE(at: offset) else { return nil }
		return Int32(bitPattern: unsigned)
	}

	func readInt32BE(at offset: Int) -> Int32? {
		guard let unsigned = readUInt32BE(at: offset) else { return nil }
		return Int32(bitPattern: unsigned)
	}

	func readInt64BE(at offset: Int) -> Int64? {
		guard let unsigned = readUInt64BE(at: offset) else { return nil }
		return Int64(bitPattern: unsigned)
	}

	func readCString(at offset: Int) -> String? {
		guard offset >= 0, offset < count else { return nil }
		return bytes.extracting(droppingFirst: offset).withUnsafeBytes {
			String(cString: $0.bindMemory(to: CChar.self).baseAddress!)
		}
	}

	func subdata(offset: Int, count: Int) -> Data? {
		guard offset >= 0, offset + count <= self.count else { return nil }
		return self[startIndex + offset ..< startIndex + offset + count]
	}
}
