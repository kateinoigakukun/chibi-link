struct ImportSeciton: VectorSection {
    struct Import {
        let kind: Kind
        let module: String
        let field: String
        enum Kind {
            case function(signature: Index)
            case global(type: ValueType, mutable: Bool)
        }
    }

    var section: BinarySection { .import }
    var size: OutputSectionSize { .unknown }
    var count: Int { imports.count }

    private(set) var imports: [Import] = []
    private var importIndexMap: [String: Index] = [:]

    mutating func addImport(_ import: Import) {
        imports.append(`import`)
    }

    func importIndex<T: UndefinedTarget>(for target: T) -> Index? {
        let key = uniqueImportKey(module: target.module, field: target.name)
        return importIndexMap[key]
    }

    init(symbolTable: SymbolTable) {
        func addImport<S>(_ symbol: S) where S: SymbolProtocol {
            guard let newImport = createImport(symbol) else { return }
            let key = uniqueImportKey(
                module: newImport.module, field: newImport.field
            )
            importIndexMap[key] = imports.count
            imports.append(newImport)
        }
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

func createImport<S>(_ symbol: S) -> ImportSeciton.Import? where S: SymbolProtocol {
    typealias Import = ImportSeciton.Import
    switch symbol.target {
    case .defined: return nil
    case let .undefined(undefined as FunctionImport):
        let signature = undefined.signatureIdx
            + undefined.selfBinary!.relocOffsets!.typeIndexOffset
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
