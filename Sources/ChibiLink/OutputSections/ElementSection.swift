class ElementSection: VectorSection {
    var section: BinarySection { .elem }
    var size: OutputSectionSize { .unknown }
    let count: Int = 1
    let elementCount: Int
    private let sections: [Section]
    private let funcSection: FunctionSection
    private let indexOffsetByFileName: [String: Offset]

    init(sections: [Section], funcSection: FunctionSection) {
        var totalElemCount = 0
        var indexOffsets: [String: Offset] = [:]
        for section in sections {
            indexOffsets[section.binary!.filename] = totalElemCount
            totalElemCount += section.tableElementCount!
        }
        elementCount = totalElemCount
        self.sections = sections
        self.funcSection = funcSection
        indexOffsetByFileName = indexOffsets
    }

    func indexOffset(for binary: InputBinary) -> Offset? {
        return indexOffsetByFileName[binary.filename]
    }

    func writeVectorContent(writer: BinaryWriter, relocator _: Relocator) throws {
        try writer.writeULEB128(UInt32(0)) // table index
        try writer.writeI32InitExpr(.i32(0)) // offset
        try writer.writeULEB128(UInt32(elementCount))
        // Read + Write + Relocate func indexes
        for section in sections {
            let payloadStart = section.payloadOffset!
            let payloadSize = section.payloadSize!
            let payloadEnd = payloadStart + payloadSize
            var readOffset = payloadStart
            let binary = section.binary!
            let offsetBase = funcSection.indexOffset(for: binary)! - binary.funcImports.count
            for _ in 0 ..< section.tableElementCount! {
                let payload = section.binary!.data[readOffset ..< payloadEnd]
                let (funcIndex, length) = decodeULEB128(payload, UInt32.self)
                readOffset += length
                try writer.writeIndex(Index(funcIndex) + offsetBase)
            }
        }
    }
}
