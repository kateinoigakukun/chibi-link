class MemorySection: VectorSection {
    var section: BinarySection { .memory }
    var size: OutputSectionSize { .unknown }
    var count: Int { 1 }
    let pagesCount: Int
    
    init(dataSection: DataSection) {
        pagesCount = align(dataSection.initialMemorySize, to: PAGE_SIZE) / PAGE_SIZE
    }
    
    func writeVectorContent(writer: BinaryWriter, relocator: Relocator) throws {
        // TODO: Support max pages
        let flags: UInt32 = 0
        try writer.writeULEB128(flags)
        try writer.writeULEB128(UInt32(pagesCount))
    }
}
