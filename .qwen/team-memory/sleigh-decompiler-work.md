---
name: sleigh-decompiler-work
description: User is working on Ghidra's Sleigh decompiler — specifically the decision-tree resolution mechanism in the Sleigh .sla instruction format
type: project
category: project_introduction
keywords:
  - Sleigh decompiler
  - decision tree
  - .sla format
  - SubtableSymbol
  - DecisionNode
  - slghsymbol.cc
---

The user is actively working on Ghidra's Sleigh decompiler (`Ghidra/Features/Decompiler/src/decompile/cpp`), with a current focus on how the Sleigh `.sla` instruction format encodes and resolves **decision trees** (`DecisionNode`) that select a constructor for an instruction address.

**Why:** Sleigh patterns cannot be matched by a single bit-scan because constructors overlap and are not nested; the decision tree is the prefix-free decision procedure that guarantees exactly one constructor per address. Understanding this mechanism is what the user is currently investigating.

**How to apply:** When suggesting changes to Sleigh parsing/disassembly, frame them in terms of the two phases — compile-time tree construction (`DecisionNode::split`, `chooseOptimalField`, `consistentValues`) and runtime walking (`DecisionNode::resolve`, driven by `Sleigh::resolve` in `sleigh.cc`). Note that the sleigh *compiler* C code is generated from `slghparse.y` at build time, so it is not present in the source tree.