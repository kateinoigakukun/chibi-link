class OutputGlobalSection: OutputVectorSection {
    typealias Synthesized = GlobalSymbol.Synthesized
    var section: BinarySection { .global }
    var size: OutputSectionSize { .unknown }
    let count: Int
    let sections: [Section]
    private let indexOffsetByFileName: [String: Offset]

    init(sections: [Section], importSection: OutputImportSeciton, symbolTable: SymbolTable) {
        let synthesizedCount = symbolTable.synthesizedGlobals().count
        var totalCount = synthesizedCount
        var indexOffsets: [String: Offset] = [:]
        let offset = importSection.globalCount

        for section in sections {
            indexOffsets[section.binary!.filename] = totalCount + offset
            totalCount += section.count!
        }

        self.sections = sections
        count = totalCount
        indexOffsetByFileName = indexOffsets
    }

    func indexOffset(for binary: InputBinary) -> Offset? {
        return indexOffsetByFileName[binary.filename]
    }

    func writeVectorContent(writer: BinaryWriter, relocator: Relocator) throws {
        for global in relocator.symbolTable.synthesizedGlobals() {
            try writer.writeFixedUInt8(global.type.rawValue)
            try writer.writeFixedUInt8(global.mutable ? 1 : 0)
            try writer.writeI32InitExpr(.i32(global.value))
        }
        for section in sections {
            let body = relocator.relocate(chunk: section)
            let payload = body[(section.payloadOffset! - section.offset)...]
            try writer.writeBytes(payload)
        }
    }
}
