
class TableSection: VectorSection {
    var count: Int = 1
    var section: BinarySection { .table }
    var size: OutputSectionSize { .unknown }
    
    let elementCount: Int
    
    init(inputs: [InputBinary]) {
        elementCount = inputs.reduce(0) {
            $0 + $1.tableElemSize
        }
    }

    func writeVectorContent(writer: BinaryWriter, relocator: Relocator) throws {
        // TODO: Support max and shared table
        let limits = Limits(initial: elementCount, max: nil, isShared: false)
        try writer.writeTable(type: .funcRef, limits: limits)
    }
}
