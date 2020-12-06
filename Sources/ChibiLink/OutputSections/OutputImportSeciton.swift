struct OutputImportSeciton: OutputVectorSection {
    struct Import {
        let kind: Kind
        let module: String
        let field: String
        enum Kind {
            case function(signature: Index)
            case global(type: ValueType, mutable: Bool)
        }
    }

    var section: SectionCode { .import }
    var size: OutputSectionSize { .unknown }
    var count: Int { imports.count }
    private(set) var functionCount: Int = 0
    private(set) var globalCount: Int = 0

    private(set) var imports: [Import] = []
    private var importFuncIndexMap: [String: Index] = [:]
    private var importGlobalIndexMap: [String: Index] = [:]

    func importIndex(for target: FunctionImport) -> Index? {
        let key = uniqueImportKey(module: target.module, field: target.name)
        return importFuncIndexMap[key]
    }

    func importIndex(for target: GlobalImport) -> Index? {
        let key = uniqueImportKey(module: target.module, field: target.name)
        return importGlobalIndexMap[key]
    }

    init(symbolTable: SymbolTable, typeSection: OutputTypeSection) {
        func addImport<S>(_ symbol: S) where S: SymbolProtocol {
            guard let newImport = createImport(symbol, typeSection: typeSection) else { return }

            let key = uniqueImportKey(
                module: newImport.module, field: newImport.field
            )
            switch newImport.kind {
            case .global:
                importGlobalIndexMap[key] = globalCount
                globalCount += 1
            case .function:
                importFuncIndexMap[key] = functionCount
                functionCount += 1
            }

            imports.append(newImport)
        }
        #if DEBUG
            debug("Print all undefined symbols")
            for symbol in symbolTable.symbols() {
                guard symbol.isUndefined else { continue }
                debug(symbol.name)
            }
        #endif
        for symbol in symbolTable.symbols() {
            switch symbol {
            case let .function(symbol): addImport(symbol)
            case let .global(symbol): addImport(symbol)
            case .data:
                // We don't generate imports for data symbols.
                continue
            }
        }
    }

    func writeVectorContent(writer: BinaryWriter, relocator _: Relocator) throws {
        for anImport in imports {
            try writer.writeImport(anImport)
        }
    }
}

private func uniqueImportKey(module: String, field: String) -> String {
    module + "." + field
}

private func createImport<S>(_ symbol: S, typeSection: OutputTypeSection) -> OutputImportSeciton
    .Import? where S: SymbolProtocol
{
    typealias Import = OutputImportSeciton.Import
    guard !symbol.flags.isWeak else { return nil }
    switch symbol.target {
    case .defined, .synthesized: return nil
    case let .undefined(undefined as FunctionImport):
        let typeBaseIndex = typeSection.indexOffset(for: undefined.selfBinary!)!
        let signature = typeBaseIndex + undefined.signatureIdx
        let kind = Import.Kind.function(signature: signature)
        return Import(
            kind: kind,
            module: undefined.module,
            field: undefined.name
        )
    case let .undefined(undefined as GlobalImport):
        let kind = Import.Kind.global(type: undefined.type, mutable: undefined.mutable)
        return Import(
            kind: kind,
            module: undefined.module,
            field: undefined.name
        )
    default:
        fatalError("unreachable")
    }
}
