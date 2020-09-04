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
        let importSection = ImportSeciton(symbolTable: symbolTable, typeSection: typeSection)
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

        let startSection = StartSection(
            symbolTable: symbolTable, funcSection: funcSection
        )

        #if DEBUG
        let nameSectino = NameSection(inputs: inputs, funcSection: funcSection)
        #endif

        synthesizeSymbols(dataSection: dataSection)

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
        if let startSection = startSection {
            try writeSection(startSection)
        }
        try writeSection(elemSection)
        try writeSection(codeSection)
        try writeSection(dataSection)
        #if DEBUG
        try writeSection(nameSectino)
        #endif
    }

    func synthesizeSymbols(dataSection: DataSection) {
        func addSynthesizedSymbol(name: String, address: Offset) {
            let dummySegment = DataSegment(memoryIndex: 0)
            dummySegment.info = DataSegment.Info(name: name, alignment: 1, flags: 0)
            let segment = DataSymbol.DefinedSegment(
                name: name, segment: dummySegment, context: "_linker"
            )
            let flags = SymbolFlags(rawValue: SYMBOL_VISIBILITY_HIDDEN)
            _ = symbolTable.addDataSymbol(.defined(segment), flags: flags)
            dataSection.setVirtualAddress(for: name, address)
        }

        for (segment, address) in dataSection.segments {
            let name = "__start_\(segment.name)"
            print("Log: \(name) is synthesized")
            addSynthesizedSymbol(name: name, address: address)
        }
        addSynthesizedSymbol(name: "__dso_handle", address: 0)
    }
}
