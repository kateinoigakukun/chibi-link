class OutputFunctionSection: OutputVectorSection {
    var section: BinarySection { .function }
    var size: OutputSectionSize { .unknown }
    let count: Int
    private let sections: [Section]
    private let typeSection: OutputTypeSection
    private let indexOffsetByFileName: [String: Offset]

    init(sections: [Section],
         typeSection: OutputTypeSection,
         importSection: OutputImportSeciton,
         symbolTable: SymbolTable
    ) {
        var totalCount = symbolTable.synthesizedFuncs().count
        var indexOffsets: [String: Offset] = [:]
        for section in sections {
            indexOffsets[section.binary!.filename] = totalCount + importSection.functionCount
            totalCount += section.count!
        }
        count = totalCount
        self.sections = sections
        self.typeSection = typeSection
        indexOffsetByFileName = indexOffsets
    }

    func indexOffset(for binary: InputBinary) -> Offset? {
        return indexOffsetByFileName[binary.filename]
    }

    func writeVectorContent(writer: BinaryWriter, relocator: Relocator) throws {
        // Synthesized functions and types are always on the head of sections
        var synthesizedSignatureCount = 0
        for synthesized in relocator.symbolTable.synthesizedFuncs() {
            if let (binary, index) = synthesized.reuseSignatureIndex {
                let baseOffset = typeSection.indexOffset(for: binary)!
                try writer.writeIndex(baseOffset + index)
            } else {
                try writer.writeIndex(synthesizedSignatureCount)
                synthesizedSignatureCount += 1
            }
        }
        // Read + Write + Relocate type indexes
        for section in sections {
            let payloadStart = section.payloadOffset!
            let payloadSize = section.payloadSize!
            let payloadEnd = payloadStart + payloadSize
            var readOffset = payloadStart
            let typeIndexOffset = typeSection.indexOffset(for: section.binary!)!
            for _ in 0 ..< section.count! {
                let payload = section.binary!.data[readOffset ..< payloadEnd]
                let (typeIndex, length) = decodeULEB128(payload, UInt32.self)
                readOffset += length
                try writer.writeIndex(Index(typeIndex) + typeIndexOffset)
            }
        }
    }
}
