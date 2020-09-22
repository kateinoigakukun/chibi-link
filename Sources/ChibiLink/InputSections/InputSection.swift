struct Relocation {
    let type: RelocType
    let offset: Offset
    let symbolIndex: Index
    let addend: Int32
}

class InputVectorContent<Element> {
    let payloadOffset: Offset
    let payloadSize: Size
    let count: Int
    var elements: [Element] = []
    
    internal init(payloadOffset: Offset, payloadSize: Size, count: Int) {
        self.payloadOffset = payloadOffset
        self.payloadSize = payloadSize
        self.count = count
    }
}

class GenericInputSection<Content> {
    let size: Size
    let offset: Offset
    let content: Content
    weak var _binary: InputBinary!
    var binary: InputBinary { _binary }
    var relocations: [Relocation] = []
    
    init(size: Size, offset: Offset, content: Content, binary: InputBinary) {
        self.size = size
        self.offset = offset
        self.content = content
        self._binary = binary
    }
}

typealias InputVectorSection = GenericInputSection<InputVectorContent<Never>>
typealias InputRawSection = GenericInputSection<Void>

extension GenericInputSection where Content == Void {
    convenience init(size: Size, offset: Offset, binary: InputBinary) {
        self.init(size: size, offset: offset, content: (), binary: binary)
    }
}

enum InputSection {
    case data(InputDataSection)
    case element(InputElementSection)
    case raw(SectionCode, InputRawSection)
    case rawVector(SectionCode, InputVectorSection)
    
    var sectionCode: SectionCode {
        switch self {
        case .data: return .data
        case .element: return .elem
        case let .raw(code, _),
             let .rawVector(code, _): return code
        }
    }
    
    func append(relocation: Relocation) {
        switch self {
        case .data(let sec):
            sec.relocations.append(relocation)
        case .element(let sec):
            sec.relocations.append(relocation)
        case .raw(_, let sec):
            sec.relocations.append(relocation)
        case .rawVector(_, let sec):
            sec.relocations.append(relocation)
        }
    }
    
    var binary: InputBinary {
        switch self {
        case .data(let sec): return sec.binary
        case .element(let sec): return sec.binary
        case .raw(_, let sec): return sec.binary
        case .rawVector(_, let sec): return sec.binary
        }
    }
}
