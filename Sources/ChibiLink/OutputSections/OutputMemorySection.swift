class OutputMemorySection: OutputVectorSection {
    var section: SectionCode { .memory }
    var size: OutputSectionSize { .unknown }
    var count: Int { 1 }
    let pagesCount: Int

    init(heapStart: Int32) {
        pagesCount = align(Int(heapStart), to: PAGE_SIZE) / PAGE_SIZE
    }

    func writeVectorContent(writer: BinaryWriter, relocator _: Relocator) throws {
        // TODO: Support max pages
        let flags: UInt32 = 0
        try writer.writeULEB128(flags)
        try writer.writeULEB128(UInt32(pagesCount))
    }
}
