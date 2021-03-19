class OutputWriter {
    let writer: BinaryWriter
    let symbolTable: SymbolTable
    let inputs: [InputBinary]
    let exportSymbols: [String]
    init(
        stream: OutputByteStream,
        symbolTable: SymbolTable,
        inputs: [InputBinary],
        exportSymbols: [String] = []
    ) {
        writer = BinaryWriter(stream: stream)
        self.symbolTable = symbolTable
        self.inputs = inputs
        self.exportSymbols = exportSymbols
    }

    func writeBinary() throws {
        try writer.writeHeader()

        var sectionsMap: [SectionCode: [InputSection]] = [:]
        for sec in inputs.lazy.flatMap(\.sections) {
            sectionsMap[sec.sectionCode, default: []].append(sec)
        }

        try synthesizeFunctionSymbols()

        let typeSection = OutputTypeSection(
            sections: sectionsMap[.type] ?? [], symbolTable: symbolTable
        )
        let dataSection = OutputDataSection(sections: sectionsMap[.data] ?? [])

        try synthesizeDataSymbols(dataSection: dataSection)
        try synthesizeStackPointer(dataSection: dataSection)

        let importSection = OutputImportSeciton(symbolTable: symbolTable, typeSection: typeSection)
        let funcSection = OutputFunctionSection(
            sections: sectionsMap[.function] ?? [],
            typeSection: typeSection, importSection: importSection, symbolTable: symbolTable
        )
        let globalSection = OutputGlobalSection(
            sections: sectionsMap[.global] ?? [],
            importSection: importSection, symbolTable: symbolTable
        )
        let exportSection = try OutputExportSection(
            symbolTable: symbolTable,
            exportSymbols: exportSymbols,
            funcSection: funcSection,
            globalSection: globalSection
        )
        let codeSection = OutputCodeSection(
            sections: sectionsMap[.code] ?? [], symbolTable: symbolTable)
        let memorySection = OutputMemorySection(dataSection: dataSection)
        let elemSection = OutputElementSection(
            sections: sectionsMap[.elem] ?? [], funcSection: funcSection
        )
        let tableSection = OutputTableSection(elementSection: elemSection)
        /*
        let startSection = OutputStartSection(
            symbolTable: symbolTable, funcSection: funcSection
        )
        */

        #if DEBUG
            let nameSectino = OutputNameSection(inputs: inputs, funcSection: funcSection)
        #endif

        let relocator = Relocator(
            symbolTable: symbolTable, typeSection: typeSection,
            importSection: importSection, funcSection: funcSection,
            elemSection: elemSection, dataSection: dataSection,
            globalSection: globalSection
        )

        func writeSection<S: OutputSection>(_ section: S) throws {
            debug("Writing \(section.section)")
            try section.write(writer: writer, relocator: relocator)
            debug("Finish writing \(section.section)")
        }

        try writeSection(typeSection)
        try writeSection(importSection)
        try writeSection(funcSection)
        try writeSection(tableSection)
        try writeSection(memorySection)
        try writeSection(globalSection)
        try writeSection(exportSection)
        /*
        if let startSection = startSection {
            try writeSection(startSection)
        }
        */
        try writeSection(elemSection)
        try writeSection(codeSection)
        try writeSection(dataSection)
        #if DEBUG
            try writeSection(nameSectino)
        #endif
    }

    func addSynthesizedSymbol(name: String, mutable: Bool, value: Int32) throws {
        let target = GlobalSymbol.Synthesized(
            name: name, context: "_linker", type: .i32,
            mutable: mutable, value: value
        )
        let flags = SymbolFlags(rawValue: SYMBOL_VISIBILITY_HIDDEN)
        _ = try symbolTable.addGlobalSymbol(.synthesized(target), flags: flags)
        debug("\(name) is synthesized")
    }

    func synthesizeDataSymbols(dataSection: OutputDataSection) throws {
        func addSynthesizedSymbol(name: String, address: Offset) throws {
            let target = DataSymbol.Synthesized(name: name, context: "_linker", address: address)
            let flags = SymbolFlags(rawValue: SYMBOL_VISIBILITY_HIDDEN)
            _ = try symbolTable.addDataSymbol(.synthesized(target), flags: flags)
            debug("\(name) is synthesized")
        }

        for (segment, address) in dataSection.segments {
            try addSynthesizedSymbol(name: "__start_\(segment.name)", address: address)
            try addSynthesizedSymbol(name: "__stop_\(segment.name)", address: address + segment.size)
        }
        try addSynthesizedSymbol(name: "__dso_handle", address: 0)
    }

    func synthesizeStackPointer(dataSection: OutputDataSection) throws {
        // Stack area is allocated **after** static data
        let stackAlignment = 16
        let stackStart = Int32(align(dataSection.initialMemorySize + PAGE_SIZE, to: stackAlignment))
        try addSynthesizedSymbol(name: "__stack_pointer", mutable: true, value: stackStart)
    }

    func synthesizeFunctionSymbols() throws {
        // Synthesize ctors caller
        let initFunctions = inputs.flatMap(\.initFunctions).sorted(by: {
            $0.priority < $1.priority
        })
        let target = FunctionSymbol.Synthesized.ctorsCaller(inits: initFunctions)
        let flags = SymbolFlags(rawValue: SYMBOL_VISIBILITY_HIDDEN)
        _ = try symbolTable.addFunctionSymbol(.synthesized(target), flags: flags)

        // Synthesize weak undef func stubs
        for sym in symbolTable.symbols() {
            guard case let .function(sym) = sym,
                case let .undefined(target) = sym.target,
                sym.flags.isWeak
            else { continue }
            let flags = SymbolFlags(rawValue: SYMBOL_VISIBILITY_HIDDEN)
            let synthesized = FunctionSymbol.Synthesized.weakUndefStub(target)
            _ = try symbolTable.addFunctionSymbol(.synthesized(synthesized), flags: flags)
            debug("weak undef stub for \(target.name) is synthesized")
        }
    }
}
