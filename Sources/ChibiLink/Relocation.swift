protocol RelocatableChunk {
    var relocations: [Relocation] { get }
    var parentBinary: InputBinary { get }
    var relocationRange: Range<Index> { get }
}

extension Section: RelocatableChunk {
    var parentBinary: InputBinary {
        binary!
    }

    var relocationRange: Range<Index> {
        offset ..< offset + size
    }
}

class Relocator {
    let symbolTable: SymbolTable
    let typeSection: TypeSection
    let importSection: ImportSeciton
    let funcSection: FunctionSection
    let elemSection: ElementSection
    let dataSection: DataSection

    init(symbolTable: SymbolTable, typeSection: TypeSection,
         importSection: ImportSeciton, funcSection: FunctionSection,
         elemSection: ElementSection, dataSection: DataSection)
    {
        self.symbolTable = symbolTable
        self.typeSection = typeSection
        self.importSection = importSection
        self.funcSection = funcSection
        self.elemSection = elemSection
        self.dataSection = dataSection
    }

    func relocate<T>(chunk: T) -> [UInt8] where T: RelocatableChunk {
        var body = Array(chunk.parentBinary.data[chunk.relocationRange])
        for reloc in chunk.relocations {
            apply(relocation: reloc, binary: chunk.parentBinary, bytes: &body)
        }
        return body
    }

    func translate(relocation: Relocation, binary: InputBinary) -> UInt64 {
        var symbol: Symbol?
        if relocation.type != .typeIndexLEB {
            symbol = binary.symbols[relocation.symbolIndex]
        }
        switch relocation.type {
        case .tableIndexI32,
             .tableIndexI64,
             .tableIndexSLEB,
             .tableIndexSLEB64,
             .tableIndexRelSLEB:
            fatalError("TODO: Write out TableSection and get index from it")
        case .memoryAddressLEB,
             .memoryAddressLeb64,
             .memoryAddressSLEB,
             .memoryAddressSLEB64,
             .memoryAddressRelSLEB,
             .memoryAddressRelSLEB64,
             .memoryAddressI32,
             .memoryAddressI64:
            guard case let .data(dataSym) = symbol,
                case let .defined(target) = dataSym.target
            else {
                fatalError()
            }
            let startVA = dataSection.startVirtualAddress(for: target.segment)!
            return UInt64(startVA) + UInt64(relocation.addend)
        case .typeIndexLEB:
            // for R_WASM_TYPE_INDEX_LEB, symbolIndex means the index for the type
            return UInt64(typeSection.indexOffset(for: binary)! + relocation.symbolIndex)
        case .functionIndexLEB:
            guard case let .function(funcSym) = symbol else {
                fatalError()
            }
            switch funcSym.target {
            case let .defined(target):
                return UInt64(funcSection.indexOffset(for: target.binary)! + target.itemIndex)
            case let .undefined(funcImport):
                return UInt64(importSection.importIndex(for: funcImport)!)
            }
        case .globalIndexLEB, .globalIndexI32:
            fatalError("TODO")
        case .functionOffsetI32:
            guard case let .function(funcSym) = symbol,
                case .defined = funcSym.target
            else {
                fatalError()
            }
        // TODO: Need to parse each function code to derive code offset
        case .sectionOffsetI32:
            // TODO: Support section symbol
            break
        }
        fatalError()
    }

    func apply(relocation: Relocation, binary: InputBinary, bytes: inout [UInt8]) {
        let location = bytes.startIndex + relocation.offset
        let value = translate(relocation: relocation, binary: binary)
        func writeBytes(_ result: [UInt8]) {
            for (offset, byte) in result.enumerated() {
                bytes[location + offset] = byte
            }
        }
        switch relocation.type {
        case .typeIndexLEB,
             .functionIndexLEB,
             .globalIndexLEB,
             .memoryAddressLEB:
            writeBytes(encodeULEB128(UInt32(value), padTo: 5))
        case .memoryAddressLeb64:
            writeBytes(encodeULEB128(UInt64(value), padTo: 10))
        case .tableIndexSLEB,
             .tableIndexRelSLEB,
             .memoryAddressSLEB,
             .memoryAddressRelSLEB:
            writeBytes(encodeSLEB128(Int32(value), padTo: 5))
        case .tableIndexSLEB64,
             .memoryAddressSLEB64,
             .memoryAddressRelSLEB64:
            writeBytes(encodeSLEB128(Int64(value), padTo: 10))
        case .tableIndexI32,
             .memoryAddressI32,
             .functionOffsetI32,
             .sectionOffsetI32,
             .globalIndexI32:
            writeBytes(encodeLittleEndian(UInt32(value)))
        case .tableIndexI64,
             .memoryAddressI64:
            writeBytes(encodeLittleEndian(UInt64(value)))
        }
    }
}

func encodeLittleEndian<T>(_ value: T) -> [UInt8]
    where T: FixedWidthInteger
{
    let size = MemoryLayout<T>.size
    var bytes = [UInt8](repeating: 0, count: size)
    for offset in 0 ..< size {
        let shift = offset * Int(8)
        let mask: T = 0xFF << shift
        bytes[offset] = UInt8((value & mask) >> shift)
    }
    return bytes
}
