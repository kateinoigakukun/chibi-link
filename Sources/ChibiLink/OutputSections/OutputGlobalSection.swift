class OutputGlobalSection: OutputVectorSection {
    typealias Synthesized = GlobalSymbol.Synthesized
    var section: SectionCode { .global }
    var size: OutputSectionSize { .unknown }
    let count: Int
    let sections: [InputVectorSection]
    private let indexOffsetByFileID: [InputBinary.ID: Offset]

    init(sections: [InputSection], importSection: OutputImportSeciton, symbolTable: SymbolTable) {
        let synthesizedCount = symbolTable.synthesizedGlobals().count
        var totalCount = synthesizedCount
        var indexOffsets: [InputBinary.ID: Offset] = [:]
        let offset = importSection.globalCount
        var vectorSections: [InputVectorSection] = []

        for section in sections {
            guard case let .rawVector(code, section) = section,
                code == .global
            else { preconditionFailure() }
            indexOffsets[section.binary.id] = totalCount + offset
            totalCount += section.content.count
            vectorSections.append(section)
        }

        self.sections = vectorSections
        count = totalCount
        indexOffsetByFileID = indexOffsets
    }

    func indexOffset(for binary: InputBinary) -> Offset? {
        return indexOffsetByFileID[binary.id]
    }

    func writeVectorContent(writer: BinaryWriter, relocator: Relocator) throws {
        for global in relocator.symbolTable.synthesizedGlobals() {
            try writer.writeFixedUInt8(global.type.rawValue)
            try writer.writeFixedUInt8(global.mutable ? 1 : 0)
            try writer.writeI32InitExpr(.i32(global.value))
        }
        for section in sections {
            let body = relocator.relocate(chunk: section)
            let payload = body[
                (section.sectionStart + section.content.payloadOffset - section.offset)...]
            try writer.writeBytes(payload)
        }
    }
}
