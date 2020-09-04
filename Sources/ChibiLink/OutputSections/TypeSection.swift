class TypeSection: VectorSection {
    var section: BinarySection { .type }
    let size: OutputSectionSize
    let count: Size

    private let sections: [Section]
    private let indexOffsetByFileName: [String: Offset]

    func writeVectorContent(writer: BinaryWriter, relocator: Relocator) throws {
        for section in sections {
            let offset = section.payloadOffset!
            let bytes = section.binary!.data[offset ..< offset + section.payloadSize!]
            try writer.writeBytes(bytes)
        }
    }
    
    func indexOffset(for binary: InputBinary) -> Offset? {
        return indexOffsetByFileName[binary.filename]
    }

    init(sections: [Section]) {
        var totalSize: Size = 0
        var totalCount: Int = 0
        var indexOffsets: [String: Offset] = [:]
        for section in sections {
            assert(section.sectionCode == .type)
            indexOffsets[section.binary!.filename] = totalCount
            totalSize += section.payloadSize!
            totalCount += section.count!
        }
        let lengthBytes = encodeULEB128(UInt32(totalCount))
        totalSize += lengthBytes.count
        size = .fixed(totalSize)
        count = totalCount
        self.sections = sections
        self.indexOffsetByFileName = indexOffsets
    }
}
