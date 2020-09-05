class TypeSection: VectorSection {
    var section: BinarySection { .type }
    var size: OutputSectionSize { .unknown }
    let count: Size

    private let sections: [Section]
    private let indexOffsetByFileName: [String: Offset]
    private let symbolTable: SymbolTable

    func indexOffset(for binary: InputBinary) -> Offset? {
        return indexOffsetByFileName[binary.filename]
    }

    init(sections: [Section], symbolTable: SymbolTable) {
        var totalCount: Int = symbolTable.synthesizedFuncs().count
        var indexOffsets: [String: Offset] = [:]
        for section in sections {
            assert(section.sectionCode == .type)
            indexOffsets[section.binary!.filename] = totalCount
            totalCount += section.count!
        }
        count = totalCount
        self.sections = sections
        self.symbolTable = symbolTable
        indexOffsetByFileName = indexOffsets
    }

    func writeVectorContent(writer: BinaryWriter, relocator: Relocator) throws {
        for synthesizedFunc in symbolTable.synthesizedFuncs() {
            try synthesizedFunc.writeSignature(writer: writer)
        }
        for section in sections {
            let offset = section.payloadOffset!
            let bytes = section.binary!.data[offset ..< offset + section.payloadSize!]
            try writer.writeBytes(bytes)
        }
    }
}
