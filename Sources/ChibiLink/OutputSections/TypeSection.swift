struct TypeSection: VectorSection {
    var section: BinarySection { .type }
    let size: OutputSectionSize
    let count: Size

    private let sections: [Section]

    func writeVectorContent(writer: BinaryWriter) throws {
        for section in sections {
            try writer.writeSectionPayload(section)
        }
    }

    init(sections: [Section]) {
        var totalSize: Size = 0
        var totalCount: Int = 0
        for section in sections {
            assert(section.sectionCode == .type)
            totalSize += section.payloadSize!
            totalCount += section.count!
        }
        let lengthBytes = encodeULEB128(UInt32(totalSize))
        totalSize += lengthBytes.count
        size = .fixed(totalSize)
        count = totalCount
        self.sections = sections
    }
}
