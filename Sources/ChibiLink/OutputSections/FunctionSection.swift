class FunctionSection: VectorSection {
    var section: BinarySection { .function }
    var size: OutputSectionSize { .unknown }
    let count: Int
    private let sections: [Section]
    private let typeSection: TypeSection
    private let indexOffsetByFileName: [String: Offset]
    
    init(sections: [Section], typeSection: TypeSection) {
        var totalCount = 0
        var indexOffsets: [String: Offset] = [:]
        for section in sections {
            indexOffsets[section.binary!.filename] = totalCount
            totalCount += section.count!
        }
        self.count = totalCount
        self.sections = sections
        self.typeSection = typeSection
        self.indexOffsetByFileName = indexOffsets
    }

    func indexOffset(for binary: InputBinary) -> Offset? {
        return indexOffsetByFileName[binary.filename]
    }
    
    func writeVectorContent(writer: BinaryWriter) throws {
        // Read + Write + Relocate type indexes
        for section in sections {
            let payloadStart = section.payloadOffset!
            let payloadSize = section.payloadSize!
            let payloadEnd = payloadStart + payloadSize
            var readOffset = payloadStart
            let typeIndexOffset = typeSection.indexOffset(for: section.binary!)!
            for _ in 0..<section.count! {
                let payload = section.binary!.data[readOffset..<payloadEnd]
                let (typeIndex, length) = decodeULEB128(payload, UInt32.self)
                readOffset += length
                try writer.writeIndex(Index(typeIndex) + typeIndexOffset)
            }
        }
    }
}
