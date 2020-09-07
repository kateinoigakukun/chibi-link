
class TableSection: VectorSection {
    var count: Int = 1
    var section: BinarySection { .table }
    var size: OutputSectionSize { .unknown }

    let elementCount: Int

    init(elementSection: ElementSection) {
        elementCount = elementSection.elementCount
    }

    func writeVectorContent(writer: BinaryWriter, relocator _: Relocator) throws {
        // TODO: Support max and shared table
        // Add 1 for trap func at offset 0
        let limits = Limits(initial: elementCount + 1, max: nil, isShared: false)
        try writer.writeTable(type: .funcRef, limits: limits)
    }
}
