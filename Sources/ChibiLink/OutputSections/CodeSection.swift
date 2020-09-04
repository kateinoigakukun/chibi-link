class CodeSection: VectorSection {
    var section: BinarySection { .code }
    let size: OutputSectionSize
    let count: Int
    let sections: [Section]
    let relocator: Relocator

    init(sections: [Section], relocator: Relocator) {
        var totalSize = 0
        var totalCount = 0
        for section in sections {
            totalSize += section.payloadSize!
            totalCount += section.count!
        }
        let lengthBytes = encodeULEB128(UInt32(totalCount))
        totalSize += lengthBytes.count
        self.sections = sections
        count = totalCount
        size = .fixed(totalSize)
        self.relocator = relocator
    }

    func writeVectorContent(writer: BinaryWriter, relocator: Relocator) throws {
        for section in sections {
            let text = relocator.relocate(section: section)
            try writer.writeBytes(text[...])
        }
    }
}
