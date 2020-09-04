class ExportSection: VectorSection {
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
        funcSection: FunctionSection,
        globalSection: GlobalSection
    ) {
        var exports: [Export] = []
        func addExport(
            _ target: IndexableTarget,
            baseOffset _: Index,
            kind kindConstructor: (Index) -> ExportSection.Export.Kind
        ) {
            let kind = kindConstructor(target.itemIndex)
            let export = ExportSection.Export(kind: kind, name: target.name)
            exports.append(export)
        }

        for symbol in symbolTable.symbols() {
            guard symbol.flags.isExported else { continue }
            switch symbol {
            case let .function(symbol):
                guard case let .defined(target) = symbol.target else { continue }
                addExport(
                    target,
                    baseOffset: funcSection.indexOffset(for: target.binary)!,
                    kind: Export.Kind.function
                )
            case let .global(symbol):
                guard case let .defined(target) = symbol.target else { continue }
                addExport(
                    target,
                    baseOffset: globalSection.indexOffset(for: target.binary)!,
                    kind: Export.Kind.global
                )
            case .data:
                // FIXME: Support exports for data symbols through global.
                continue
            }
        }
        self.exports = exports
    }

    func writeVectorContent(writer: BinaryWriter, relocator _: Relocator) throws {
        for export in exports {
            try writer.writeExport(export)
        }
    }
}
