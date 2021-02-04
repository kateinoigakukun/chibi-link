protocol RelocatableChunk {
    var sectionStart: Offset { get }
    var relocations: [Relocation] { get }
    var parentBinary: InputBinary { get }
    var relocationRange: Range<Index> { get }
}

extension GenericInputSection: RelocatableChunk {
    var sectionStart: Offset { offset }
    var parentBinary: InputBinary { binary }
    var relocationRange: Range<Index> {
        sectionStart..<sectionStart + size
    }
}

extension InputSection: RelocatableChunk {
    var relocations: [Relocation] {
        switch self {
        case .data(let sec): return sec.relocations
        case .element(let sec): return sec.relocations
        case .raw(_, let sec): return sec.relocations
        case .rawVector(_, let sec): return sec.relocations
        }
    }

    var sectionStart: Offset {
        switch self {
        case .data(let sec): return sec.offset
        case .element(let sec): return sec.offset
        case .raw(_, let sec): return sec.offset
        case .rawVector(_, let sec): return sec.offset
        }
    }

    var size: Size {
        switch self {
        case .data(let sec): return sec.size
        case .element(let sec): return sec.size
        case .raw(_, let sec): return sec.size
        case .rawVector(_, let sec): return sec.size
        }
    }

    var chunkBytes: ArraySlice<UInt8> {
        binary.data[sectionStart..<sectionStart + size]
    }
    var parentBinary: InputBinary {
        binary
    }

    var relocationRange: Range<Index> {
        sectionStart..<sectionStart + size
    }
}

class Relocator {
    let symbolTable: SymbolTable
    let typeSection: OutputTypeSection
    let importSection: OutputImportSeciton
    let funcSection: OutputFunctionSection
    let elemSection: OutputElementSection
    let dataSection: OutputDataSection
    let globalSection: OutputGlobalSection

    init(
        symbolTable: SymbolTable, typeSection: OutputTypeSection,
        importSection: OutputImportSeciton, funcSection: OutputFunctionSection,
        elemSection: OutputElementSection, dataSection: OutputDataSection,
        globalSection: OutputGlobalSection
    ) {
        self.symbolTable = symbolTable
        self.typeSection = typeSection
        self.importSection = importSection
        self.funcSection = funcSection
        self.elemSection = elemSection
        self.dataSection = dataSection
        self.globalSection = globalSection
    }

    func relocate<T>(chunk: T) -> ArraySlice<UInt8> where T: RelocatableChunk {
        relocate(
            chunk: &chunk.parentBinary.data,
            relocations: chunk.relocations,
            binary: chunk.parentBinary, in: chunk.relocationRange,
            sectionOffset: chunk.sectionStart
        )
        return chunk.parentBinary.data[chunk.relocationRange]
    }

    func relocate(
        chunk: inout [UInt8], relocations: [Relocation], binary: InputBinary,
        in range: Range<Int>, sectionOffset: Int
    ) {
        for reloc in relocations {
            apply(
                relocation: reloc, sectionOffset: sectionOffset,
                binary: binary, bytes: &chunk, in: range)
        }
    }

    func functionIndex(for target: IndexableTarget) -> Index {
        let importCount = target.binary.funcImports.count
        let isImported = target.itemIndex < importCount
        if isImported {
            let anImport = target.binary.funcImports[target.itemIndex]
            return importSection.importIndex(for: anImport)!
        }
        let offset = target.itemIndex - importCount
        let base = funcSection.indexOffset(for: target.binary)!
        return base + offset
    }

    func globalIndex(for target: IndexableTarget) -> Index {
        let importCount = target.binary.globalImports.count
        let isImported = target.itemIndex < importCount
        if isImported {
            let anImport = target.binary.globalImports[target.itemIndex]
            return importSection.importIndex(for: anImport)!
        }
        let offset = target.itemIndex - importCount
        let base = globalSection.indexOffset(for: target.binary)!
        return base + offset
    }

    func translate(relocation: Relocation, binary: InputBinary, current: Int) -> UInt64 {
        var symbol: Symbol?
        if relocation.type != .TYPE_INDEX_LEB {
            symbol = binary.symbols[relocation.symbolIndex]
        }
        switch relocation.type {
        case .TABLE_INDEX_I32,
            .TABLE_INDEX_I64,
            .TABLE_INDEX_SLEB,
            .TABLE_INDEX_SLEB64,
            .TABLE_INDEX_REL_SLEB:
            return UInt64(elemSection.indexOffset(for: binary)! + current)
        case .MEMORY_ADDR_LEB,
            .MEMORY_ADDR_LEB64,
            .MEMORY_ADDR_SLEB,
            .MEMORY_ADDR_SLEB64,
            .MEMORY_ADDR_REL_SLEB,
            .MEMORY_ADDR_REL_SLEB64,
            .MEMORY_ADDR_I32,
            .MEMORY_ADDR_I64:
            guard case let .data(dataSym) = symbol else {
                fatalError()
            }
            switch dataSym.target {
            case let .defined(target):
                let startVA = dataSection.startVirtualAddress(
                    for: target.segment, binary: target.binary)!
                return UInt64(startVA + target.offset + Int(relocation.addend))
            case .undefined where dataSym.flags.isWeak:
                return 0
            case .undefined:
                fatalError()
            case let .synthesized(target):
                return UInt64(target.address)
            }
        case .TYPE_INDEX_LEB:
            // for R_WASM_TYPE_INDEX_LEB, symbolIndex means the index for the type
            return UInt64(typeSection.indexOffset(for: binary)! + relocation.symbolIndex)
        case .FUNCTION_INDEX_LEB:
            guard case let .function(funcSym) = symbol else {
                fatalError()
            }
            switch funcSym.target {
            case let .defined(target):
                return UInt64(functionIndex(for: target))
            case .undefined where funcSym.flags.isWeak:
                fatalError(
                    "unreachable: weak undef symbols should be replaced with synthesized stub function"
                )
            case let .undefined(funcImport):
                return UInt64(importSection.importIndex(for: funcImport)!)
            case let .synthesized(target):
                return UInt64(
                    importSection.functionCount + symbolTable.synthesizedFuncIndex(for: target)!)
            }
        case .GLOBAL_INDEX_LEB, .GLOBAL_INDEX_I32:
            guard case let .global(globalSym) = symbol else {
                fatalError()
            }
            switch globalSym.target {
            case let .defined(target):
                return UInt64(globalIndex(for: target))
            case let .undefined(globalImport):
                return UInt64(importSection.importIndex(for: globalImport)!)
            case let .synthesized(target):
                return UInt64(
                    importSection.globalCount + symbolTable.synthesizedGlobalIndex(for: target)!)
            }
        case .FUNCTION_OFFSET_I32:
            guard case let .function(funcSym) = symbol,
                case .defined = funcSym.target
            else {
                fatalError()
            }
        // TODO: Need to parse each function code to derive code offset
        case .SECTION_OFFSET_I32:
            // TODO: Support section symbol
            break
        }
        fatalError()
    }

    func apply(
        relocation: Relocation, sectionOffset: Offset, binary: InputBinary,
        bytes: inout [UInt8], in range: Range<Int>
    ) {
        let location = sectionOffset + relocation.offset
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
        func writeByte(offset: Int, value: UInt8) {
            bytes[location + offset] = value
        }
        switch relocation.type.outputType {
        case .ULEB128_32Bit:
            encodeULEB128(UInt32(value), padTo: 5, writer: writeByte)
        case .ULEB128_64Bit:
            encodeULEB128(UInt64(value), padTo: 10, writer: writeByte)
        case .SLEB128_32Bit:
            encodeSLEB128(Int32(value), padTo: 5, writer: writeByte)
        case .SLEB128_64Bit:
            encodeSLEB128(Int64(value), padTo: 10, writer: writeByte)
        case .LE32Bit:
            encodeLittleEndian(UInt32(value), writer: writeByte)
        case .LE64Bit:
            encodeLittleEndian(UInt64(value), writer: writeByte)
        }
    }
}

extension RelocType {
    fileprivate enum OutputType {
        case ULEB128_32Bit
        case ULEB128_64Bit
        case SLEB128_32Bit
        case SLEB128_64Bit
        case LE32Bit
        case LE64Bit
    }

    fileprivate var outputType: OutputType {
        switch self {
        case .TYPE_INDEX_LEB,
            .FUNCTION_INDEX_LEB,
            .GLOBAL_INDEX_LEB,
            .MEMORY_ADDR_LEB:
            return .ULEB128_32Bit
        case .MEMORY_ADDR_LEB64:
            return .ULEB128_64Bit
        case .TABLE_INDEX_SLEB,
            .TABLE_INDEX_REL_SLEB,
            .MEMORY_ADDR_SLEB,
            .MEMORY_ADDR_REL_SLEB:
            return .SLEB128_32Bit
        case .TABLE_INDEX_SLEB64,
            .MEMORY_ADDR_SLEB64,
            .MEMORY_ADDR_REL_SLEB64:
            return .SLEB128_64Bit
        case .TABLE_INDEX_I32,
            .MEMORY_ADDR_I32,
            .FUNCTION_OFFSET_I32,
            .SECTION_OFFSET_I32,
            .GLOBAL_INDEX_I32:
            return .LE32Bit
        case .TABLE_INDEX_I64,
            .MEMORY_ADDR_I64:
            return .LE64Bit
        }
    }
}

func encodeLittleEndian<T>(
    _ value: T,
    writer: (_ offset: Int, _ byte: UInt8) -> Void
) where T: FixedWidthInteger {
    let size = MemoryLayout<T>.size
    for offset in 0..<size {
        let shift = offset * Int(8)
        let mask: T = 0xFF << shift
        writer(offset, UInt8((value & mask) >> shift))
    }
}

func decodeLittleEndian<T>(_ bytes: ArraySlice<UInt8>, _: T.Type) -> T
where T: FixedWidthInteger {
    var value: T = 0
    let size = MemoryLayout<T>.size
    for offset in 0..<size {
        let shift = offset * Int(8)
        let byte = bytes[bytes.startIndex + offset]
        value += numericCast(byte) << shift
    }
    return value
}
