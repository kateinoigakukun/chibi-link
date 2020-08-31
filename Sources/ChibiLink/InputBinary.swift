class DataSegment {
    let memoryIndex: Int
    var offset: Int!
    var data: ArraySlice<UInt8>!
    var size: Int!

    internal init(memoryIndex: Int) {
        self.memoryIndex = memoryIndex
    }
}

struct Relocation {
    let type: RelocType
    let offset: UInt32
    let index: UInt32
    let addend: UInt32
}

class Section {
    let sectionCode: BinarySection
    let size: UInt32
    let offset: Int

    var payloadOffset: Int?
    var payloadSize: Int?
    let count: Int?

    var memoryInitialSize: Int?

    var relocations: [Relocation] = []

    var dataSegments: [DataSegment] = []

    weak var binary: InputBinary?

    init(sectionCode: BinarySection, size: UInt32, offset: Int,
         payloadOffset _: Int?, payloadSize _: Int?, count: Int?,
         binary: InputBinary)
    {
        self.sectionCode = sectionCode
        self.size = size
        self.offset = offset
        self.count = count
        self.binary = binary
    }
}

class FunctionImport {
    let module: String
    let field: String
    let signatureIdx: Int
    var active: Bool

    init(module: String, field: String, signatureIdx: Int, active: Bool) {
        self.module = module
        self.field = field
        self.signatureIdx = signatureIdx
        self.active = active
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
    let index: Int

    init(kind: ExternalKind, name: String, index: Int) {
        self.kind = kind
        self.name = name
        self.index = index
    }
}

class InputBinary {
    let filename: String
    let data: [UInt8]

    fileprivate(set) var sections: [Section] = []
    fileprivate(set) var funcImports: [FunctionImport] = []
    fileprivate(set) var globalImports: [GlobalImport] = []

    fileprivate(set) var exports: [Export] = []

    fileprivate(set) var functionCount: Int!
    fileprivate(set) var tableElemCount: Int!

    fileprivate(set) var debugNames: [String] = []

    init(filename: String, data: [UInt8]) {
        self.filename = filename
        self.data = data
    }
}

func hasCount(_ section: BinarySection) -> Bool {
    section != .custom && section != .start
}

class LinkInfoCollector: BinaryReaderDelegate {
    var state: BinaryReader.State!
    var currentSection: Section!
    var currentRelocSection: Section!
    let binary: InputBinary
    init(binary: InputBinary) {
        self.binary = binary
    }

    func setState(_ state: BinaryReader.State) {
        self.state = state
    }

    func beginSection(_ sectionCode: BinarySection, size: UInt32) {
        var count: UInt32?
        var startOffset: Int?
        if hasCount(sectionCode) {
            (count, startOffset) = decodeLEB128(binary.data[state.offset...])
            assert(count != 0)
        }
        let section = Section(
            sectionCode: sectionCode, size: size, offset: state.offset,
            payloadOffset: startOffset.map { state.offset + $0 },
            payloadSize: startOffset.map { Int(size) - $0 },
            count: count.map(Int.init),
            binary: binary
        )
        binary.sections.append(section)
        currentSection = section
    }

    func onImportFunc(_: Int, _ module: String, _ field: String, _: Int, _ signatureIndex: Int) {
        let funcImport = FunctionImport(
            module: module, field: field,
            signatureIdx: signatureIndex,
            active: true
        )
        binary.funcImports.append(funcImport)
    }

    func onImportMemory(_: Int, _: String, _: String, _: Int, _: Limits) {
        fatalError("TODO")
    }

    func onImportGlobal(_: Int, _ module: String, _ field: String, _: Int, _ type: ValueType, _ mutable: Bool) {
        let globalImport = GlobalImport(module: module, field: field, type: type, mutable: mutable)
        binary.globalImports.append(globalImport)
    }

    func onFunctionCount(_ count: Int) {
        binary.functionCount = count
    }

    func onTable(_: Int, _: ElementType, _ limits: Limits) {
        binary.tableElemCount = Int(limits.initial)
    }

    func onElementSegmentFunctionIndexCount(_: Int, _: Int) {
        let sec = currentSection!
        let delta = state.offset - sec.payloadOffset!
        sec.payloadOffset! += delta
        sec.payloadSize! -= delta
    }

    func onMemory(_: Int, _ pageLimits: Limits) {
        currentSection.memoryInitialSize = Int(pageLimits.initial)
    }

    func onExport(_: Int, _ kind: ExternalKind, _ itemIndex: Int, _ name: String) {
        let export = Export(kind: kind, name: name, index: itemIndex)
        binary.exports.append(export)
    }

    func beginDataSegment(_: Int, _ memoryIndex: Int) {
        let sec = currentSection!
        let segment = DataSegment(memoryIndex: memoryIndex)
        sec.dataSegments.append(segment)
    }

    func onInitExprI32ConstExpr(_: Int, _ value: UInt32) {
        let sec = currentSection!
        guard sec.sectionCode == .data else { return }
        let segment = sec.dataSegments.last!
        segment.offset = Int(value)
    }

    func onDataSegmentData(_: Int, _ data: ArraySlice<UInt8>, _ size: Int) {
        let sec = currentSection!
        let segment = sec.dataSegments.last!
        segment.data = data
        segment.size = size
    }

    func beginNamesSection(_: UInt32) {
        let funcSize = binary.functionCount + binary.funcImports.count
        binary.debugNames = Array(repeating: "", count: funcSize)
    }

    func onFunctionName(_ index: Int, _ name: String) {
        binary.debugNames[index] = name
    }

    func onRelocCount(_: Int, _ sectionIndex: Int) {
        currentRelocSection = binary.sections[sectionIndex]
    }

    func onReloc(_ type: RelocType, _ offset: UInt32, _ index: UInt32, _ addend: UInt32) {
        let reloc = Relocation(type: type, offset: offset, index: index, addend: addend)
        currentRelocSection.relocations.append(reloc)
    }
}
