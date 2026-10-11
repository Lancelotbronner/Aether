//
//  SleighTests.swift
//  AetherKit
//
//  Created by Christophe Bronner on 2026-06-30.
//

import Foundation
import Testing
import AetherKit
import sla2swift

@Test func z80() throws {
	let url = URL(fileURLWithPath: "/Users/lancelot/Developer/Hacking/Aether/Processors/z80.json")
	let data = try Data(contentsOf: url)
	let doc = try JSONDecoder().decode(SleighSpec.Document.self, from: data)
	let config = ArchitectureConfiguration(
		name: "Z80")
	print("\n<===| C Header |===>\n")
	print(doc.toHeader)
	print("\n<===| Swift |===>\n")
	print(doc.toSwift(using: config))
}

@Test func x86_64() throws {
	let url = URL(fileURLWithPath: "/Users/lancelot/Developer/Hacking/Aether/Processors/x86-64.json")
	let data = try Data(contentsOf: url)
	let doc = try JSONDecoder().decode(SleighSpec.Document.self, from: data)
	let config = ArchitectureConfiguration(
		name: "X86_64")
	print("\n<===| C Header |===>\n")
	print(doc.toHeader)
	print("\n<===| Swift |===>\n")
	print(doc.toSwift(using: config))
}
