import Foundation
import Testing
import CoreAether

// Evidence for how the `nlist_64` type byte decodes through `n_type_field`.
// The byte is `N_STAB(7-5) | N_PEXT(4) | N_TYPE(3-1) | N_EXT(0)`, so the
// three-bit `n_type` field holds `N_TYPE >> 1` while the SDK `n_type` enum
// constants are byte values (`N_SECT` = 0x0e). Comparing the bitfield directly
// against the enum therefore never matches — use `n_type_of`/`n_stab_of`.
private func typeField(_ byte: UInt8) -> n_type_field {
	return unsafeBitCast(byte, to: n_type_field.self)
}

@Test("the n_type byte's bitfields are shifted extractions of the SDK constants")
func nlistTypeByteLayout() {
	#expect(MemoryLayout<n_type_field>.size == 1)

	let local = typeField(0x0E) // N_SECT
	#expect(local.byte == 0x0E)
	#expect(local.n_ext == false)
	#expect(local.n_pext == false)
	#expect(local.n_stab == .N_NONE)
	#expect(n_type_of(local.byte) == .N_SECT)

	let exported = typeField(0x0F) // N_SECT | N_EXT
	#expect(exported.n_ext == true)
	#expect(n_type_of(exported.byte) == .N_SECT)

	#expect(n_type_of(typeField(0x0A).byte) == .N_INDR)
	#expect(n_type_of(typeField(0x0C).byte) == .N_PBUD)
	#expect(n_type_of(typeField(0x02).byte) == .N_ABS)
	#expect(n_type_of(typeField(0x06).byte) == .N_6)

	// N_STAB (0xe0) is a mask, not an identity: 0x26 and 0x80 are stabs, and
	// the high three bits cannot distinguish N_STSYM from N_GSYM.
	#expect(is_stab(typeField(0x26).byte))
	#expect(is_stab(typeField(0x80).byte))
	#expect(!is_stab(typeField(0x02).byte)) // N_ABS is not a stab
	#expect(!is_stab(typeField(0x0E).byte))
}
