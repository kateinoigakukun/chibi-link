class DataSegment {
    let memoryIndex: Index
    var offset: Offset!
    var size: Size!
    var info: Info!
    var data: ArraySlice<UInt8>!

    struct Info {
        let name: String
        let alignment: Int
        let flags: UInt32
    }

    internal init(memoryIndex: Index) {
        self.memoryIndex = memoryIndex
    }
}

struct Relocation {
    let type: RelocType
    let offset: Offset
    let symbolIndex: Index
    let addend: Int32
}

class FunctionImport {
    let module: String
    let field: String
    let signatureIdx: Int
    weak var selfBinary: InputBinary?

    init(module: String, field: String, signatureIdx: Int, selfBinary: InputBinary) {
        self.module = module
        self.field = field
        self.signatureIdx = signatureIdx
        self.selfBinary = selfBinary
    }
}

class GlobalImport {
    internal init(module: String, field: String, type: ValueType, mutable: Bool) {
        self.module = module
        self.field = field
        self.type = type
        self.mutable = mutable
    }

    let module: String
    let field: String
    let type: ValueType
    let mutable: Bool
}

class Export {
    let kind: ExternalKind
    let name: String
    let index: Index

    init(kind: ExternalKind, name: String, index: Index) {
        self.kind = kind
        self.name = name
        self.index = index
    }
}

struct InitFunction {
    let priority: UInt32
    let symbolIndex: Index
    weak var binary: InputBinary!
}

class InputBinary {
    let filename: String
    let data: [UInt8]

    fileprivate(set) var sections: [InputSection] = []
    fileprivate(set) var funcImports: [FunctionImport] = []
    fileprivate(set) var globalImports: [GlobalImport] = []

    fileprivate(set) var exports: [Export] = []

    fileprivate(set) var functionCount: Int!

    fileprivate(set) var debugNames: [String] = []
    fileprivate(set) var symbols: [Symbol] = []
    fileprivate(set) var initFunctions: [InitFunction] = []

    init(filename: String, data: [UInt8]) {
        self.filename = filename
        self.data = data
    }
}

func hasCount(_ section: SectionCode) -> Bool {
    section != .custom && section != .start
}

class LinkInfoCollector: BinaryReaderDelegate {
    var state: BinaryReader.State!
    var currentSection: InputSection!
    var currentRelocTargetSection: InputSection!
    var dataSection: InputDataSection!

    let binary: InputBinary
    let symbolTable: SymbolTable
    init(binary: InputBinary, symbolTable: SymbolTable) {
        self.binary = binary
        self.symbolTable = symbolTable
    }

    func setState(_ state: BinaryReader.State) {
        self.state = state
    }

    func beginSection(_ sectionCode: SectionCode, size: Size) {
        let section: InputSection
        func parseVector<E>(_: E.Type = E.self) -> InputVectorContent<E> {
            let (itemCount, offset) = decodeULEB128(binary.data[state.offset...], UInt32.self)
            assert(itemCount != 0)
            let payloadOffset = state.offset + offset
            let payloadSize = size - offset
            return InputVectorContent<E>(
                payloadOffset: payloadOffset, payloadSize: payloadSize, count: Int(itemCount)
            )
        }
        switch sectionCode {
        case .custom, .start:
            section = .raw(sectionCode, InputRawSection(size: size, offset: state.offset, binary: binary))
        case .data:
            dataSection = InputDataSection(
                size: size, offset: state.offset, content: parseVector(), binary: binary
            )
            section = .data(dataSection)
        case .elem:
            section = .element(
                InputElementSection(
                    size: size, offset: state.offset, content: parseVector(), binary: binary
                )
            )
        default: // vector section
            section = .rawVector(
                sectionCode,
                InputVectorSection(
                    size: size, offset: state.offset, content: parseVector(), binary: binary
                )
            )
        }
        binary.sections.append(section)
        currentSection = section
    }

    func onImportFunc(_: Index, _ module: String, _ field: String, _: Int, _ signatureIndex: Index) {
        let funcImport = FunctionImport(
            module: module, field: field,
            signatureIdx: signatureIndex,
            selfBinary: binary
        )
        binary.funcImports.append(funcImport)
    }

    func onImportGlobal(_: Index, _ module: String, _ field: String, _: Index, _ type: ValueType, _ mutable: Bool) {
        let globalImport = GlobalImport(module: module, field: field, type: type, mutable: mutable)
        binary.globalImports.append(globalImport)
    }

    func onFunctionCount(_ count: Int) {
        binary.functionCount = count
    }

    func onElementSegmentFunctionIndexCount(_: Index, _ indexCount: Int) {
        guard case let .element(sec) = currentSection else { preconditionFailure() }
        let segment = ElementSegment(offset: state.offset, elementCount: indexCount)
        sec.content.elements.append(segment)
    }

    func onMemory(_: Index, _: Limits) {}

    func onExport(_: Index, _ kind: ExternalKind, _ itemIndex: Index, _ name: String) {
        let export = Export(kind: kind, name: name, index: itemIndex)
        binary.exports.append(export)
    }

    func beginDataSegment(_: Index, _ memoryIndex: Index) {
        guard case let .data(sec) = currentSection else { preconditionFailure() }
        let segment = DataSegment(memoryIndex: memoryIndex)
        sec.content.elements.append(segment)
    }

    func onInitExprI32ConstExpr(_: Index, _ value: UInt32) {
        guard case let .data(sec) = currentSection else { return }
        let segment = sec.content.elements.last!
        segment.offset = Int(value)
    }

    func onDataSegmentData(_: Index, _ data: ArraySlice<UInt8>, _ size: Size) {
        guard case let .data(sec) = currentSection else { preconditionFailure() }
        let segment = sec.content.elements.last!
        segment.size = size
        segment.data = data
    }

    func beginNamesSection(_: Size) {
        let funcSize = binary.functionCount + binary.funcImports.count
        binary.debugNames = Array(repeating: "", count: funcSize)
    }

    func onFunctionName(_ index: Index, _ name: String) {
        binary.debugNames[index] = name
    }

    func onRelocCount(_: Int, _ sectionIndex: Index) {
        currentRelocTargetSection = binary.sections[sectionIndex]
    }

    func onReloc(_ type: RelocType, _ offset: Offset, _ symbolIndex: Index, _ addend: Int32) {
        let reloc = Relocation(type: type, offset: offset, symbolIndex: symbolIndex, addend: addend)
        currentRelocTargetSection.append(relocation: reloc)
    }

    func onFunctionSymbol(_: Index, _ rawFlags: UInt32, _ name: String?, _ itemIndex: Index) {
        let target: FunctionSymbol.Target
        let flags = SymbolFlags(rawValue: rawFlags)
        if let name = name, !flags.isUndefined {
            target = .defined(IndexableTarget(itemIndex: itemIndex, name: name, binary: binary))
        } else {
            target = .undefined(binary.funcImports[itemIndex])
        }
        let symbol: FunctionSymbol
        if flags.isLocal {
            symbol = FunctionSymbol(target: target, flags: flags)
        } else {
            symbol = symbolTable.addFunctionSymbol(target, flags: flags)
        }
        binary.symbols.append(.function(symbol))
    }

    func onGlobalSymbol(_: Index, _ rawFlags: UInt32, _ name: String?, _ itemIndex: Index) {
        let target: GlobalSymbol.Target
        let flags = SymbolFlags(rawValue: rawFlags)
        if let name = name, !flags.isUndefined {
            target = .defined(IndexableTarget(itemIndex: itemIndex, name: name, binary: binary))
        } else {
            target = .undefined(binary.globalImports[itemIndex])
        }
        let symbol: GlobalSymbol
        if flags.isLocal {
            symbol = GlobalSymbol(target: target, flags: flags)
        } else {
            symbol = symbolTable.addGlobalSymbol(target, flags: flags)
        }
        binary.symbols.append(.global(symbol))
    }

    func onDataSymbol(_: Index, _ rawFlags: UInt32, _ name: String,
                      _ content: (segmentIndex: Index, offset: Offset, size: Size)?)
    {
        let target: DataSymbol.Target
        let flags = SymbolFlags(rawValue: rawFlags)
        if let content = content, !flags.isUndefined {
            let segment = dataSection.content.elements[content.segmentIndex]
            target = .defined(
                DataSymbol.DefinedSegment(
                    name: name,
                    segment: segment,
                    offset: content.offset,
                    context: binary.filename,
                    binary: binary
                )
            )
        } else {
            target = .undefined(DataSymbol.UndefinedSegment(name: name))
        }
        let symbol: DataSymbol
        if flags.isLocal {
            symbol = DataSymbol(target: target, flags: flags)
        } else {
            symbol = symbolTable.addDataSymbol(target, flags: flags)
        }
        binary.symbols.append(.data(symbol))
    }

    func onSegmentInfo(_ index: Index, _ name: String, _ alignment: Int, _ flags: UInt32) {
        let info = DataSegment.Info(name: name, alignment: alignment, flags: flags)
        dataSection.content.elements[index].info = info
    }

    func onInitFunction(_ initSymbol: Index, _ priority: UInt32) {
        let initFn = InitFunction(priority: priority, symbolIndex: initSymbol, binary: binary)
        binary.initFunctions.append(initFn)
    }
}
