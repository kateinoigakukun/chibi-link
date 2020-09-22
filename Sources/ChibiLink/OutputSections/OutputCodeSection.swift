class OutputCodeSection: OutputVectorSection {
    var section: BinarySection { .code }
    var size: OutputSectionSize { .unknown }
    let count: Int
    let sections: [Section]

    init(sections: [Section], symbolTable: SymbolTable) {
        var totalCount = symbolTable.synthesizedFuncs().count
        for section in sections {
            totalCount += section.count!
        }

        self.sections = sections
        count = totalCount
    }

    func writeVectorContent(writer: BinaryWriter, relocator: Relocator) throws {
        for synthesizedFunc in relocator.symbolTable.synthesizedFuncs() {
            try synthesizedFunc.writeCode(writer: writer, relocator: relocator)
        }
        for section in sections {
            let body = relocator.relocate(chunk: section)
            let payload = body[(section.payloadOffset! - section.offset)...]
            try writer.writeBytes(payload)
        }
    }
}
