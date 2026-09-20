//
//  mach-o.h
//  CoreAether
//
//  Created by Christophe Bronner on 2026-06-09.
//

#include <stdbool.h>

/**
 Symbolic debugger symbols.  The comments give the conventional use for
 ```
 .stabs "n_name", n_type, n_sect, n_desc, n_value
 ```

 where `n_type` is the defined constant and not listed in the comment.
 Other fields not listed are zero. `n_sect` is the section ordinal the entry is refering to.
 */
enum [[clang::enum_extensibility(closed)]] n_stab {
	/// not a stab
	N_NONE = 0x00,
	/// global symbol `(n_name: name, n_sect: NO_SECT, n_desc: type, n_value: 0)`
	N_GSYM = 0x20,
	/// procedure name (f77 kludge) `(n_name: name, n_sect: NO_SECT, n_desc: 0, n_value: 0)`
	N_FNAME = 0x22,
	/// procedure `(n_name: name, n_sect: n_sect, n_desc: linenumber, n_value: address)`
	N_FUN = 0x24,
	/// static symbol `(n_name: name, n_sect: n_sect, n_desc: type, n_value: address)`
	N_STSYM = 0x26,
	/// .lcomm symbol `(n_name: name, n_sect: n_sect, n_desc: type, n_value: address)`
	N_LCSYM = 0x28,
	/// begin nsect sym `(n_name: 0, n_sect: n_sect, n_desc: 0, n_value: address)`
	N_BNSYM = 0x2e,
	/// AST file path `(n_name: name, n_sect: NO_SECT, n_desc: 0, n_value: 0)`
	N_AST = 0x32,
	/// emitted with `gcc2_compiled` and in gcc source
	N_OPT = 0x3c,
	/// register sym `(n_name: name, n_sect: NO_SECT, n_desc: type, n_value: register)`
	N_RSYM = 0x40,
	/// src line `(n_name: 0, n_sect: n_sect, n_desc: linenumber, n_value: address)`
	N_SLINE = 0x44,
	/// end nsect sym `(n_name: 0, n_sect: n_sect, n_desc: 0, n_value: address)`
	N_ENSYM = 0x4e,
	/// structure elt `(n_name: name, n_sect: NO_SECT, n_desc: type, n_value: struct_offset)`
	N_SSYM = 0x60,
	/// source file name `(n_name: name, n_sect: n_sect, n_desc: 0, n_value: address)`
	N_SO = 0x64,
	/// object file name `(n_name: name, n_sect: (see below), n_desc: 1, n_value: st_mtime)`
	///
	/// Historically `N_OSO` set `n_sect` to 0.
	/// The `N_OSO` `n_sect` may instead hold the low byte of the `cpusubtype` value from the Mach-O header.
	N_OSO = 0x66,
	/// dynamic library file name `(n_name: name, n_sect: NO_SECT, n_desc: 0, n_value: 0)`
	N_LIB = 0x68   ,
	/// local sym `(n_name: name, n_sect: NO_SECT, n_desc: type, n_value: offset)`
	N_LSYM = 0x80,
	/// include file beginning `(n_name: name, n_sect: NO_SECT, n_desc: 0, n_value: sum)`
	N_BINCL = 0x82,
	/// `#includ`ed file name `(n_name: name, n_sect: n_sect, n_desc: 0, n_value: address)`
	N_SOL = 0x84,
	/// compiler parameters `(n_name: name, n_sect: NO_SECT, n_desc: 0, n_value: 0)`
	N_PARAMS = 0x86,
	/// compiler version `(n_name: name, n_sect: NO_SECT, n_desc: 0, n_value: 0)`
	N_VERSION = 0x88,
	/// compiler -O level `(n_name: name, n_sect: NO_SECT, n_desc: 0, n_value: 0)`
	N_OLEVEL = 0x8A,
	/// parameter `(n_name: name, n_sect: NO_SECT, n_desc: type, n_value: offset)`
	N_PSYM = 0xa0,
	/// include file end `(n_name: name, n_sect: NO_SECT, n_desc: 0, n_value: 0)`
	N_EINCL = 0xa2,
	/// alternate entry `(n_name: name, n_sect: n_sect, n_desc: linenumber, n_value: address)`
	N_ENTRY = 0xa4,
	/// left bracket `(n_name: 0, n_sect: NO_SECT, n_desc: nesting level, n_value: address)`
	N_LBRAC = 0xc0,
	/// deleted include file `(n_name: name, n_sect: NO_SECT, n_desc: 0, n_value: sum)`
	N_EXCL = 0xc2,
	/// right bracket `(n_name: 0, n_sect: NO_SECT, n_desc: nesting level, n_value: address)`
	N_RBRAC = 0xe0,
	/// begin common `(n_name: name, n_sect: NO_SECT, n_desc: 0, n_value: 0)`
	N_BCOMM = 0xe2,
	/// end common `(n_name: name, n_sect: n_sect, n_desc: 0, n_value: 0)`
	N_ECOMM = 0xe4,
	/// end common (local name) `(n_name: 0, n_sect: n_sect, n_desc: 0, n_value: address)`
	N_ECOML = 0xe8,
	/// second stab entry with length information
	N_LENG =0xfe,
	/// global pascal symbol `(n_name: name, n_sect: NO_SECT, n_desc: subtype, n_value: line)`
	///
	/// For the berkeley pascal compiler, pc(1).
	N_PC = 0x30,
};

/// Values for `N_TYPE` bits of the `n_type` field.
enum [[clang::enum_extensibility(closed)]] n_type {
	/// undefined, `n_sect == NO_SECT`
	N_UNDF = 0x0,
	/// absolute, `n_sect == NO_SECT`
	N_ABS = 0x2,
	N_6 = 0x6,
	/// defined in section number `n_sect`
	N_SECT = 0xe,
	/// prebound undefined (defined in a dylib)
	N_PBUD = 0xc,
	/// indirect
	N_INDR = 0xa,
};

/*
 * If the type is N_INDR then the symbol is defined to be the same as another
 * symbol.  In this case the n_value field is an index into the string table
 * of the other symbol's name.  When the other symbol is defined then they both
 * take on the defined type and value.
 */

/*
 * If the type is N_SECT then the n_sect field contains an ordinal of the
 * section the symbol is defined in.  The sections are numbered from 1 and
 * refer to sections in order they appear in the load commands for the file
 * they are in.  This means the same ordinal may very well refer to different
 * sections in different files.
 *
 * The n_value field for all symbol table entries (including N_STAB's) gets
 * updated by the link editor based on the value of it's n_sect field and where
 * the section n_sect references gets relocated.  If the value of the n_sect
 * field is NO_SECT then it's n_value field is not changed by the link editor.
 */
#define	NO_SECT		0	/* symbol is not in any section */
#define MAX_SECT	255	/* 1 thru 255 inclusive */

/*
 * Common symbols are represented by undefined (N_UNDF) external (N_EXT) types
 * who's values (n_value) are non-zero.  In which case the value of the n_value
 * field is the size (in bytes) of the common symbol.  The n_sect field is set
 * to NO_SECT.  The alignment of a common symbol may be set as a power of 2
 * between 2^1 and 2^15 as part of the n_desc field using the macros below. If
 * the alignment is not set (a value of zero) then natural alignment based on
 * the size is used.
 */
#define GET_COMM_ALIGN(n_desc) (((n_desc) >> 8) & 0x0f)
#define SET_COMM_ALIGN(n_desc,align) \
	(n_desc) = (((n_desc) & 0xf0ff) | (((align) & 0x0f) << 8))

/*
 * To support the lazy binding of undefined symbols in the dynamic link-editor,
 * the undefined symbols in the symbol table (the nlist structures) are marked
 * with the indication if the undefined reference is a lazy reference or
 * non-lazy reference.  If both a non-lazy reference and a lazy reference is
 * made to the same symbol the non-lazy reference takes precedence.  A reference
 * is lazy only when all references to that symbol are made through a symbol
 * pointer in a lazy symbol pointer section.
 *
 * The implementation of marking nlist structures in the symbol table for
 * undefined symbols will be to use some of the bits of the n_desc field as a
 * reference type.  The mask REFERENCE_TYPE will be applied to the n_desc field
 * of an nlist structure for an undefined symbol to determine the type of
 * undefined reference (lazy or non-lazy).
 *
 * The constants for the REFERENCE FLAGS are propagated to the reference table
 * in a shared library file.  In that case the constant for a defined symbol,
 * REFERENCE_FLAG_DEFINED, is also used.
 */
/* Reference type bits of the n_desc field of undefined symbols */
#define REFERENCE_TYPE				0x7
/* types of references */
#define REFERENCE_FLAG_UNDEFINED_NON_LAZY		0
#define REFERENCE_FLAG_UNDEFINED_LAZY			1
#define REFERENCE_FLAG_DEFINED				2
#define REFERENCE_FLAG_PRIVATE_DEFINED			3
#define REFERENCE_FLAG_PRIVATE_UNDEFINED_NON_LAZY	4
#define REFERENCE_FLAG_PRIVATE_UNDEFINED_LAZY		5

/*
 * To simplify stripping of objects that use are used with the dynamic link
 * editor, the static link editor marks the symbols defined an object that are
 * referenced by a dynamically bound object (dynamic shared libraries, bundles).
 * With this marking strip knows not to strip these symbols.
 */
#define REFERENCED_DYNAMICALLY	0x0010

/*
 * For images created by the static link editor with the -twolevel_namespace
 * option in effect the flags field of the mach header is marked with
 * MH_TWOLEVEL.  And the binding of the undefined references of the image are
 * determined by the static link editor.  Which library an undefined symbol is
 * bound to is recorded by the static linker in the high 8 bits of the n_desc
 * field using the SET_LIBRARY_ORDINAL macro below.  The ordinal recorded
 * references the libraries listed in the Mach-O's LC_LOAD_DYLIB,
 * LC_LOAD_WEAK_DYLIB, LC_REEXPORT_DYLIB, LC_LOAD_UPWARD_DYLIB, and
 * LC_LAZY_LOAD_DYLIB, etc. load commands in the order they appear in the
 * headers.   The library ordinals start from 1.
 * For a dynamic library that is built as a two-level namespace image the
 * undefined references from module defined in another use the same nlist struct
 * an in that case SELF_LIBRARY_ORDINAL is used as the library ordinal.  For
 * defined symbols in all images they also must have the library ordinal set to
 * SELF_LIBRARY_ORDINAL.  The EXECUTABLE_ORDINAL refers to the executable
 * image for references from plugins that refer to the executable that loads
 * them.
 *
 * The DYNAMIC_LOOKUP_ORDINAL is for undefined symbols in a two-level namespace
 * image that are looked up by the dynamic linker with flat namespace semantics.
 * This ordinal was added as a feature in Mac OS X 10.3 by reducing the
 * value of MAX_LIBRARY_ORDINAL by one.  So it is legal for existing binaries
 * or binaries built with older tools to have 0xfe (254) dynamic libraries.  In
 * this case the ordinal value 0xfe (254) must be treated as a library ordinal
 * for compatibility.
 */
#define GET_LIBRARY_ORDINAL(n_desc) (((n_desc) >> 8) & 0xff)
#define SET_LIBRARY_ORDINAL(n_desc,ordinal) \
	(n_desc) = (((n_desc) & 0x00ff) | (((ordinal) & 0xff) << 8))
#define SELF_LIBRARY_ORDINAL 0x0
#define MAX_LIBRARY_ORDINAL 0xfd
#define DYNAMIC_LOOKUP_ORDINAL 0xfe
#define EXECUTABLE_ORDINAL 0xff

/*
 * The bit 0x0020 of the n_desc field is used for two non-overlapping purposes
 * and has two different symbolic names, N_NO_DEAD_STRIP and N_DESC_DISCARDED.
 */

/*
 * The N_NO_DEAD_STRIP bit of the n_desc field only ever appears in a
 * relocatable .o file (MH_OBJECT filetype). And is used to indicate to the
 * static link editor it is never to dead strip the symbol.
 */
#define N_NO_DEAD_STRIP 0x0020 /* symbol is not to be dead stripped */

/*
 * The N_DESC_DISCARDED bit of the n_desc field never appears in linked image.
 * But is used in very rare cases by the dynamic link editor to mark an in
 * memory symbol as discared and longer used for linking.
 */
#define N_DESC_DISCARDED 0x0020	/* symbol is discarded */

/*
 * The N_WEAK_REF bit of the n_desc field indicates to the dynamic linker that
 * the undefined symbol is allowed to be missing and is to have the address of
 * zero when missing.
 */
#define N_WEAK_REF	0x0040 /* symbol is weak referenced */

/*
 * The N_WEAK_DEF bit of the n_desc field indicates to the static and dynamic
 * linkers that the symbol definition is weak, allowing a non-weak symbol to
 * also be used which causes the weak definition to be discared.  Currently this
 * is only supported for symbols in coalesed sections.
 */
#define N_WEAK_DEF	0x0080 /* coalesed symbol is a weak definition */

/*
 * The N_REF_TO_WEAK bit of the n_desc field indicates to the dynamic linker
 * that the undefined symbol should be resolved using flat namespace searching.
 */
#define	N_REF_TO_WEAK	0x0080 /* reference to a weak symbol */

/*
 * The N_ARM_THUMB_DEF bit of the n_desc field indicates that the symbol is
 * a defintion of a Thumb function.
 */
#define N_ARM_THUMB_DEF	0x0008 /* symbol is a Thumb function (ARM) */

/*
 * The N_SYMBOL_RESOLVER bit of the n_desc field indicates that the
 * that the function is actually a resolver function and should
 * be called to get the address of the real function to use.
 * This bit is only available in .o files (MH_OBJECT filetype)
 */
#define N_SYMBOL_RESOLVER  0x0100

/*
 * The N_ALT_ENTRY bit of the n_desc field indicates that the
 * symbol is pinned to the previous content.
 */
#define N_ALT_ENTRY 0x0200

/*
 * The N_COLD_FUNC bit of the n_desc field indicates that the symbol is used
 * infrequently and the linker should order it towards the end of the section.
 */
#define N_COLD_FUNC 0x0400

struct [[gnu::packed]] n_type_field {
	/// if any of these bits set, a symbolic debugging entry
	enum n_stab n_stab : 3;
	/// private external symbol bit
	bool n_pext : 1;
	/// mask for the type bits
	enum n_type n_type : 3;
	/// external symbol bit, set for external symbols
	bool n_ext : 1;
};
