class CodeSection: VectorSection {
    var section: BinarySection { .code }
    let size: OutputSectionSize
    let count: Int
    let funcSection: FunctionSection
    let sections: [Section]
    
    init(sections: [Section], funcSection: FunctionSection) {
        var totalSize = 0
        var totalCount = 0
        for section in sections {
            totalSize += section.payloadSize!
            totalCount += section.count!
        }
        assert(totalCount == funcSection.count)
        let lengthBytes = encodeULEB128(UInt32(totalCount))
        totalSize += lengthBytes.count
        self.funcSection = funcSection
        self.sections = sections
        self.count = totalCount
        self.size = .fixed(totalSize)
    }
    
    func writeVectorContent(writer: BinaryWriter) throws {
        for section in sections {
            let textStart = section.payloadOffset!
            let textEnd = textStart + section.payloadSize!
            let text = section.binary!.data[textStart..<textEnd]
            // TODO: Apply relocations
            try writer.writeBytes(text)
        }
    }
}
