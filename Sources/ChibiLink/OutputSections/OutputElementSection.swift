class OutputElementSection: OutputVectorSection {
    var section: SectionCode { .elem }
    var size: OutputSectionSize { .unknown }
    let count: Int = 1
    let elementCount: Int
    private let sections: [InputElementSection]
    private let funcSection: OutputFunctionSection
    private let indexOffsetByFileID: [InputBinary.ID: Offset]

    init(sections: [InputSection], funcSection: OutputFunctionSection) {
        var totalElemCount = 0
        var indexOffsets: [InputBinary.ID: Offset] = [:]
        var elemSections: [InputElementSection] = []
        for section in sections {
            guard case let .element(section) = section else { preconditionFailure() }
            indexOffsets[section.binary.id] = totalElemCount
            totalElemCount += section.content.elements.reduce(0) { $0 + $1.elementCount }
            elemSections.append(section)
        }
        elementCount = totalElemCount
        self.sections = elemSections
        self.funcSection = funcSection
        indexOffsetByFileID = indexOffsets
    }

    func indexOffset(for binary: InputBinary) -> Offset? {
        return indexOffsetByFileID[binary.id]
    }

    func writeVectorContent(writer: BinaryWriter, relocator _: Relocator) throws {
        try writer.writeULEB128(UInt32(0)) // table index
        // For non-PIC, we start at 1 so that accessing table index 0 always traps.
        try writer.writeI32InitExpr(.i32(1)) // offset
        try writer.writeULEB128(UInt32(elementCount))
        // Read + Write + Relocate func indexes
        for section in sections {
            let binary = section.binary
            let offsetBase = funcSection.indexOffset(for: binary)! - binary.funcImports.count
            for segment in section.content.elements {
                var readOffset = segment.offset
                for _ in 0 ..< segment.elementCount {
                    let payload = section.binary.data[readOffset...]
                    let (funcIndex, length) = decodeULEB128(payload, UInt32.self)
                    readOffset += length
                    try writer.writeIndex(Index(funcIndex) + offsetBase)
                }
            }
        }
    }
}
