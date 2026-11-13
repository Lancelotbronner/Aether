import AetherKit
import ArgumentParser

extension AnnotationKind: @retroactive ExpressibleByArgument {}
extension SymbolKind: @retroactive ExpressibleByArgument {}
extension SymbolType: @retroactive ExpressibleByArgument {}
extension SymbolBinding: @retroactive ExpressibleByArgument {}
extension BinaryFormat: @retroactive ExpressibleByArgument {}
extension Endianness: @retroactive ExpressibleByArgument {}
extension Architecture: @retroactive ExpressibleByArgument {}
// The one option value on the CLI that parses by NAME rather than by numeric
// raw value, because this enum is String-backed while the others are `Int`-
// backed schema enums where the number is what a script already holds.
extension ProcedureDetectionPattern: @retroactive ExpressibleByArgument {}
