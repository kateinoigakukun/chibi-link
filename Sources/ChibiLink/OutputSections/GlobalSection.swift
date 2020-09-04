class GlobalSection: VectorSection {
    var section: BinarySection { .global }
    let size: OutputSectionSize
    let count: Int
    let sections: [Section]
    private let indexOffsetByFileName: [String: Offset]

    init(sections: [Section], importSection: ImportSeciton) {
        var totalSize = 0
        var totalCount = 0
        var indexOffsets: [String: Offset] = [:]
        for section in sections {
            indexOffsets[section.binary!.filename] = totalCount + importSection.globalCount
            totalSize += section.payloadSize!
            totalCount += section.count!
        }
        let lengthBytes = encodeULEB128(UInt32(totalCount))
        totalSize += lengthBytes.count
        self.sections = sections
        count = totalCount
        size = .fixed(totalSize)
        indexOffsetByFileName = indexOffsets
    }

    func indexOffset(for binary: InputBinary) -> Offset? {
        return indexOffsetByFileName[binary.filename]
    }

    func writeVectorContent(writer: BinaryWriter, relocator: Relocator) throws {
        for section in sections {
            let body = relocator.relocate(chunk: section)
            let payload = body[(section.payloadOffset! - section.offset)...]
            try writer.writeBytes(payload)
        }
    }
}
