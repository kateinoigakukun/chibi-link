class GlobalSection: VectorSection {
    struct Synthesized {
        let type: ValueType
        let mutable: Bool
        let value: Int32
    }
    var section: BinarySection { .global }
    var size: OutputSectionSize { .unknown }
    let count: Int
    let sections: [Section]
    private let indexOffsetByFileName: [String: Offset]
    private let synthesized: [Synthesized]

    init(sections: [Section], synthesized: [Synthesized],
         dummyBinary: InputBinary, importSection: ImportSeciton) {
        var totalCount = 0
        var indexOffsets: [String: Offset] = [:]
        let offset = importSection.globalCount

        indexOffsets[dummyBinary.filename] = totalCount + offset
        totalCount += synthesized.count

        for section in sections {
            indexOffsets[section.binary!.filename] = totalCount + offset
            totalCount += section.count!
        }

        self.sections = sections
        self.synthesized = synthesized
        count = totalCount
        indexOffsetByFileName = indexOffsets
    }

    func indexOffset(for binary: InputBinary) -> Offset? {
        return indexOffsetByFileName[binary.filename]
    }

    func writeVectorContent(writer: BinaryWriter, relocator: Relocator) throws {
        for global in synthesized {
            try writer.writeFixedUInt8(global.type.rawValue)
            try writer.writeFixedUInt8(global.mutable ? 1 : 0)
            try writer.writeI32InitExpr(.i32(global.value))
        }
        for section in sections {
            let body = relocator.relocate(chunk: section)
            let payload = body[(section.payloadOffset! - section.offset)...]
            try writer.writeBytes(payload)
        }
    }
}
