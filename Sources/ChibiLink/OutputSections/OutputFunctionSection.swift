class OutputFunctionSection: OutputVectorSection {
    var section: SectionCode { .function }
    var size: OutputSectionSize { .unknown }
    let count: Int
    private let sections: [InputVectorSection]
    private let typeSection: OutputTypeSection
    private let indexOffsetByFileID: [InputBinary.ID: Offset]
    private let importSection: OutputImportSeciton

    init(
        sections: [InputSection],
        typeSection: OutputTypeSection,
        importSection: OutputImportSeciton,
        symbolTable: SymbolTable
    ) {
        var totalCount = symbolTable.synthesizedFuncs().count
        var indexOffsets: [InputBinary.ID: Offset] = [:]
        var vectorSections: [InputVectorSection] = []
        for section in sections {
            guard case let .rawVector(code, section) = section,
                code == .function
            else { preconditionFailure() }
            indexOffsets[section.binary.id] = importSection.functionCount + totalCount
            totalCount += section.content.count
            vectorSections.append(section)
        }
        count = totalCount
        self.sections = vectorSections
        self.typeSection = typeSection
        self.importSection = importSection
        indexOffsetByFileID = indexOffsets
    }

    func indexOffset(for binary: InputBinary) -> Offset? {
        return indexOffsetByFileID[binary.id]
    }

    func indexOffset(fromIndex objectIndex: Index, binary: InputBinary) -> Offset {
        if objectIndex < binary.funcImports.count {
            let funcImport = binary.funcImports[objectIndex]
            // If not found in the final import section, the import entry is stub or undef
            return importSection.importIndex(for: funcImport) ?? 0
        } else {
            return indexOffsetByFileID[binary.id]! + objectIndex - binary.funcImports.count
        }
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
            let payloadStart = section.content.payloadOffset
            let payloadSize = section.content.payloadSize
            let payloadEnd = payloadStart + payloadSize
            var readOffset = payloadStart
            let typeIndexOffset = typeSection.indexOffset(for: section.binary)!
            for _ in 0..<section.content.count {
                let payload = section.binary.data[readOffset..<payloadEnd]
                let (typeIndex, length) = decodeULEB128(payload, UInt32.self)
                readOffset += length
                try writer.writeIndex(Index(typeIndex) + typeIndexOffset)
            }
        }
    }
}
