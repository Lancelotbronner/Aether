import Foundation

// MARK: - Data Flow Analysis

class DataFlowAnalyzer {

    struct DataFlowInfo {
        var definitions: [UInt64: Set<String>]  // Address -> registers defined
        var uses: [UInt64: Set<String>]         // Address -> registers used
        var liveIn: [UInt64: Set<String>]       // Live registers at entry
        var liveOut: [UInt64: Set<String>]      // Live registers at exit
    }

    /// Perform data flow analysis on a function
    func analyze(function: Function, instructions: [Instruction], architecture: Architecture) -> DataFlowInfo {
        var info = DataFlowInfo(
            definitions: [:],
            uses: [:],
            liveIn: [:],
            liveOut: [:]
        )

        // Build def-use chains
        for insn in instructions {
            let regsRead = extractReads(insn, architecture: architecture)
            let regsWrite = extractWrites(insn, architecture: architecture)

            info.uses[insn.address] = Set(regsRead)
            info.definitions[insn.address] = Set(regsWrite)
        }

        // Compute liveness (simplified backward analysis)
        var changed = true
        while changed {
            changed = false

            for block in function.basicBlocks.reversed() {
                var liveOut = Set<String>()

                // Union of live-in of all successors
                for succ in block.successors {
                    if let succLiveIn = info.liveIn[succ] {
                        liveOut.formUnion(succLiveIn)
                    }
                }

                let oldLiveOut = info.liveOut[block.startAddress] ?? Set()
                if liveOut != oldLiveOut {
                    info.liveOut[block.startAddress] = liveOut
                    changed = true
                }

                // live_in = use ∪ (live_out - def)
                var liveIn = liveOut
                for insn in block.instructions.reversed() {
                    if let defs = info.definitions[insn.address] {
                        liveIn.subtract(defs)
                    }
                    if let uses = info.uses[insn.address] {
                        liveIn.formUnion(uses)
                    }
                }

                let oldLiveIn = info.liveIn[block.startAddress] ?? Set()
                if liveIn != oldLiveIn {
                    info.liveIn[block.startAddress] = liveIn
                    changed = true
                }
            }
        }

        return info
    }

    private func extractReads(_ insn: Instruction, architecture: Architecture) -> [String] {
        var regs: [String] = []
        let operands = insn.operands.lowercased()

        for reg in architecture.generalPurposeRegisters {
            if operands.contains(reg.lowercased()) {
                // Simple heuristic: if in memory operand or after comma, it's a read
                if operands.contains("[\(reg.lowercased())") ||
                   operands.split(separator: ",").dropFirst().joined().contains(reg.lowercased()) {
                    regs.append(reg)
                }
            }
        }

        return regs
    }

    private func extractWrites(_ insn: Instruction, architecture: Architecture) -> [String] {
        var regs: [String] = []
        let operands = insn.operands.lowercased()

        // First operand is usually destination
        if let firstOp = operands.split(separator: ",").first {
            let first = String(firstOp).trimmingCharacters(in: .whitespaces)
            if !first.contains("[") { // Not memory
                for reg in architecture.generalPurposeRegisters {
                    if first == reg.lowercased() {
                        regs.append(reg)
                        break
                    }
                }
            }
        }

        return regs
    }
}
