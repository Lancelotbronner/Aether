import Foundation
import CommonCrypto

/// PE/COFF binary format loader (Windows executables)
nonisolated final class PELoader: BinaryLoaderProtocol {

	// MARK: - PE Constants

	private let MZ_MAGIC: UInt16 = 0x5A4D  // "MZ"
	private let PE_SIGNATURE: UInt32 = 0x00004550  // "PE\0\0"

	// Machine types
	private let IMAGE_FILE_MACHINE_I386: UInt16 = 0x014C
	private let IMAGE_FILE_MACHINE_AMD64: UInt16 = 0x8664
	private let IMAGE_FILE_MACHINE_ARM: UInt16 = 0x01C0
	private let IMAGE_FILE_MACHINE_ARM64: UInt16 = 0xAA64

	// Optional header magic
	private let PE32_MAGIC: UInt16 = 0x10B
	private let PE32PLUS_MAGIC: UInt16 = 0x20B

	// Section characteristics
	private let IMAGE_SCN_CNT_CODE: UInt32 = 0x00000020
	private let IMAGE_SCN_MEM_EXECUTE: UInt32 = 0x20000000
	private let IMAGE_SCN_MEM_READ: UInt32 = 0x40000000
	private let IMAGE_SCN_MEM_WRITE: UInt32 = 0x80000000

	// Data Directory indices
	private let IMAGE_DIRECTORY_ENTRY_EXPORT: Int = 0
	private let IMAGE_DIRECTORY_ENTRY_IMPORT: Int = 1
	private let IMAGE_DIRECTORY_ENTRY_RESOURCE: Int = 2
	private let IMAGE_DIRECTORY_ENTRY_DEBUG: Int = 6
	private let IMAGE_DIRECTORY_ENTRY_TLS: Int = 9
	private let IMAGE_DIRECTORY_ENTRY_DELAY_IMPORT: Int = 13

	// MARK: - Data Directory Entry
	struct DataDirectory {
		let virtualAddress: UInt32
		let size: UInt32
	}

	// MARK: - Parsed PE Info (passed between methods)
	struct PEInfo {
		let data: Data
		let imageBase: UInt64
		let is64Bit: Bool
		let sections: [Section]
		let dataDirectories: [DataDirectory]
		let entryPointRVA: UInt32
	}

	// MARK: - Protocol Implementation

	func canLoad(data: Data) -> Bool {
		guard data.count >= 2 else { return false }
		guard let magic = data.readUInt16LE(at: 0) else { return false }
		return magic == MZ_MAGIC
	}

	func load(data: Data) throws -> BinaryFile {
		// Check DOS header
		guard let dosHeader = data.readUInt16LE(at: 0),
			  dosHeader == MZ_MAGIC else {
			throw BinaryLoaderError.invalidHeader
		}

		// Get PE header offset from DOS header
		guard let peOffset = data.readUInt32LE(at: 0x3C) else {
			throw BinaryLoaderError.invalidHeader
		}

		// Validate peOffset
		guard peOffset < 0x10000, Int(peOffset) + 4 <= data.count else {
			throw BinaryLoaderError.corruptedFile("Invalid PE offset: \(peOffset)")
		}

		// Check PE signature
		guard let peSignature = data.readUInt32LE(at: Int(peOffset)),
			  peSignature == PE_SIGNATURE else {
			throw BinaryLoaderError.invalidHeader
		}

		let coffOffset = Int(peOffset) + 4

		// Parse COFF header
		guard coffOffset + 20 <= data.count,
			  let machine = data.readUInt16LE(at: coffOffset),
			  let numberOfSections = data.readUInt16LE(at: coffOffset + 2),
			  let sizeOfOptionalHeader = data.readUInt16LE(at: coffOffset + 16),
			  let characteristics = data.readUInt16LE(at: coffOffset + 18) else {
			throw BinaryLoaderError.invalidHeader
		}

		// Limit number of sections
		guard numberOfSections <= 96 else {
			throw BinaryLoaderError.corruptedFile("Too many sections: \(numberOfSections)")
		}

		let optionalHeaderOffset = coffOffset + 20

		// Parse optional header
		guard optionalHeaderOffset + 2 <= data.count,
			  let optionalMagic = data.readUInt16LE(at: optionalHeaderOffset) else {
			throw BinaryLoaderError.invalidHeader
		}

		let is64Bit = optionalMagic == PE32PLUS_MAGIC

		// Parse optional header fields
		let entryPointRVA: UInt32
		let imageBase: UInt64
		let sectionAlignment: UInt32
		let fileAlignment: UInt32
		let numberOfRvaAndSizes: UInt32

		if is64Bit {
			guard optionalHeaderOffset + 112 <= data.count,
				  let ep = data.readUInt32LE(at: optionalHeaderOffset + 16),
				  let ib = data.readUInt64LE(at: optionalHeaderOffset + 24),
				  let sa = data.readUInt32LE(at: optionalHeaderOffset + 32),
				  let fa = data.readUInt32LE(at: optionalHeaderOffset + 36),
				  let nrva = data.readUInt32LE(at: optionalHeaderOffset + 108) else {
				throw BinaryLoaderError.invalidHeader
			}
			imageBase = ib
			entryPointRVA = ep
			sectionAlignment = sa
			fileAlignment = fa
			numberOfRvaAndSizes = min(nrva, 16)
		} else {
			guard optionalHeaderOffset + 96 <= data.count,
				  let ep = data.readUInt32LE(at: optionalHeaderOffset + 16),
				  let ib = data.readUInt32LE(at: optionalHeaderOffset + 28),
				  let sa = data.readUInt32LE(at: optionalHeaderOffset + 32),
				  let fa = data.readUInt32LE(at: optionalHeaderOffset + 36),
				  let nrva = data.readUInt32LE(at: optionalHeaderOffset + 92) else {
				throw BinaryLoaderError.invalidHeader
			}
			imageBase = UInt64(ib)
			entryPointRVA = ep
			sectionAlignment = sa
			fileAlignment = fa
			numberOfRvaAndSizes = min(nrva, 16)
		}

		let entryPoint = imageBase + UInt64(entryPointRVA)

		// Parse Data Directories
		let dataDirectoryOffset = is64Bit ? optionalHeaderOffset + 112 : optionalHeaderOffset + 96
		var dataDirectories: [DataDirectory] = []
		for i in 0..<Int(numberOfRvaAndSizes) {
			let ddOffset = dataDirectoryOffset + i * 8
			guard ddOffset + 8 <= data.count,
				  let va = data.readUInt32LE(at: ddOffset),
				  let sz = data.readUInt32LE(at: ddOffset + 4) else {
				break
			}
			dataDirectories.append(DataDirectory(virtualAddress: va, size: sz))
		}

		// Parse sections
		let sectionHeaderOffset = optionalHeaderOffset + Int(sizeOfOptionalHeader)
		guard sectionHeaderOffset + Int(numberOfSections) * 40 <= data.count else {
			throw BinaryLoaderError.corruptedFile("Section headers extend beyond file")
		}
		let (sections, segments) = try parseSections(
			data: data,
			offset: sectionHeaderOffset,
			count: Int(numberOfSections),
			imageBase: imageBase
		)

		let peInfo = PEInfo(
			data: data,
			imageBase: imageBase,
			is64Bit: is64Bit,
			sections: sections,
			dataDirectories: dataDirectories,
			entryPointRVA: entryPointRVA
		)

		// Parse symbols (COFF symbol table, if present)
		var symbols = try parseSymbols(data: data, coffOffset: coffOffset, is64Bit: is64Bit)

		// Add entry point as "start" function
		if entryPointRVA != 0 {
			symbols.append(Symbol(
				name: "start",
				address: entryPoint,
				size: 0,
				type: .function,
				binding: .global,
				section: ".text"
			))
		}

		// Parse imports from IAT
		let importSymbols = parseImports(peInfo: peInfo)
		symbols.append(contentsOf: importSymbols)

		// Parse exports
		let exportSymbols = parseExports(peInfo: peInfo)
		symbols.append(contentsOf: exportSymbols)

		return BinaryFile(
			format: .pe,
			architecture: mapMachine(machine),
			endianness: .little,
			is64Bit: is64Bit,
			fileSize: data.count,
			entryPoint: entryPoint,
			baseAddress: imageBase,
			sections: sections,
			segments: segments,
			symbols: symbols,
			data: data
		)
	}

	// MARK: - RVA to File Offset

	private func rvaToFileOffset(rva: UInt32, sections: [Section], imageBase: UInt64) -> Int? {
		for section in sections {
			let sectionRVA = UInt32(section.address - imageBase)
			let sectionSize = UInt32(section.size)
			if rva >= sectionRVA && rva < sectionRVA + sectionSize {
				let offsetInSection = rva - sectionRVA
				return Int(section.offset) + Int(offsetInSection)
			}
		}
		return nil
	}

	// MARK: - Section Parsing

	private func parseSections(
		data: Data,
		offset: Int,
		count: Int,
		imageBase: UInt64
	) throws -> ([Section], [Segment]) {
		var sections: [Section] = []
		var segments: [Segment] = []

		for i in 0..<count {
			let sectOffset = offset + i * 40
			guard sectOffset + 40 <= data.count else { break }

			// Read section name (8 bytes, null-padded)
			guard let nameData = data.subdata(offset: sectOffset, count: 8) else { continue }
			let name = String(data: nameData, encoding: .utf8)?
				.trimmingCharacters(in: .init(charactersIn: "\0")) ?? ""

			guard let virtualSize = data.readUInt32LE(at: sectOffset + 8),
				  let virtualAddress = data.readUInt32LE(at: sectOffset + 12),
				  let sizeOfRawData = data.readUInt32LE(at: sectOffset + 16),
				  let pointerToRawData = data.readUInt32LE(at: sectOffset + 20),
				  let characteristics = data.readUInt32LE(at: sectOffset + 36) else {
				continue
			}

			let addr = imageBase + UInt64(virtualAddress)
			let size = max(virtualSize, sizeOfRawData)

			// Read section data
			let sectionData: Data
			if sizeOfRawData > 0 && pointerToRawData > 0 {
				let start = Int(pointerToRawData)
				let end = min(start + Int(sizeOfRawData), data.count)
				if start < end && start < data.count {
					sectionData = data.subdata(in: start..<end)
				} else {
					sectionData = Data()
				}
			} else {
				sectionData = Data()
			}

			// Convert characteristics to flags
			let isCode = (characteristics & IMAGE_SCN_CNT_CODE) != 0 ||
			(characteristics & IMAGE_SCN_MEM_EXECUTE) != 0
			let flags: UInt32 = isCode ? 0x80000000 : 0

			sections.append(Section(
				name: name,
				segmentName: "",
				address: addr,
				size: UInt64(size),
				offset: pointerToRawData,
				alignment: 0,
				flags: flags,
				data: sectionData
			))

			// Create corresponding segment
			let protection = characteristicsToProtection(characteristics)
			segments.append(Segment(
				name: name,
				address: addr,
				size: UInt64(size),
				fileOffset: UInt64(pointerToRawData),
				fileSize: UInt64(sizeOfRawData),
				maxProtection: protection,
				initProtection: protection
			))
		}

		return (sections, segments)
	}

	// MARK: - Symbol Parsing

	private func parseSymbols(data: Data, coffOffset: Int, is64Bit: Bool) throws -> [Symbol] {
		guard let pointerToSymbolTable = data.readUInt32LE(at: coffOffset + 8),
			  let numberOfSymbols = data.readUInt32LE(at: coffOffset + 12),
			  pointerToSymbolTable > 0, numberOfSymbols > 0 else {
			return []
		}

		// Validate symbol table bounds
		guard numberOfSymbols <= 1_000_000 else { return [] }
		let symTableEnd = Int(pointerToSymbolTable) + Int(numberOfSymbols) * 18
		guard symTableEnd <= data.count else { return [] }

		var symbols: [Symbol] = []

		// String table is right after symbol table
		let stringTableOffset = symTableEnd

		var i = 0
		while i < numberOfSymbols {
			let symOffset = Int(pointerToSymbolTable) + i * 18
			guard symOffset + 18 <= data.count else { break }

			// Read symbol name
			guard symOffset + 8 <= data.count else { break }
			let nameBytes = data.subdata(in: symOffset..<(symOffset + 8))
			let name: String

			// Check if name is inline or in string table
			if nameBytes[nameBytes.startIndex] == 0 && nameBytes[nameBytes.startIndex + 1] == 0 &&
				nameBytes[nameBytes.startIndex + 2] == 0 && nameBytes[nameBytes.startIndex + 3] == 0 {
				// Name is in string table
				guard let strOffset = data.readUInt32LE(at: symOffset + 4) else {
					i += 1
					continue
				}
				let absStrOffset = stringTableOffset + Int(strOffset)
				guard absStrOffset < data.count else {
					i += 1
					continue
				}
				name = data.readCString(at: absStrOffset) ?? ""
			} else {
				name = String(data: nameBytes, encoding: .utf8)?
					.trimmingCharacters(in: .init(charactersIn: "\0")) ?? ""
			}

			guard let value = data.readUInt32LE(at: symOffset + 8),
				  let sectionNumber = data.readUInt16LE(at: symOffset + 12),
				  let type = data.readUInt16LE(at: symOffset + 14),
				  let storageClass = data.readUInt8(at: symOffset + 16),
				  let numberOfAuxSymbols = data.readUInt8(at: symOffset + 17) else {
				i += 1
				continue
			}

			// Skip auxiliary symbols
			i += 1 + Int(numberOfAuxSymbols)

			guard !name.isEmpty else { continue }

			// Determine symbol type
			let symType: SymbolType
			if (type & 0x20) != 0 {
				symType = .function
			} else if sectionNumber > 0 {
				symType = .data
			} else {
				symType = .unknown
			}

			// Determine binding
			let binding: SymbolBinding
			switch storageClass {
			case 2:  // IMAGE_SYM_CLASS_EXTERNAL
				binding = sectionNumber == 0 ? .external : .global
			case 3:  // IMAGE_SYM_CLASS_STATIC
				binding = .local
			case 6:  // IMAGE_SYM_CLASS_LABEL
				binding = .local
			default:
				binding = .local
			}

			symbols.append(Symbol(
				name: name,
				address: UInt64(value),
				size: 0,
				type: symType,
				binding: binding,
				section: nil
			))
		}

		return symbols
	}

	// MARK: - Import Parsing (IAT)

	private func parseImports(peInfo: PEInfo) -> [Symbol] {
		guard peInfo.dataDirectories.count > IMAGE_DIRECTORY_ENTRY_IMPORT else { return [] }
		let importDir = peInfo.dataDirectories[IMAGE_DIRECTORY_ENTRY_IMPORT]
		guard importDir.virtualAddress > 0, importDir.size > 0 else { return [] }

		guard let importTableOffset = rvaToFileOffset(
			rva: importDir.virtualAddress,
			sections: peInfo.sections,
			imageBase: peInfo.imageBase
		) else { return [] }

		var symbols: [Symbol] = []
		var entryOffset = importTableOffset

		// Each Import Directory Entry is 20 bytes
		// OriginalFirstThunk(4), TimeDateStamp(4), ForwarderChain(4), Name(4), FirstThunk(4)
		while entryOffset + 20 <= peInfo.data.count {
			guard let originalFirstThunk = peInfo.data.readUInt32LE(at: entryOffset),
				  let nameRVA = peInfo.data.readUInt32LE(at: entryOffset + 12),
				  let firstThunk = peInfo.data.readUInt32LE(at: entryOffset + 16) else {
				break
			}

			// End of import directory (null entry)
			if originalFirstThunk == 0 && nameRVA == 0 && firstThunk == 0 { break }

			// Read DLL name
			var dllName = "unknown"
			if let nameFileOffset = rvaToFileOffset(rva: nameRVA, sections: peInfo.sections, imageBase: peInfo.imageBase) {
				dllName = peInfo.data.readCString(at: nameFileOffset) ?? "unknown"
			}

			// Read Import Lookup Table (ILT)
			let lookupRVA = originalFirstThunk > 0 ? originalFirstThunk : firstThunk
			guard let lookupOffset = rvaToFileOffset(rva: lookupRVA, sections: peInfo.sections, imageBase: peInfo.imageBase) else {
				entryOffset += 20
				continue
			}

			let entrySize = peInfo.is64Bit ? 8 : 4
			var iltOffset = lookupOffset
			var thunkRVA = firstThunk

			while iltOffset + entrySize <= peInfo.data.count {
				let entry: UInt64
				if peInfo.is64Bit {
					guard let e = peInfo.data.readUInt64LE(at: iltOffset) else { break }
					entry = e
				} else {
					guard let e = peInfo.data.readUInt32LE(at: iltOffset) else { break }
					entry = UInt64(e)
				}

				if entry == 0 { break }

				let ordinalFlag: UInt64 = peInfo.is64Bit ? 0x8000000000000000 : 0x80000000
				let funcName: String

				if (entry & ordinalFlag) != 0 {
					// Import by ordinal
					let ordinal = entry & 0xFFFF
					funcName = "\(dllName)!Ordinal_\(ordinal)"
				} else {
					// Import by name
					let hintRVA = UInt32(entry & 0x7FFFFFFF)
					if let hintOffset = rvaToFileOffset(rva: hintRVA, sections: peInfo.sections, imageBase: peInfo.imageBase),
					   hintOffset + 2 < peInfo.data.count {
						let name = peInfo.data.readCString(at: hintOffset + 2) ?? "unknown"
						funcName = "\(dllName)!\(name)"
					} else {
						funcName = "\(dllName)!unknown"
					}
				}

				let thunkAddress = peInfo.imageBase + UInt64(thunkRVA)
				symbols.append(Symbol(
					name: funcName,
					address: thunkAddress,
					size: 0,
					type: .function,
					binding: .external,
					section: nil
				))

				iltOffset += entrySize
				thunkRVA += UInt32(entrySize)
			}

			entryOffset += 20
		}

		return symbols
	}

	// MARK: - Export Parsing

	private func parseExports(peInfo: PEInfo) -> [Symbol] {
		guard peInfo.dataDirectories.count > IMAGE_DIRECTORY_ENTRY_EXPORT else { return [] }
		let exportDir = peInfo.dataDirectories[IMAGE_DIRECTORY_ENTRY_EXPORT]
		guard exportDir.virtualAddress > 0, exportDir.size > 0 else { return [] }

		guard let exportTableOffset = rvaToFileOffset(
			rva: exportDir.virtualAddress,
			sections: peInfo.sections,
			imageBase: peInfo.imageBase
		) else { return [] }

		// Export Directory Table
		guard exportTableOffset + 40 <= peInfo.data.count,
			  let numberOfNames = peInfo.data.readUInt32LE(at: exportTableOffset + 24),
			  let addressOfFunctions = peInfo.data.readUInt32LE(at: exportTableOffset + 28),
			  let addressOfNames = peInfo.data.readUInt32LE(at: exportTableOffset + 32),
			  let addressOfNameOrdinals = peInfo.data.readUInt32LE(at: exportTableOffset + 36) else {
			return []
		}

		guard numberOfNames <= 100_000 else { return [] }

		guard let namesOffset = rvaToFileOffset(rva: addressOfNames, sections: peInfo.sections, imageBase: peInfo.imageBase),
			  let ordinalsOffset = rvaToFileOffset(rva: addressOfNameOrdinals, sections: peInfo.sections, imageBase: peInfo.imageBase),
			  let functionsOffset = rvaToFileOffset(rva: addressOfFunctions, sections: peInfo.sections, imageBase: peInfo.imageBase) else {
			return []
		}

		var symbols: [Symbol] = []

		for i in 0..<Int(numberOfNames) {
			let nameRVAOffset = namesOffset + i * 4
			let ordinalOffset = ordinalsOffset + i * 2

			guard nameRVAOffset + 4 <= peInfo.data.count,
				  ordinalOffset + 2 <= peInfo.data.count,
				  let nameRVA = peInfo.data.readUInt32LE(at: nameRVAOffset),
				  let ordinal = peInfo.data.readUInt16LE(at: ordinalOffset) else {
				continue
			}

			let funcRVAOffset = functionsOffset + Int(ordinal) * 4
			guard funcRVAOffset + 4 <= peInfo.data.count,
				  let funcRVA = peInfo.data.readUInt32LE(at: funcRVAOffset) else {
				continue
			}

			guard let nameFileOffset = rvaToFileOffset(rva: nameRVA, sections: peInfo.sections, imageBase: peInfo.imageBase) else {
				continue
			}

			let name = peInfo.data.readCString(at: nameFileOffset) ?? "export_\(i)"
			let address = peInfo.imageBase + UInt64(funcRVA)

			symbols.append(Symbol(
				name: name,
				address: address,
				size: 0,
				type: .function,
				binding: .global,
				section: nil
			))
		}

		return symbols
	}

	// MARK: - Imphash Calculation

	func calculateImphash(peInfo: PEInfo) -> String? {
		guard peInfo.dataDirectories.count > IMAGE_DIRECTORY_ENTRY_IMPORT else { return nil }
		let importDir = peInfo.dataDirectories[IMAGE_DIRECTORY_ENTRY_IMPORT]
		guard importDir.virtualAddress > 0, importDir.size > 0 else { return nil }

		guard let importTableOffset = rvaToFileOffset(
			rva: importDir.virtualAddress,
			sections: peInfo.sections,
			imageBase: peInfo.imageBase
		) else { return nil }

		var impEntries: [String] = []
		var entryOffset = importTableOffset

		while entryOffset + 20 <= peInfo.data.count {
			guard let originalFirstThunk = peInfo.data.readUInt32LE(at: entryOffset),
				  let nameRVA = peInfo.data.readUInt32LE(at: entryOffset + 12),
				  let firstThunk = peInfo.data.readUInt32LE(at: entryOffset + 16) else {
				break
			}
			if originalFirstThunk == 0 && nameRVA == 0 && firstThunk == 0 { break }

			var dllName = "unknown"
			if let nameFileOffset = rvaToFileOffset(rva: nameRVA, sections: peInfo.sections, imageBase: peInfo.imageBase) {
				dllName = peInfo.data.readCString(at: nameFileOffset) ?? "unknown"
			}
			// Remove extension for imphash
			if let dotIdx = dllName.lastIndex(of: ".") {
				dllName = String(dllName[..<dotIdx])
			}
			dllName = dllName.lowercased()

			let lookupRVA = originalFirstThunk > 0 ? originalFirstThunk : firstThunk
			if let lookupOffset = rvaToFileOffset(rva: lookupRVA, sections: peInfo.sections, imageBase: peInfo.imageBase) {
				let entrySize = peInfo.is64Bit ? 8 : 4
				var iltOffset = lookupOffset

				while iltOffset + entrySize <= peInfo.data.count {
					let entry: UInt64
					if peInfo.is64Bit {
						guard let e = peInfo.data.readUInt64LE(at: iltOffset) else { break }
						entry = e
					} else {
						guard let e = peInfo.data.readUInt32LE(at: iltOffset) else { break }
						entry = UInt64(e)
					}
					if entry == 0 { break }

					let ordinalFlag: UInt64 = peInfo.is64Bit ? 0x8000000000000000 : 0x80000000
					if (entry & ordinalFlag) != 0 {
						let ordinal = entry & 0xFFFF
						impEntries.append("\(dllName).ord\(ordinal)")
					} else {
						let hintRVA = UInt32(entry & 0x7FFFFFFF)
						if let hintOffset = rvaToFileOffset(rva: hintRVA, sections: peInfo.sections, imageBase: peInfo.imageBase),
						   hintOffset + 2 < peInfo.data.count {
							let name = (peInfo.data.readCString(at: hintOffset + 2) ?? "unknown").lowercased()
							impEntries.append("\(dllName).\(name)")
						}
					}
					iltOffset += entrySize
				}
			}
			entryOffset += 20
		}

		guard !impEntries.isEmpty else { return nil }

		let impString = impEntries.joined(separator: ",")
		guard let data = impString.data(using: .utf8) else { return nil }

		var digest = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
		data.withUnsafeBytes { body in
			_ = CC_MD5(body.baseAddress, CC_LONG(data.count), &digest)
		}
		return digest.map { String(format: "%02x", $0) }.joined()
	}

	// MARK: - Helpers

	private func mapMachine(_ machine: UInt16) -> Architecture {
		switch machine {
		case IMAGE_FILE_MACHINE_AMD64:
			return .x86_64
		case IMAGE_FILE_MACHINE_ARM64:
			return .arm64
		case IMAGE_FILE_MACHINE_I386:
			return .i386
		case IMAGE_FILE_MACHINE_ARM:
			return .armv7
		default:
			return .unknown
		}
	}

	private func characteristicsToProtection(_ characteristics: UInt32) -> UInt32 {
		var prot: UInt32 = 0
		if (characteristics & IMAGE_SCN_MEM_READ) != 0 { prot |= 1 }
		if (characteristics & IMAGE_SCN_MEM_WRITE) != 0 { prot |= 2 }
		if (characteristics & IMAGE_SCN_MEM_EXECUTE) != 0 { prot |= 4 }
		return prot
	}
}
