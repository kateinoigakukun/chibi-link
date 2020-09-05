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

        synthesizeFunctionSymbols()

        let typeSection = TypeSection(
            sections: sectionsMap[.type] ?? [], symbolTable: symbolTable
        )
        let dataSection = DataSection(sections: sectionsMap[.data] ?? [])

        synthesizeDataSymbols(dataSection: dataSection)
        synthesizeGlobalSymbols()

        let importSection = ImportSeciton(symbolTable: symbolTable, typeSection: typeSection)
        let funcSection = FunctionSection(
            sections: sectionsMap[.function] ?? [],
            typeSection: typeSection, importSection: importSection, symbolTable: symbolTable
        )
        let globalSection = GlobalSection(
            sections: sectionsMap[.global] ?? [],
            importSection: importSection, symbolTable: symbolTable
        )
        let exportSection = ExportSection(
            symbolTable: symbolTable,
            funcSection: funcSection,
            globalSection: globalSection
        )
        exportSection.addExport(ExportSection.Export(kind: .memory(0), name: "memory"))
        let codeSection = CodeSection(sections: sectionsMap[.code] ?? [], symbolTable: symbolTable)
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

    func synthesizeDataSymbols(dataSection: DataSection) {
        func addSynthesizedSymbol(name: String, address: Offset) {
            let dummySegment = DataSegment(memoryIndex: 0)
            dummySegment.info = DataSegment.Info(name: name, alignment: 1, flags: 0)
            let segment = DataSymbol.DefinedSegment(
                name: name, segment: dummySegment, context: "_linker"
            )
            let flags = SymbolFlags(rawValue: SYMBOL_VISIBILITY_HIDDEN)
            _ = symbolTable.addDataSymbol(.defined(segment), flags: flags)
            dataSection.setVirtualAddress(for: name, address)
            print("Log: \(name) is synthesized")
        }

        for (segment, address) in dataSection.segments {
            addSynthesizedSymbol(name: "__start_\(segment.name)", address: address)
            addSynthesizedSymbol(name: "__stop_\(segment.name)", address: address)
        }
        addSynthesizedSymbol(name: "__dso_handle", address: 0)
    }

    func synthesizeGlobalSymbols() {
        func addSynthesizedSymbol(name: String, mutable: Bool, value: Int32) {
            let target = GlobalSymbol.Synthesized(
                name: name, context: "_linker", type: .i32,
                mutable: mutable, value: value
            )
            let flags = SymbolFlags(rawValue: SYMBOL_VISIBILITY_HIDDEN)
            _ = symbolTable.addGlobalSymbol(.synthesized(target), flags: flags)
            print("Log: \(name) is synthesized")
        }
        addSynthesizedSymbol(name: "__stack_pointer", mutable: true, value: 0)
    }

    func synthesizeFunctionSymbols() {
        // Synthesize ctors caller
        let initFunctions = inputs.flatMap(\.initFunctions).sorted(by: {
            $0.priority < $1.priority
        })
        let target = FunctionSymbol.Synthesized.ctorsCaller(inits: initFunctions)
        let flags = SymbolFlags(rawValue: SYMBOL_VISIBILITY_HIDDEN)
        _ = symbolTable.addFunctionSymbol(.synthesized(target), flags: flags)

        // Synthesize weak undef func stubs
        for sym in symbolTable.symbols() {
            guard case let .function(sym) = sym,
                  case let .undefined(target) = sym.target,
                  sym.flags.isWeak else { continue }
            let flags = SymbolFlags(rawValue: SYMBOL_VISIBILITY_HIDDEN)
            let synthesized = FunctionSymbol.Synthesized.weakUndefStub(target)
            _ = symbolTable.addFunctionSymbol(.synthesized(synthesized), flags: flags)
            print("Log: weak undef stub for \(target.name) is synthesized")
        }
    }
}
