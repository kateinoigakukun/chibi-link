class StartSection: OutputSection {
    var section: BinarySection { .start }
    let size: OutputSectionSize
    let index: Index

    init?(symbolTable: SymbolTable, funcSection: FunctionSection) {
        guard case let .function(symbol) = symbolTable.find("_start") else {
            return nil
        }
        guard case let .defined(target) = symbol.target else {
            return nil
        }
        let base = funcSection.indexOffset(for: target.binary)!
        index = base + target.itemIndex - target.binary.funcImports.count
        size = .fixed(encodeULEB128(UInt32(index)).count)
    }

    func writeContent(writer: BinaryWriter, relocator _: Relocator) throws {
        try writer.writeIndex(index)
    }
}
