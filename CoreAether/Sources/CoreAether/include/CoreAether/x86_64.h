//
//  x86_64.h
//  CoreAether
//
//  Created by Christophe Bronner on 2026-06-28.
//

#pragma once

#include <stdint.h>

typedef __uint128_t uint128_t;

struct [[gnu::packed]] x86_64_register {

	// General Purpose Registers

	union {
		struct {
			[[gnu::aligned(8)]] uint64_t RAX, RCX, RDX, RBX, RSP, RBP, RSI, RDI;
		};
		struct {
			[[gnu::aligned(8)]] uint32_t EAX, ECX, EDX, EBX, ESP, EBP, ESI, EDI;
		};
		struct {
			[[gnu::aligned(8)]] uint16_t AX, CX, DX, BX, SP, BP, SI, DI;
		};
		struct {
			struct [[gnu::aligned(8)]] { uint8_t AL, AH; };
			struct [[gnu::aligned(8)]] { uint8_t CL, CH; };
			struct [[gnu::aligned(8)]] { uint8_t DL, DH; };
			struct [[gnu::aligned(8)]] { uint8_t BL, BH; };
			[[gnu::aligned(8)]] uint8_t SPL, BPL, SIL, DIL;
		};
	};
	union {
		struct {
			[[gnu::aligned(8)]] uint64_t R8, R9, R10, R11, R12, R13, R14, R15;
		};
		struct {
			[[gnu::aligned(8)]] uint64_t R8D, R9D, R10D, R11D, R12D, R13D, R14D, R15D;
		};
		struct {
			[[gnu::aligned(8)]] uint64_t R8W, R9W, R10W, R11W, R12W, R13W, R14W, R15W;
		};
		struct {
			[[gnu::aligned(8)]] uint64_t R8B, R9B, R10B, R11B, R12B, R13B, R14B, R15B;
		};
	};

	// Segment Registers

	uint16_t RS, CS, SS, DS, FS, GS;
	uint64_t FS_OFFSET, GS_OFFSET;

	// Flags & Program Counter

	uint8_t CF, F1, PD, F3, AF, F5, ZF, SF, TF, IF, DF, OF, IOPL, NT, F15, RF, VM, AC, VIF, VIP, ID;
	union {
		struct {
			[[gnu::aligned(8)]] uint64_t rflags, RIP;
		};
		struct {
			[[gnu::aligned(8)]] uint32_t eflags, EIP;
		};
		struct {
			[[gnu::aligned(8)]] uint16_t flags, IP;
		};
	};

	// Processor State Register

	// Currently only XFEATURE_ENABLED_MASK=XCR0 is defined
	uint64_t XCR0;

	// Memory Protection Extensions (MPX)

	uint64_t BNDCFGS, BNDCFGU, BNDSTATUS;
	union {
		struct {
			uint128_t BND0, BND1, BND2, BND3;
			uint64_t BND0_LB, BND0_UB, BND1_LB, BND1_UB, BND2_LB, BND2_UB, BND3_LB, BND3_UB;
		};
	};

	// Control Flow Extensions

	uint64_t SSP, IA32_PL2_SSP, IA32_PL1_SSP, IA32_PL0_SSP;
	uint8_t C0, C1, C2, C3;
	uint32_t MXCSR;
	uint16_t FPUControlWord, FPUStatusWord, FPUTagWord, FPULastInstructionOpcode;
	uint64_t FPUDataPointer, FPUInstructionPointer;
	uint16_t FPUPointerSelector, FPUDataSelector;

	// Floating point registers

	// as they are in 32-bit protected mode
	uint64_t ST0, ST1, ST2, ST3, ST4, ST5, ST6, ST7;
	// NOTE: The upper 16-bits of the x87 ST registers go unused in MMX.
	// These upper 16-bits should be set to all ones by any MMX instruction, which correspond to the floating-point representation of NaNs or infinities.
	// Although not currently modeled, the 2-byte ST0h..ST7h registers are provided for that purpose.

	// MM registers

	/*
	 define register offset=0x1100 size=8   [ MM0 _ MM1 _ MM2 _ MM3 _ MM4 _ MM5 _ MM6 _ MM7 _ ];
	 define register offset=0x1100 size=4   [
	   MM0_Da MM0_Db _ _
	   MM1_Da MM1_Db _ _
	   MM2_Da MM2_Db _ _
	   MM3_Da MM3_Db _ _
	   MM4_Da MM4_Db _ _
	   MM5_Da MM5_Db _ _
	   MM6_Da MM6_Db _ _
	   MM7_Da MM7_Db _ _
	 ];
	 define register offset=0x1100 size=2   [
	   MM0_Wa MM0_Wb MM0_Wc MM0_Wd ST0h _ _ _
	   MM1_Wa MM1_Wb MM1_Wc MM1_Wd ST1h _ _ _
	   MM2_Wa MM2_Wb MM2_Wc MM2_Wd ST2h _ _ _
	   MM3_Wa MM3_Wb MM3_Wc MM3_Wd ST3h _ _ _
	   MM4_Wa MM4_Wb MM4_Wc MM4_Wd ST4h _ _ _
	   MM5_Wa MM5_Wb MM5_Wc MM5_Wd ST5h _ _ _
	   MM6_Wa MM6_Wb MM6_Wc MM6_Wd ST6h _ _ _
	   MM7_Wa MM7_Wb MM7_Wc MM7_Wd ST7h _ _ _
	 ];
	 define register offset=0x1100 size=1   [
	   MM0_Ba MM0_Bb MM0_Bc MM0_Bd MM0_Be MM0_Bf MM0_Bg MM0_Bh _ _ _ _ _ _ _ _
	   MM1_Ba MM1_Bb MM1_Bc MM1_Bd MM1_Be MM1_Bf MM1_Bg MM1_Bh _ _ _ _ _ _ _ _
	   MM2_Ba MM2_Bb MM2_Bc MM2_Bd MM2_Be MM2_Bf MM2_Bg MM2_Bh _ _ _ _ _ _ _ _
	   MM3_Ba MM3_Bb MM3_Bc MM3_Bd MM3_Be MM3_Bf MM3_Bg MM3_Bh _ _ _ _ _ _ _ _
	   MM4_Ba MM4_Bb MM4_Bc MM4_Bd MM4_Be MM4_Bf MM4_Bg MM4_Bh _ _ _ _ _ _ _ _
	   MM5_Ba MM5_Bb MM5_Bc MM5_Bd MM5_Be MM5_Bf MM5_Bg MM5_Bh _ _ _ _ _ _ _ _
	   MM6_Ba MM6_Bb MM6_Bc MM6_Bd MM6_Be MM6_Bf MM6_Bg MM6_Bh _ _ _ _ _ _ _ _
	   MM7_Ba MM7_Bb MM7_Bc MM7_Bd MM7_Be MM7_Bf MM7_Bg MM7_Bh _ _ _ _ _ _ _ _
	 ];


	 define register offset=0x1180 size=16  [ xmmTmp1 xmmTmp2 ];
	 define register offset=0x1180 size=8   [
	   xmmTmp1_Qa  xmmTmp1_Qb
	   xmmTmp2_Qa  xmmTmp2_Qb
	 ];
	 define register offset=0x1180 size=4   [
	   xmmTmp1_Da  xmmTmp1_Db  xmmTmp1_Dc  xmmTmp1_Dd
	   xmmTmp2_Da  xmmTmp2_Db  xmmTmp2_Dc  xmmTmp2_Dd
	 ];
	 */

	//MARK: - YMM Registers

	// YMM0 - YMM7    - available in 32 bit mode
	// YMM0 - YMM15   - available in 64 bit mode

	/*
	 # YMMx_H is the formal name for the high double quadword of the YMMx register, XMMx is the overlay in the XMM register set
	 define register offset=0x1200 size=16  [
		 XMM0 YMM0_H	_	_
		 XMM1 YMM1_H	_	_
		 XMM2 YMM2_H	_	_
		 XMM3 YMM3_H	_	_
		 XMM4 YMM4_H	_	_
		 XMM5 YMM5_H	_	_
		 XMM6 YMM6_H	_	_
		 XMM7 YMM7_H	_	_
		 XMM8 YMM8_H	_	_
		 XMM9 YMM9_H	_	_
		 XMM10 YMM10_H	_	_
		 XMM11 YMM11_H	_	_
		 XMM12 YMM12_H	_	_
		 XMM13 YMM13_H	_	_
		 XMM14 YMM14_H	_	_
		 XMM15 YMM15_H	_	_
		 XMM16 YMM16_H	_	_
		 XMM17 YMM17_H	_	_
		 XMM18 YMM18_H	_	_
		 XMM19 YMM19_H	_	_
		 XMM20 YMM20_H	_	_
		 XMM21 YMM21_H	_	_
		 XMM22 YMM22_H	_	_
		 XMM23 YMM23_H	_	_
		 XMM24 YMM24_H	_	_
		 XMM25 YMM25_H	_	_
		 XMM26 YMM26_H	_	_
		 XMM27 YMM27_H	_	_
		 XMM28 YMM28_H	_	_
		 XMM29 YMM29_H	_	_
		 XMM30 YMM30_H	_	_
		 XMM31 YMM31_H	_	_

	 ];

	 define register offset=0x1200 size=8   [
		 XMM0_Qa  XMM0_Qb  _ _ _ _ _ _
		 XMM1_Qa  XMM1_Qb  _ _ _ _ _ _
		 XMM2_Qa  XMM2_Qb  _ _ _ _ _ _
		 XMM3_Qa  XMM3_Qb  _ _ _ _ _ _
		 XMM4_Qa  XMM4_Qb  _ _ _ _ _ _
		 XMM5_Qa  XMM5_Qb  _ _ _ _ _ _
		 XMM6_Qa  XMM6_Qb  _ _ _ _ _ _
		 XMM7_Qa  XMM7_Qb  _ _ _ _ _ _
		 XMM8_Qa  XMM8_Qb  _ _ _ _ _ _
		 XMM9_Qa  XMM9_Qb  _ _ _ _ _ _
		 XMM10_Qa XMM10_Qb _ _ _ _ _ _
		 XMM11_Qa XMM11_Qb _ _ _ _ _ _
		 XMM12_Qa XMM12_Qb _ _ _ _ _ _
		 XMM13_Qa XMM13_Qb _ _ _ _ _ _
		 XMM14_Qa XMM14_Qb _ _ _ _ _ _
		 XMM15_Qa XMM15_Qb _ _ _ _ _ _
		 XMM16_Qa XMM16_Qb _ _ _ _ _ _
		 XMM17_Qa XMM17_Qb _ _ _ _ _ _
		 XMM18_Qa XMM18_Qb _ _ _ _ _ _
		 XMM19_Qa XMM19_Qb _ _ _ _ _ _
		 XMM20_Qa XMM20_Qb _ _ _ _ _ _
		 XMM21_Qa XMM21_Qb _ _ _ _ _ _
		 XMM22_Qa XMM22_Qb _ _ _ _ _ _
		 XMM23_Qa XMM23_Qb _ _ _ _ _ _
		 XMM24_Qa XMM24_Qb _ _ _ _ _ _
		 XMM25_Qa XMM25_Qb _ _ _ _ _ _
		 XMM26_Qa XMM26_Qb _ _ _ _ _ _
		 XMM27_Qa XMM27_Qb _ _ _ _ _ _
		 XMM28_Qa XMM28_Qb _ _ _ _ _ _
		 XMM29_Qa XMM29_Qb _ _ _ _ _ _
		 XMM30_Qa XMM30_Qb _ _ _ _ _ _
		 XMM31_Qa XMM31_Qb _ _ _ _ _ _
	 ];
	 define register offset=0x1200 size=4   [
		 XMM0_Da  XMM0_Db  XMM0_Dc  XMM0_Dd  _ _ _ _ _ _ _ _ _ _ _ _
		 XMM1_Da  XMM1_Db  XMM1_Dc  XMM1_Dd  _ _ _ _ _ _ _ _ _ _ _ _
		 XMM2_Da  XMM2_Db  XMM2_Dc  XMM2_Dd  _ _ _ _ _ _ _ _ _ _ _ _
		 XMM3_Da  XMM3_Db  XMM3_Dc  XMM3_Dd  _ _ _ _ _ _ _ _ _ _ _ _
		 XMM4_Da  XMM4_Db  XMM4_Dc  XMM4_Dd  _ _ _ _ _ _ _ _ _ _ _ _
		 XMM5_Da  XMM5_Db  XMM5_Dc  XMM5_Dd  _ _ _ _ _ _ _ _ _ _ _ _
		 XMM6_Da  XMM6_Db  XMM6_Dc  XMM6_Dd  _ _ _ _ _ _ _ _ _ _ _ _
		 XMM7_Da  XMM7_Db  XMM7_Dc  XMM7_Dd  _ _ _ _ _ _ _ _ _ _ _ _
		 XMM8_Da  XMM8_Db  XMM8_Dc  XMM8_Dd  _ _ _ _ _ _ _ _ _ _ _ _
		 XMM9_Da  XMM9_Db  XMM9_Dc  XMM9_Dd  _ _ _ _ _ _ _ _ _ _ _ _
		 XMM10_Da XMM10_Db XMM10_Dc XMM10_Dd _ _ _ _ _ _ _ _ _ _ _ _
		 XMM11_Da XMM11_Db XMM11_Dc XMM11_Dd _ _ _ _ _ _ _ _ _ _ _ _
		 XMM12_Da XMM12_Db XMM12_Dc XMM12_Dd _ _ _ _ _ _ _ _ _ _ _ _
		 XMM13_Da XMM13_Db XMM13_Dc XMM13_Dd _ _ _ _ _ _ _ _ _ _ _ _
		 XMM14_Da XMM14_Db XMM14_Dc XMM14_Dd _ _ _ _ _ _ _ _ _ _ _ _
		 XMM15_Da XMM15_Db XMM15_Dc XMM15_Dd _ _ _ _ _ _ _ _ _ _ _ _
		 XMM16_Da XMM16_Db XMM16_Dc XMM16_Dd _ _ _ _ _ _ _ _ _ _ _ _
		 XMM17_Da XMM17_Db XMM17_Dc XMM17_Dd _ _ _ _ _ _ _ _ _ _ _ _
		 XMM18_Da XMM18_Db XMM18_Dc XMM18_Dd _ _ _ _ _ _ _ _ _ _ _ _
		 XMM19_Da XMM19_Db XMM19_Dc XMM19_Dd _ _ _ _ _ _ _ _ _ _ _ _
		 XMM20_Da XMM20_Db XMM20_Dc XMM20_Dd _ _ _ _ _ _ _ _ _ _ _ _
		 XMM21_Da XMM21_Db XMM21_Dc XMM21_Dd _ _ _ _ _ _ _ _ _ _ _ _
		 XMM22_Da XMM22_Db XMM22_Dc XMM22_Dd _ _ _ _ _ _ _ _ _ _ _ _
		 XMM23_Da XMM23_Db XMM23_Dc XMM23_Dd _ _ _ _ _ _ _ _ _ _ _ _
		 XMM24_Da XMM24_Db XMM24_Dc XMM24_Dd _ _ _ _ _ _ _ _ _ _ _ _
		 XMM25_Da XMM25_Db XMM25_Dc XMM25_Dd _ _ _ _ _ _ _ _ _ _ _ _
		 XMM26_Da XMM26_Db XMM26_Dc XMM26_Dd _ _ _ _ _ _ _ _ _ _ _ _
		 XMM27_Da XMM27_Db XMM27_Dc XMM27_Dd _ _ _ _ _ _ _ _ _ _ _ _
		 XMM28_Da XMM28_Db XMM28_Dc XMM28_Dd _ _ _ _ _ _ _ _ _ _ _ _
		 XMM29_Da XMM29_Db XMM29_Dc XMM29_Dd _ _ _ _ _ _ _ _ _ _ _ _
		 XMM30_Da XMM30_Db XMM30_Dc XMM30_Dd _ _ _ _ _ _ _ _ _ _ _ _
		 XMM31_Da XMM31_Db XMM31_Dc XMM31_Dd _ _ _ _ _ _ _ _ _ _ _ _
	 ];
	 define register offset=0x1200 size=2   [
		 XMM0_Wa  XMM0_Wb  XMM0_Wc  XMM0_Wd  XMM0_We  XMM0_Wf  XMM0_Wg  XMM0_Wh  _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
		 XMM1_Wa  XMM1_Wb  XMM1_Wc  XMM1_Wd  XMM1_We  XMM1_Wf  XMM1_Wg  XMM1_Wh  _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
		 XMM2_Wa  XMM2_Wb  XMM2_Wc  XMM2_Wd  XMM2_We  XMM2_Wf  XMM2_Wg  XMM2_Wh  _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
		 XMM3_Wa  XMM3_Wb  XMM3_Wc  XMM3_Wd  XMM3_We  XMM3_Wf  XMM3_Wg  XMM3_Wh  _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
		 XMM4_Wa  XMM4_Wb  XMM4_Wc  XMM4_Wd  XMM4_We  XMM4_Wf  XMM4_Wg  XMM4_Wh  _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
		 XMM5_Wa  XMM5_Wb  XMM5_Wc  XMM5_Wd  XMM5_We  XMM5_Wf  XMM5_Wg  XMM5_Wh  _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
		 XMM6_Wa  XMM6_Wb  XMM6_Wc  XMM6_Wd  XMM6_We  XMM6_Wf  XMM6_Wg  XMM6_Wh  _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
		 XMM7_Wa  XMM7_Wb  XMM7_Wc  XMM7_Wd  XMM7_We  XMM7_Wf  XMM7_Wg  XMM7_Wh  _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
		 XMM8_Wa  XMM8_Wb  XMM8_Wc  XMM8_Wd  XMM8_We  XMM8_Wf  XMM8_Wg  XMM8_Wh  _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
		 XMM9_Wa  XMM9_Wb  XMM9_Wc  XMM9_Wd  XMM9_We  XMM9_Wf  XMM9_Wg  XMM9_Wh  _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
		 XMM10_Wa XMM10_Wb XMM10_Wc XMM10_Wd XMM10_We XMM10_Wf XMM10_Wg XMM10_Wh _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
		 XMM11_Wa XMM11_Wb XMM11_Wc XMM11_Wd XMM11_We XMM11_Wf XMM11_Wg XMM11_Wh _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
		 XMM12_Wa XMM12_Wb XMM12_Wc XMM12_Wd XMM12_We XMM12_Wf XMM12_Wg XMM12_Wh _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
		 XMM13_Wa XMM13_Wb XMM13_Wc XMM13_Wd XMM13_We XMM13_Wf XMM13_Wg XMM13_Wh _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
		 XMM14_Wa XMM14_Wb XMM14_Wc XMM14_Wd XMM14_We XMM14_Wf XMM14_Wg XMM14_Wh _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
		 XMM15_Wa XMM15_Wb XMM15_Wc XMM15_Wd XMM15_We XMM15_Wf XMM15_Wg XMM15_Wh _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
		 XMM16_Wa XMM16_Wb XMM16_Wc XMM16_Wd XMM16_We XMM16_Wf XMM16_Wg XMM16_Wh _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
		 XMM17_Wa XMM17_Wb XMM17_Wc XMM17_Wd XMM17_We XMM17_Wf XMM17_Wg XMM17_Wh _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
		 XMM18_Wa XMM18_Wb XMM18_Wc XMM18_Wd XMM18_We XMM18_Wf XMM18_Wg XMM18_Wh _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
		 XMM19_Wa XMM19_Wb XMM19_Wc XMM19_Wd XMM19_We XMM19_Wf XMM19_Wg XMM19_Wh _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
		 XMM20_Wa XMM20_Wb XMM20_Wc XMM20_Wd XMM20_We XMM20_Wf XMM20_Wg XMM20_Wh _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
		 XMM21_Wa XMM21_Wb XMM21_Wc XMM21_Wd XMM21_We XMM21_Wf XMM21_Wg XMM21_Wh _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
		 XMM22_Wa XMM22_Wb XMM22_Wc XMM22_Wd XMM22_We XMM22_Wf XMM22_Wg XMM22_Wh _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
		 XMM23_Wa XMM23_Wb XMM23_Wc XMM23_Wd XMM23_We XMM23_Wf XMM23_Wg XMM23_Wh _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
		 XMM24_Wa XMM24_Wb XMM24_Wc XMM24_Wd XMM24_We XMM24_Wf XMM24_Wg XMM24_Wh _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
		 XMM25_Wa XMM25_Wb XMM25_Wc XMM25_Wd XMM25_We XMM25_Wf XMM25_Wg XMM25_Wh _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
		 XMM26_Wa XMM26_Wb XMM26_Wc XMM26_Wd XMM26_We XMM26_Wf XMM26_Wg XMM26_Wh _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
		 XMM27_Wa XMM27_Wb XMM27_Wc XMM27_Wd XMM27_We XMM27_Wf XMM27_Wg XMM27_Wh _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
		 XMM28_Wa XMM28_Wb XMM28_Wc XMM28_Wd XMM28_We XMM28_Wf XMM28_Wg XMM28_Wh _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
		 XMM29_Wa XMM29_Wb XMM29_Wc XMM29_Wd XMM29_We XMM29_Wf XMM29_Wg XMM29_Wh _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
		 XMM30_Wa XMM30_Wb XMM30_Wc XMM30_Wd XMM30_We XMM30_Wf XMM30_Wg XMM30_Wh _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
		 XMM31_Wa XMM31_Wb XMM31_Wc XMM31_Wd XMM31_We XMM31_Wf XMM31_Wg XMM31_Wh _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
	 ];
	 define register offset=0x1200 size=1   [
		 XMM0_Ba  XMM0_Bb  XMM0_Bc  XMM0_Bd  XMM0_Be  XMM0_Bf  XMM0_Bg  XMM0_Bh  XMM0_Bi  XMM0_Bj  XMM0_Bk  XMM0_Bl  XMM0_Bm  XMM0_Bn  XMM0_Bo  XMM0_Bp  _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
		 XMM1_Ba  XMM1_Bb  XMM1_Bc  XMM1_Bd  XMM1_Be  XMM1_Bf  XMM1_Bg  XMM1_Bh  XMM1_Bi  XMM1_Bj  XMM1_Bk  XMM1_Bl  XMM1_Bm  XMM1_Bn  XMM1_Bo  XMM1_Bp  _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
		 XMM2_Ba  XMM2_Bb  XMM2_Bc  XMM2_Bd  XMM2_Be  XMM2_Bf  XMM2_Bg  XMM2_Bh  XMM2_Bi  XMM2_Bj  XMM2_Bk  XMM2_Bl  XMM2_Bm  XMM2_Bn  XMM2_Bo  XMM2_Bp  _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
		 XMM3_Ba  XMM3_Bb  XMM3_Bc  XMM3_Bd  XMM3_Be  XMM3_Bf  XMM3_Bg  XMM3_Bh  XMM3_Bi  XMM3_Bj  XMM3_Bk  XMM3_Bl  XMM3_Bm  XMM3_Bn  XMM3_Bo  XMM3_Bp  _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
		 XMM4_Ba  XMM4_Bb  XMM4_Bc  XMM4_Bd  XMM4_Be  XMM4_Bf  XMM4_Bg  XMM4_Bh  XMM4_Bi  XMM4_Bj  XMM4_Bk  XMM4_Bl  XMM4_Bm  XMM4_Bn  XMM4_Bo  XMM4_Bp  _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
		 XMM5_Ba  XMM5_Bb  XMM5_Bc  XMM5_Bd  XMM5_Be  XMM5_Bf  XMM5_Bg  XMM5_Bh  XMM5_Bi  XMM5_Bj  XMM5_Bk  XMM5_Bl  XMM5_Bm  XMM5_Bn  XMM5_Bo  XMM5_Bp  _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
		 XMM6_Ba  XMM6_Bb  XMM6_Bc  XMM6_Bd  XMM6_Be  XMM6_Bf  XMM6_Bg  XMM6_Bh  XMM6_Bi  XMM6_Bj  XMM6_Bk  XMM6_Bl  XMM6_Bm  XMM6_Bn  XMM6_Bo  XMM6_Bp  _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
		 XMM7_Ba  XMM7_Bb  XMM7_Bc  XMM7_Bd  XMM7_Be  XMM7_Bf  XMM7_Bg  XMM7_Bh  XMM7_Bi  XMM7_Bj  XMM7_Bk  XMM7_Bl  XMM7_Bm  XMM7_Bn  XMM7_Bo  XMM7_Bp  _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
		 XMM8_Ba  XMM8_Bb  XMM8_Bc  XMM8_Bd  XMM8_Be  XMM8_Bf  XMM8_Bg  XMM8_Bh  XMM8_Bi  XMM8_Bj  XMM8_Bk  XMM8_Bl  XMM8_Bm  XMM8_Bn  XMM8_Bo  XMM8_Bp  _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
		 XMM9_Ba  XMM9_Bb  XMM9_Bc  XMM9_Bd  XMM9_Be  XMM9_Bf  XMM9_Bg  XMM9_Bh  XMM9_Bi  XMM9_Bj  XMM9_Bk  XMM9_Bl  XMM9_Bm  XMM9_Bn  XMM9_Bo  XMM9_Bp  _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
		 XMM10_Ba XMM10_Bb XMM10_Bc XMM10_Bd XMM10_Be XMM10_Bf XMM10_Bg XMM10_Bh XMM10_Bi XMM10_Bj XMM10_Bk XMM10_Bl XMM10_Bm XMM10_Bn XMM10_Bo XMM10_Bp _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
		 XMM11_Ba XMM11_Bb XMM11_Bc XMM11_Bd XMM11_Be XMM11_Bf XMM11_Bg XMM11_Bh XMM11_Bi XMM11_Bj XMM11_Bk XMM11_Bl XMM11_Bm XMM11_Bn XMM11_Bo XMM11_Bp _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
		 XMM12_Ba XMM12_Bb XMM12_Bc XMM12_Bd XMM12_Be XMM12_Bf XMM12_Bg XMM12_Bh XMM12_Bi XMM12_Bj XMM12_Bk XMM12_Bl XMM12_Bm XMM12_Bn XMM12_Bo XMM12_Bp _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
		 XMM13_Ba XMM13_Bb XMM13_Bc XMM13_Bd XMM13_Be XMM13_Bf XMM13_Bg XMM13_Bh XMM13_Bi XMM13_Bj XMM13_Bk XMM13_Bl XMM13_Bm XMM13_Bn XMM13_Bo XMM13_Bp _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
		 XMM14_Ba XMM14_Bb XMM14_Bc XMM14_Bd XMM14_Be XMM14_Bf XMM14_Bg XMM14_Bh XMM14_Bi XMM14_Bj XMM14_Bk XMM14_Bl XMM14_Bm XMM14_Bn XMM14_Bo XMM14_Bp _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
		 XMM15_Ba XMM15_Bb XMM15_Bc XMM15_Bd XMM15_Be XMM15_Bf XMM15_Bg XMM15_Bh XMM15_Bi XMM15_Bj XMM15_Bk XMM15_Bl XMM15_Bm XMM15_Bn XMM15_Bo XMM15_Bp _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
		 XMM16_Ba XMM16_Bb XMM16_Bc XMM16_Bd XMM16_Be XMM16_Bf XMM16_Bg XMM16_Bh XMM16_Bi XMM16_Bj XMM16_Bk XMM16_Bl XMM16_Bm XMM16_Bn XMM16_Bo XMM16_Bp _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
		 XMM17_Ba XMM17_Bb XMM17_Bc XMM17_Bd XMM17_Be XMM17_Bf XMM17_Bg XMM17_Bh XMM17_Bi XMM17_Bj XMM17_Bk XMM17_Bl XMM17_Bm XMM17_Bn XMM17_Bo XMM17_Bp _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
		 XMM18_Ba XMM18_Bb XMM18_Bc XMM18_Bd XMM18_Be XMM18_Bf XMM18_Bg XMM18_Bh XMM18_Bi XMM18_Bj XMM18_Bk XMM18_Bl XMM18_Bm XMM18_Bn XMM18_Bo XMM18_Bp _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
		 XMM19_Ba XMM19_Bb XMM19_Bc XMM19_Bd XMM19_Be XMM19_Bf XMM19_Bg XMM19_Bh XMM19_Bi XMM19_Bj XMM19_Bk XMM19_Bl XMM19_Bm XMM19_Bn XMM19_Bo XMM19_Bp _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
		 XMM20_Ba XMM20_Bb XMM20_Bc XMM20_Bd XMM20_Be XMM20_Bf XMM20_Bg XMM20_Bh XMM20_Bi XMM20_Bj XMM20_Bk XMM20_Bl XMM20_Bm XMM20_Bn XMM20_Bo XMM20_Bp _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
		 XMM21_Ba XMM21_Bb XMM21_Bc XMM21_Bd XMM21_Be XMM21_Bf XMM21_Bg XMM21_Bh XMM21_Bi XMM21_Bj XMM21_Bk XMM21_Bl XMM21_Bm XMM21_Bn XMM21_Bo XMM21_Bp _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
		 XMM22_Ba XMM22_Bb XMM22_Bc XMM22_Bd XMM22_Be XMM22_Bf XMM22_Bg XMM22_Bh XMM22_Bi XMM22_Bj XMM22_Bk XMM22_Bl XMM22_Bm XMM22_Bn XMM22_Bo XMM22_Bp _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
		 XMM23_Ba XMM23_Bb XMM23_Bc XMM23_Bd XMM23_Be XMM23_Bf XMM23_Bg XMM23_Bh XMM23_Bi XMM23_Bj XMM23_Bk XMM23_Bl XMM23_Bm XMM23_Bn XMM23_Bo XMM23_Bp _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
		 XMM24_Ba XMM24_Bb XMM24_Bc XMM24_Bd XMM24_Be XMM24_Bf XMM24_Bg XMM24_Bh XMM24_Bi XMM24_Bj XMM24_Bk XMM24_Bl XMM24_Bm XMM24_Bn XMM24_Bo XMM24_Bp _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
		 XMM25_Ba XMM25_Bb XMM25_Bc XMM25_Bd XMM25_Be XMM25_Bf XMM25_Bg XMM25_Bh XMM25_Bi XMM25_Bj XMM25_Bk XMM25_Bl XMM25_Bm XMM25_Bn XMM25_Bo XMM25_Bp _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
		 XMM26_Ba XMM26_Bb XMM26_Bc XMM26_Bd XMM26_Be XMM26_Bf XMM26_Bg XMM26_Bh XMM26_Bi XMM26_Bj XMM26_Bk XMM26_Bl XMM26_Bm XMM26_Bn XMM26_Bo XMM26_Bp _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
		 XMM27_Ba XMM27_Bb XMM27_Bc XMM27_Bd XMM27_Be XMM27_Bf XMM27_Bg XMM27_Bh XMM27_Bi XMM27_Bj XMM27_Bk XMM27_Bl XMM27_Bm XMM27_Bn XMM27_Bo XMM27_Bp _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
		 XMM28_Ba XMM28_Bb XMM28_Bc XMM28_Bd XMM28_Be XMM28_Bf XMM28_Bg XMM28_Bh XMM28_Bi XMM28_Bj XMM28_Bk XMM28_Bl XMM28_Bm XMM28_Bn XMM28_Bo XMM28_Bp _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
		 XMM29_Ba XMM29_Bb XMM29_Bc XMM29_Bd XMM29_Be XMM29_Bf XMM29_Bg XMM29_Bh XMM29_Bi XMM29_Bj XMM29_Bk XMM29_Bl XMM29_Bm XMM29_Bn XMM29_Bo XMM29_Bp _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
		 XMM30_Ba XMM30_Bb XMM30_Bc XMM30_Bd XMM30_Be XMM30_Bf XMM30_Bg XMM30_Bh XMM30_Bi XMM30_Bj XMM30_Bk XMM30_Bl XMM30_Bm XMM30_Bn XMM30_Bo XMM30_Bp _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
		 XMM31_Ba XMM31_Bb XMM31_Bc XMM31_Bd XMM31_Be XMM31_Bf XMM31_Bg XMM31_Bh XMM31_Bi XMM31_Bj XMM31_Bk XMM31_Bl XMM31_Bm XMM31_Bn XMM31_Bo XMM31_Bp _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
	 ];

	 define register offset=0x1200 size=32  [
		 YMM0	_	YMM1	_
		 YMM2	_	YMM3	_
		 YMM4	_	YMM5	_
		 YMM6	_	YMM7	_
		 YMM8	_	YMM9	_
		 YMM10	_	YMM11	_
		 YMM12	_	YMM13	_
		 YMM14	_	YMM15	_
		 YMM16	_	YMM17	_
		 YMM18	_	YMM19	_
		 YMM20	_	YMM21	_
		 YMM22	_	YMM23	_
		 YMM24	_	YMM25	_
		 YMM26	_	YMM27	_
		 YMM28	_	YMM29	_
		 YMM30	_	YMM31	_
	 ];

	 define register offset=0x1200 size=64  [
		 ZMM0	ZMM1
		 ZMM2	ZMM3
		 ZMM4	ZMM5
		 ZMM6	ZMM7
		 ZMM8	ZMM9
		 ZMM10	ZMM11
		 ZMM12	ZMM13
		 ZMM14	ZMM15
		 ZMM16	ZMM17
		 ZMM18	ZMM19
		 ZMM20	ZMM21
		 ZMM22	ZMM23
		 ZMM24	ZMM25
		 ZMM26	ZMM27
		 ZMM28	ZMM29
		 ZMM30	ZMM31
	 ];
	 */

	// AVX-512 opmask registers

	uint64_t K0, K1, K2, K3, K4, K5, K6, K7;

	// dummy registers for managing broadcast data for AVX512
	/*
	define register offset=2200 size=4 [ BCST4 ];
	define register offset=2200 size=8 [ BCST8 ];
	define register offset=2200 size=16 [ BCST16 ];
	define register offset=2200 size=32 [ BCST32 ];
	define register offset=2200 size=64 [ BCST64 ];

	define register offset=2300 size=16 [ XmmResult _ _ _ XmmMask ];
	define register offset=2300 size=32 [ YmmResult   _   YmmMask ];
	define register offset=2300 size=64 [ ZmmResult       ZmmMask ];
	 */

	//MARK: - Macros

	/*
	# These are only to be used with pre-REX (original 8086, 80386) and REX encoding.  Do not use with VEX encoding.
	# These are to be used to designate that the opcode sequence begins with one of these "mandatory" prefix values.
	# This allows the other prefixes to come before the mandatory value.
	# For example:    CRC32 r32, r16 -- 66  F2 OF 38 F1 C8

	@define PRE_NO		"mandover=0"
	@define PRE_NOFX	"(mandover=0 | prefix_66=1)"
	@define PRE_66		"prefix_66=1"
	@define PRE_F3		"prefix_f3=1"
	@define PRE_F2		"prefix_f2=1"
	*/

	//MARK: - Special Registers for Debugger

//	define register offset=0x2200 size=4   [ IDTR_Limit ];
//	define register offset=0x2200 size=12   [ IDTR   ];
//	define register offset=0x2204 size=8   [ IDTR_Address ];
//
//	define register offset=0x2220 size=4   [ GDTR_Limit ];
//	define register offset=0x2220 size=12   [ GDTR   ];
//	define register offset=0x2224 size=8   [ GDTR_Address ];
//
//	define register offset=0x2240 size=4   [ LDTR_Limit ];
//	define register offset=0x2240 size=14  [ LDTR   ];
//	define register offset=0x2244 size=8   [ LDTR_Address ];
//	define register offset=0x2248 size=2   [ LDTR_Attributes ];
//
//	define register offset=0x2260 size=4   [ TR_Limit ];
//	define register offset=0x2260 size=14  [ TR   ];
//	define register offset=0x2264 size=8   [ TR_Address ];
//	define register offset=0x2268 size=2   [ TR_Attributes ];
};

struct [[gnu::packed]] x86_64_context {
	// Start of Stored Context

	/// 0 for 32-bit emulation, 1 for 64-bit mode
	bool longMode : 1;
	/// =0  16-bit operands    =1  32-bit operands     =2 64-bit operands
	uint8_t opsize : 2;
	union [[gnu::packed]] {
		/// =0  16-bit addressing  =1  32-bit addressing   =2 64-bit addressing
		uint8_t addrsize : 2;
		/// =0  16/32 bit          =1  64-bit
		bool bit64 : 1;
	};
	union [[gnu::packed]] {
		/// 0=default 1=cs 2=ss 3=ds 4=es 5=fs 6=gs
		uint8_t segover : 3;
		/// high bit of segover will be set for ES, FS, GS
		bool highseg : 1;
	};

	// End of Stored Context

	union [[gnu::packed]] {
		///  0x66 0xf2 or 0xf3 overrides (for mandatory prefixes)
		uint8_t mandover : 3;
		struct [[gnu::packed]] {
			///  0xf2 REPNE prefi
			bool repneprefx : 1;
			///  0xf3 REP prefix
			bool repprefx : 1;
			///  This is not really a OPSIZE override, it means there is an real(read)/implied(vex) 66 byte
			bool prefix_66 : 1;
		};
		struct [[gnu::packed]] {
			///  0xf2 XACQUIRE prefix
			bool xacquireprefx : 1;
			///  0xf3 XRELEASE prefix
			bool xreleaseprefx : 1;
		};
		struct [[gnu::packed]] {
			///  This is not really a REPNE override, it means there is a real(read)/implied(vex) f2 byte
			bool prefix_f2 : 1;
			///  This is not really a REP override, it means there is an real(read)/implied(vex) f3 byte
			bool prefix_f3 : 1;
		};
	};

	union [[gnu::packed]] {
		/// REX.WRXB bits
		uint8_t rexWRXBprefix : 4;
		struct [[gnu::packed]] {
			///  REX.W bit prefix (opsize=2 when REX.W is set)
			bool rexWprefix : 1;
			///  REX.R bit prefix extend r
			bool rexRprefix : 1;
			///  REX.X bit prefix extend SIB index field to 4 bits
			bool rexXprefix : 1;
			///  REX.B bit prefix extend r/m, SIB base, Reg operand
			bool rexBprefix : 1;
			///  True if the Rex prefix is present - note, if present, `vex_mode` is not supported
			bool rexprefix : 1;
		};
	};

	//   rexWRXB bits can be re-used since they are incompatible.

	/*
	///  2 for evex instruction, 1 for vexMode, 0 for normal
	static let vexMode = contextreg.context(20...21)

	///  0 for 128, 1 for 256, 2 for 512 (also used for rounding control)
	static let evexL = contextreg.context(22...23)
	///  EVEX.L'
	static let evexLp = contextreg.context(22...22)
	///  0 for 128, 1 for 256
	static let vexL = contextreg.context(23...23)

	///  evex byte for matching ZmmReg
	static let evexV5_XmmReg = contextreg.context(24...28)
	///  evex byte for matching ZmmReg
	static let evexV5_YmmReg = contextreg.context(24...28)
	///  evex byte for matching ZmmReg
	static let evexV5_ZmmReg = contextreg.context(24...28)
	///  EVEX.V' combined with EVEX.vvvv
	static let evexV5 = contextreg.context(24...28)
	///  EVEX.V' bit prefix extends EVEX.vvvv (stored inverted)
	static let evexVp = contextreg.context(24...24)
	///  value of vex byte for matching
	static let vexVVVV = contextreg.context(25...28)
	///  value of vex byte for matching a normal 32 bit register
	static let vexVVVV_r32 = contextreg.context(25...28)
	///  value of vex byte for matching a normal 64 bit register
	static let vexVVVV_r64 = contextreg.context(25...28)
	///  value of vex byte for matching XmmReg
	static let vexVVVV_XmmReg = contextreg.context(25...28)
	///  value of vex byte for matching YmmReg
	static let vexVVVV_YmmReg = contextreg.context(25...28)
	///  value of vex byte for matching ZmmReg
	static let vexVVVV_ZmmReg = contextreg.context(25...28)

	static let vexHighV = contextreg.context(25...25)
	///  VEX.vvvv opmask
	static let evexVopmask = contextreg.context(26...28)

	///  3DNow suffix byte (overlaps un-modified vex context region)
	static let suffix3D = contextreg.context(22...29)

	///  0: initial/prefix phase, 1: primary instruction phase
	static let instrPhase = contextreg.context(30...30)

	///  0xf0 LOCK prefix
	static let lockprefx = contextreg.context(31...31)

	///  need to match for preceding bytes 1=0x0F, 2=0x0F 0x38, 3=0x0F 0x3A
	static let vexMMMMM = contextreg.context(32...36)

	///  EVEX.R' bit prefix extends r
	static let evexRp = contextreg.context(37...37)
	///  EVEX.b Broadcast
	static let evexB = contextreg.context(38...38)
	///  Opmask behavior 1 for zeroing-masking, 0 for merging-masking
	static let evexZ = contextreg.context(39...39)
	///  Opmask selector
	static let evexAAA = contextreg.context(40...42)
	///  Used for attaching Opmask registers
	static let evexOpmask = contextreg.context(40...42)
	///  Used for compressed Disp8*N, can range from 1 to 64
	static let evexD8Type = contextreg.context(43...43)
	///  Used for Disp8*N (see table 2-34 in 325462-sdm-vol-1-2abcd-3abcd-4.pdf)
	static let evexBType = contextreg.context(47...47)
	///  Used for Disp8*N (see table 2-35 in 325462-sdm-vol-1-2abcd-3abcd-4.pdf)
	static let evexTType = contextreg.context(44...47)
	static let evexDisp8 = contextreg.context(44...46)
	 */
};

union [[gnu::packed]] x86_64_opbyte {
	uint8_t byte;
	uint8_t low5 : 5;
	struct [[gnu::packed]] {
		bool byte_0 : 1;
		uint8_t : 3;
		uint8_t high4 : 4;
	};
	struct [[gnu::packed]] {
		uint8_t : 3;
		uint8_t high5 : 5;
	};
	struct [[gnu::packed]] {
		uint8_t : 4;
		bool byte_4 : 1;
	};
};

union [[gnu::packed]] x86_64_modrm {
	struct [[gnu::packed]] {
		uint8_t r_m : 3;
		uint8_t reg_opcode : 3;
		uint8_t mod : 2;
	};
	struct [[gnu::packed]] {
		uint8_t col : 3;
		bool page : 1;
		uint8_t row : 4;
	};
	struct [[gnu::packed]] {
		uint8_t cond : 4;
		uint8_t frow : 4;
	};
	struct [[gnu::packed]] {
		uint8_t r8 : 3;
		uint8_t reg8 : 3;
		uint8_t mmxmod : 2;
	};
	struct [[gnu::packed]] {
		uint8_t r16 : 3;
		uint8_t reg16 : 3;
		uint8_t xmmmod : 2;
	};
	struct [[gnu::packed]] {
		uint8_t r32 : 3;
		uint8_t reg32 : 3;
		bool vex_x : 1;
		bool vex_r : 1;
	};
	struct [[gnu::packed]] {
		uint8_t r64 : 3;
		uint8_t reg64 : 3;
		bool evex_lp : 1;
		bool evex_z : 1;
	};
	struct [[gnu::packed]] {
		uint8_t r16_x : 3;
		uint8_t reg16_x : 3;
	};
	struct [[gnu::packed]] {
		uint8_t r32_x : 3;
		uint8_t reg32_x : 3;
	};
	struct [[gnu::packed]] {
		uint8_t r64_x : 3;
		uint8_t reg64_x : 3;
	};
	struct [[gnu::packed]] {
		uint8_t freg : 3;
		bool fpage : 1;
		bool evex_b : 1;
		bool evex_l : 1;
	};
	struct [[gnu::packed]] {
		bool rexb : 1;
		bool rexx : 1;
		bool rexr : 1;
		bool rexw : 1;
		bool evex_rp : 1;
		bool reg_opcode_hb : 1;
		bool : 1;
		bool vex_w : 1;
	};
};

//	Sreg          = (3,5)
//	creg          = (3,5)
//	creg_x        = (3,5)
//	debugreg      = (3,5)
//	debugreg_x    = (3,5)
//	testreg       = (3,5)
//	mmxreg        = (3,5)
//	mmxreg1       = (3,5)
//	mmxreg2       = (0,2)
//	xmmreg        = (3,5)
//	ymmreg        = (3,5)
//	zmmreg        = (3,5)
//
//	xmmreg1       = (3,5)
//	ymmreg1       = (3,5)
//	zmmreg1       = (3,5)
//	xmmreg2       = (0,2)
//	ymmreg2       = (0,2)
//	zmmreg2       = (0,2)
//
//	xmmreg_x      = (3,5)
//	ymmreg_x      = (3,5)
//	zmmreg_x      = (3,5)
//	xmmreg1_x     = (3,5)
//	ymmreg1_x     = (3,5)
//	zmmreg1_x     = (3,5)
//	xmmreg1_r     = (3,5)
//	ymmreg1_r     = (3,5)
//	zmmreg1_r     = (3,5)
//	xmmreg1_rx    = (3,5)
//	ymmreg1_rx    = (3,5)
//	zmmreg1_rx    = (3,5)
//	xmmreg2_b     = (0,2)
//	ymmreg2_b     = (0,2)
//	zmmreg2_b     = (0,2)
//	xmmreg2_x     = (0,2)
//	ymmreg2_x     = (0,2)
//	zmmreg2_x     = (0,2)
//	xmmreg2_bx    = (0,2)
//	ymmreg2_bx    = (0,2)
//	zmmreg2_bx    = (0,2)
//
//
//	vex_pp        = (0,1)
//	vex_l         = (2,2)
//	vex_vvvv      = (3,6)

//	vex_b         = (5,5)
//	vex_mmmmm     = (0,4)
//
//	evex_res      = (3,3)
//	evex_res2     = (2,2)
//	evex_mmm      = (0,2)
//


//	evex_vp       = (3,3)
//	evex_aaa      = (0,2)
//	opmaskreg     = (3,5)
//	opmaskrm      = (0,2)
//
//	bnd1          = (3,5)
//	bnd1_lb       = (3,5)
//	bnd1_ub       = (3,5)
//	bnd2          = (0,2)
//	bnd2_lb       = (0,2)
//	bnd2_ub       = (0,2)
