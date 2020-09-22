class OutputTypeSection: OutputVectorSection {
    var section: SectionCode { .type }
    var size: OutputSectionSize { .unknown }
    let count: Size

    private let sections: [InputVectorSection]
    private let indexOffsetByFileName: [String: Offset]
    private let symbolTable: SymbolTable

    func indexOffset(for binary: InputBinary) -> Offset? {
        return indexOffsetByFileName[binary.filename]
    }

    init(sections: [InputSection], symbolTable: SymbolTable) {
        var totalCount: Int = symbolTable.synthesizedFuncs().filter {
            $0.reuseSignatureIndex == nil
        }.count
        var indexOffsets: [String: Offset] = [:]
        var typeSections: [InputVectorSection] = []
        for section in sections {
            guard case let .rawVector(code, section) = section,
                  code == .type else { preconditionFailure() }
            indexOffsets[section.binary.filename] = totalCount
            totalCount += section.content.count
            typeSections.append(section)
        }
        count = totalCount
        self.sections = typeSections
        self.symbolTable = symbolTable
        indexOffsetByFileName = indexOffsets
    }

    func writeVectorContent(writer: BinaryWriter, relocator: Relocator) throws {
        for synthesizedFunc in symbolTable.synthesizedFuncs() {
            try synthesizedFunc.writeSignature(writer: writer)
        }
        for section in sections {
            let offset = section.content.payloadOffset
            let bytes = section.binary.data[offset ..< offset + section.content.payloadSize]
            try writer.writeBytes(bytes)
        }
    }
}
