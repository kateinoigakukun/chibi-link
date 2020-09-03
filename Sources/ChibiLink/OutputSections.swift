enum OutputSectionSize {
    case fixed(Size)
    case unknown
}

protocol OutputSection {
    var section: BinarySection { get }
    var size: OutputSectionSize { get }
    func write(writer: BinaryWriter) throws
    func writeContent(writer: BinaryWriter) throws
}

extension OutputSection {
    func write(writer: BinaryWriter) throws {
        try writer.writeSectionCode(section)
        switch size {
        case .fixed(let size):
            try writer.writeULEB128(UInt32(size))
            try writeContent(writer: writer)
        case .unknown:
            let placeholder = try writer.writeSizePlaceholder()
            let contentStart = writer.offset
            try writeContent(writer: writer)
            let contentSize = writer.offset - contentStart
            try writer.fillSizePlaceholder(placeholder, value: contentSize)
        }
    }
}

protocol VectorSection: OutputSection {
    var count: Int { get }
    func writeVectorContent(writer: BinaryWriter) throws
}

extension VectorSection {
    func writeContent(writer: BinaryWriter) throws {
        try writer.writeULEB128(UInt32(count))
        try writeVectorContent(writer: writer)
    }
}

struct TypeSection: VectorSection {
    var section: BinarySection { .type }
    let size: OutputSectionSize
    let count: Size

    private let sections: [Section]

    func writeVectorContent(writer: BinaryWriter) throws {
        for section in sections {
            try writer.writeSectionPayload(section)
        }
    }

    init(sections: [Section]) {
        var totalSize: Size = 0
        var totalCount: Int = 0
        for section in sections {
            assert(section.sectionCode == .type)
            totalSize += section.payloadSize!
            totalCount += section.count!
        }
        let lengthBytes = encodeULEB128(UInt32(totalSize))
        totalSize += lengthBytes.count
        self.size = .fixed(totalSize)
        self.count = totalCount
        self.sections = sections
    }
}

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
    
    mutating func addImport(_ import: Import) {
        imports.append(`import`)
    }

    func writeVectorContent(writer: BinaryWriter) throws {
        for anImport in imports {
            try writer.writeImport(anImport)
        }
    }

    init(symbolTable: SymbolTable) {
        func addImport<S>(_ symbol: S) where S: SymbolProtocol {
            guard let newImport = createImport(symbol) else { return }
            imports.append(newImport)
        }
        for symbol in symbolTable.symbols() {
            switch symbol {
            case .function(let symbol): addImport(symbol)
            case .global(let symbol): addImport(symbol)
            case .data:
                // We don't generate imports for data symbols.
                continue
            }
        }
    }
}

func createImport<S>(_ symbol: S) -> ImportSeciton.Import? where S: SymbolProtocol {
    typealias Import = ImportSeciton.Import
    switch symbol.target {
    case .defined: return nil
    case .undefined(let undefined as FunctionImport):
        let signature = undefined.signatureIdx
            + undefined.selfBinary!.relocOffsets!.typeIndexOffset
        let kind = Import.Kind.function(signature: signature)
        return Import(
            kind: kind,
            module: undefined.module,
            field: undefined.name
        )
    case .undefined(let undefined as GlobalImport):
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
