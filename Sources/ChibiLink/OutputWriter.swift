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
        let funcSection = FunctionSection(
            sections: sectionsMap[.function] ?? [],
            typeSection: typeSection, importSection: importSection
        )
        let globalSection = GlobalSection(
            sections: sectionsMap[.global] ?? [], importSection: importSection
        )
        let exportSection = ExportSection(
            symbolTable: symbolTable,
            funcSection: funcSection,
            globalSection: globalSection
        )
        exportSection.addExport(ExportSection.Export(kind: .memory(0), name: "memory"))
        let dataSection = DataSection(sections: sectionsMap[.data] ?? [])
        let codeSection = CodeSection(sections: sectionsMap[.code] ?? [])
        let tableSection = TableSection(inputs: inputs)
        let memorySection = MemorySection(dataSection: dataSection)
        let elemSection = ElementSection(
            sections: sectionsMap[.elem] ?? [], funcSection: funcSection
        )

        let relocator = Relocator(
            symbolTable: symbolTable, typeSection: typeSection,
            importSection: importSection, funcSection: funcSection,
            elemSection: elemSection, dataSection: dataSection,
            globalSection: globalSection
        )

        func writeSection<S: OutputSection>(_ section: S) throws {
            try section.write(writer: writer, relocator: relocator)
        }

        try writeSection(typeSection)
        try writeSection(importSection)
        try writeSection(funcSection)
        try writeSection(tableSection)
        try writeSection(memorySection)
        try writeSection(globalSection)
        try writeSection(exportSection)
        try writeSection(elemSection)
        try writeSection(codeSection)
        try writeSection(dataSection)
    }
}
