//
//  Tests.swift
//  CoreAether
//
//  Created by Christophe Bronner on 2026-06-28.
//

import Testing
import CoreAether

@Test func test_uint4_t() {
	var reg = x86_64_register()
	reg.RAX = 0xFFFFFFFF_FFFFFFFF
	#expect(reg.EAX == 0xFFFFFFFF)
	#expect(reg.AX == 0xFFFF)
	#expect(reg.AL == 0xFF)
	#expect(reg.AH == 0xFF)
	reg.EAX = 0
	#expect(reg.RAX == 0xFFFFFFFF_00000000)
	reg.AX = 0xFFFF
	#expect(reg.RAX == 0xFFFFFFFF_0000FFFF)
	#expect(reg.EAX == 0x0000FFFF)
	reg.AL = 0x00
	#expect(reg.RAX == 0xFFFFFFFF_0000FF00)
	#expect(reg.EAX == 0x0000FF00)
	#expect(reg.AX == 0xFF00)
	reg.AH = 0x00
	#expect(reg.RAX == 0xFFFFFFFF_00000000)
	#expect(reg.EAX == 0x00000000)
	#expect(reg.AX == 0x0000)

	reg.RBX = 0xFFFFFFFF_FFFFFFFF
	#expect(reg.EBX == 0xFFFFFFFF)
	#expect(reg.BX == 0xFFFF)
	#expect(reg.BL == 0xFF)
	#expect(reg.BH == 0xFF)
	reg.EBX = 0
	#expect(reg.RBX == 0xFFFFFFFF_00000000)
	reg.BX = 0xFFFF
	#expect(reg.RBX == 0xFFFFFFFF_0000FFFF)
	#expect(reg.EBX == 0x0000FFFF)
	reg.BL = 0x00
	#expect(reg.RBX == 0xFFFFFFFF_0000FF00)
	#expect(reg.EBX == 0x0000FF00)
	#expect(reg.BX == 0xFF00)
	reg.BH = 0x00
	#expect(reg.RBX == 0xFFFFFFFF_00000000)
	#expect(reg.EBX == 0x00000000)
	#expect(reg.BX == 0x0000)
}
