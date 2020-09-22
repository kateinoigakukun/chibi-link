class OutputExportSection: OutputVectorSection {
    struct Export {
        let kind: Kind
        let name: String
        enum Kind {
            case function(Index)
            case global(Index)
            case memory(Index)
        }
    }

    var section: BinarySection { .export }
    var count: Int { exports.count }
    var size: OutputSectionSize { .unknown }
    private(set) var exports: [Export]

    func addExport(_ export: Export) {
        exports.append(export)
    }

    init(
        symbolTable: SymbolTable,
        exportSymbols: [String],
        funcSection: OutputFunctionSection,
        globalSection: OutputGlobalSection
    ) {
        var exports: [Export] = []
        func exportFunction(_ target: IndexableTarget) {
            let base = funcSection.indexOffset(for: target.binary)!
            let index = base + target.itemIndex - target.binary.funcImports.count
            exports.append(OutputExportSection.Export(kind: .function(index), name: target.name))
        }

        exports.append(OutputExportSection.Export(kind: .memory(0), name: "memory"))
        if case let .function(symbol) = symbolTable.find("_start"),
           case let .defined(target) = symbol.target {
            exportFunction(target)
        }
        for export in exportSymbols {
            guard case let .function(symbol) = symbolTable.find(export),
               case let .defined(target) = symbol.target else {
                fatalError("Error: Export function '\(export)' not found")
            }
            exportFunction(target)
        }
        self.exports = exports
    }

    func writeVectorContent(writer: BinaryWriter, relocator _: Relocator) throws {
        for export in exports {
            try writer.writeExport(export)
        }
    }
}
