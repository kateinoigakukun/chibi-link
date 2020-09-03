class OutputWriter {
    let writer: BinaryWriter
    let symbolTable: SymbolTable
    let inputs: [InputBinary]
    init(stream: OutputByteStream,
         symbolTable: SymbolTable,
         inputs: [InputBinary])
    {
        writer = BinaryWriter(stream: stream)
        self.symbolTable = symbolTable
        self.inputs = inputs
    }

    func writeBinary() throws {
        try writer.writeHeader()

        var sectionsMap: [BinarySection: [Section]] = [:]
        for sec in inputs.lazy.flatMap(\.sections) {
            sectionsMap[sec.sectionCode, default: []].append(sec)
        }
        let typeSection = TypeSection(sections: sectionsMap[.type] ?? [])
        let importSection = ImportSeciton(symbolTable: symbolTable)
        let dataSection = DataSection(sections: sectionsMap[.data] ?? [])

        try writeSection(typeSection)
        try writeSection(importSection)
        try writeSection(dataSection)
    }
    
    func writeSection<S: OutputSection>(_ section: S) throws {
        try section.write(writer: writer)
    }
}
