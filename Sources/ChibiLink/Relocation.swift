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
    let globalSection: GlobalSection

    init(symbolTable: SymbolTable, typeSection: TypeSection,
         importSection: ImportSeciton, funcSection: FunctionSection,
         elemSection: ElementSection, dataSection: DataSection,
         globalSection: GlobalSection)
    {
        self.symbolTable = symbolTable
        self.typeSection = typeSection
        self.importSection = importSection
        self.funcSection = funcSection
        self.elemSection = elemSection
        self.dataSection = dataSection
        self.globalSection = globalSection
    }

    func relocate<T>(chunk: T) -> [UInt8] where T: RelocatableChunk {
        var body = Array(chunk.parentBinary.data[chunk.relocationRange])
        for reloc in chunk.relocations {
            apply(relocation: reloc, binary: chunk.parentBinary, bytes: &body)
        }
        return body
    }

    func translate(relocation: Relocation, binary: InputBinary, current: Int) -> UInt64 {
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
            return UInt64(elemSection.indexOffset(for: binary)! + current)
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
                if let symbol = symbol, symbol.flags.isWeak {
                    return 0
                }
                fatalError()
            }
            let startVA = dataSection.startVirtualAddress(for: target.segment)!
            return UInt64(startVA + Int(relocation.addend))
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
            guard case let .global(globalSym) = symbol else {
                fatalError()
            }
            switch globalSym.target {
            case let .defined(target):
                return UInt64(globalSection.indexOffset(for: target.binary)! + target.itemIndex)
            case let .undefined(globalImport):
                return UInt64(importSection.importIndex(for: globalImport)!)
            }
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
        let currentValue: Int
        switch relocation.type.outputType {
        case .ULEB128_32Bit:
            currentValue = Int(decodeULEB128(bytes[location...], UInt32.self).value)
        case .ULEB128_64Bit:
            currentValue = Int(decodeULEB128(bytes[location...], UInt64.self).value)
        case .SLEB128_32Bit:
            currentValue = Int(decodeSLEB128(bytes[location...], Int32.self).value)
        case .SLEB128_64Bit:
            currentValue = Int(decodeSLEB128(bytes[location...], Int64.self).value)
        case .LE32Bit:
            currentValue = Int(decodeLittleEndian(bytes[location...], UInt32.self))
        case .LE64Bit:
            currentValue = Int(decodeLittleEndian(bytes[location...], UInt64.self))
        }
        let value = translate(relocation: relocation, binary: binary, current: currentValue)
        func writeBytes(_ result: [UInt8]) {
            for (offset, byte) in result.enumerated() {
                bytes[location + offset] = byte
            }
        }
        switch relocation.type.outputType {
        case .ULEB128_32Bit:
            writeBytes(encodeULEB128(UInt32(value), padTo: 5))
        case .ULEB128_64Bit:
            writeBytes(encodeULEB128(UInt64(value), padTo: 10))
        case .SLEB128_32Bit:
            writeBytes(encodeSLEB128(Int32(value), padTo: 5))
        case .SLEB128_64Bit:
            writeBytes(encodeSLEB128(Int64(value), padTo: 10))
        case .LE32Bit:
            writeBytes(encodeLittleEndian(UInt32(value)))
        case .LE64Bit:
            writeBytes(encodeLittleEndian(UInt64(value)))
        }
    }
}

private extension RelocType {
    enum OutputType {
        case ULEB128_32Bit
        case ULEB128_64Bit
        case SLEB128_32Bit
        case SLEB128_64Bit
        case LE32Bit
        case LE64Bit
    }

    var outputType: OutputType {
        switch self {
        case .typeIndexLEB,
             .functionIndexLEB,
             .globalIndexLEB,
             .memoryAddressLEB:
            return .ULEB128_32Bit
        case .memoryAddressLeb64:
            return .ULEB128_64Bit
        case .tableIndexSLEB,
             .tableIndexRelSLEB,
             .memoryAddressSLEB,
             .memoryAddressRelSLEB:
            return .SLEB128_32Bit
        case .tableIndexSLEB64,
             .memoryAddressSLEB64,
             .memoryAddressRelSLEB64:
            return .SLEB128_64Bit
        case .tableIndexI32,
             .memoryAddressI32,
             .functionOffsetI32,
             .sectionOffsetI32,
             .globalIndexI32:
            return .LE32Bit
        case .tableIndexI64,
             .memoryAddressI64:
            return .LE64Bit
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

func decodeLittleEndian<T>(_ bytes: ArraySlice<UInt8>, _: T.Type) -> T
    where T: FixedWidthInteger
{
    var value: T = 0
    let size = MemoryLayout<T>.size
    for offset in 0 ..< size {
        let shift = offset * Int(8)
        let byte = bytes[offset]
        value += T(byte) << shift
    }
    return value
}
