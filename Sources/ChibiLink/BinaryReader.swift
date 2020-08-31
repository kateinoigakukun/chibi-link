protocol BinaryReaderDelegate {
    func setState(_ state: BinaryReader.State)
    func beginSection(_ section: BinarySection, size: UInt32)
    func onImportFunc(
        _ importIndex: Int,
        _ module: String, _ field: String,
        _ funcIndex: Int,
        _ signatureIndex: Int
    )
    
    func onImportMemory(
        _ importIndex: Int,
        _ module: String, _ field: String,
        _ memoryIndex: Int, _ pageLimits: Limits
    )

    func onImportGlobal(
        _ importIndex: Int,
        _ module: String, _ field: String,
        _ globalIndex: Int,
        _ type: ValueType, _ mutable: Bool
    )

    func onFunctionCount(_ count: Int)

    
    func onTable(_ tableIndex: Int, _ type: ElementType, _ limits: Limits)
    func onMemory(_ memoryIndex: Int, _ pageLimits: Limits)
    func onExport(_ exportIndex: Int, _ kind: ExternalKind,
                  _ itemIndex: Int, _ name: String)
    func onElementSegmentFunctionIndex(_ segmentIndex: Int, _ funcIndex: Int)
    
    func beginDataSegment(_ segmentIndex: Int, _ memoryIndex: Int)
    func onDataSegmentData(_ segmentIndex: Int, _ data: ArraySlice<UInt8>, _ size: Int)

    func beginNamesSection(_ size: UInt32)
    func onFunctionName(_ index: Int, _ name: String)

    func onRelocCount(_ relocsCount: Int, _ sectionIndex: Int)
    
    func onReloc(_ type: RelocType, _ offset: UInt32,
                 _ index: UInt32, _ addend: UInt32)

    func onInitExprI32ConstExpr(_ segmentIndex: Int, _ value: UInt32)
    
}

class BinaryReader {
    enum Error: Swift.Error {
        case invalidSectionCode(UInt8)
        case invalidElementType(UInt8)
        case invalidValueType(UInt8)
        case invalidExternalKind(UInt8)
        case invalidRelocType(UInt8)
        case expectConstOpcode(UInt8)
        case expectI32Const(ConstOpcode)
        case expectEnd
    }

    class State {
        fileprivate(set) var offset: Int = 0
        let bytes: [UInt8]

        init(bytes: [UInt8]) {
            self.bytes = bytes
        }
    }

    let length: Int
    let state: State
    var delegate: BinaryReaderDelegate

    var funcImportCount = 0
    var tableImportCount = 0
    var memoryImportCount = 0
    var globalImportCount = 0
    var sectionEnd: Int!

    init(bytes: [UInt8], delegate: BinaryReaderDelegate) {
        length = bytes.count
        state = State(bytes: bytes)
        self.delegate = delegate
        delegate.setState(state)
    }

    // MARK: - Reader Utilities
    @discardableResult
    func read(_ length: Int) -> ArraySlice<UInt8> {
        let result = state.bytes[state.offset ..< state.offset + length]
        state.offset += length
        return result
    }

    func readU8Fixed() -> UInt8 {
        let byte = state.bytes[state.offset]
        state.offset += 1
        return byte
    }

    func readU32Leb128() -> UInt32 {
        let (value, advanced) = decodeLEB128(state.bytes[state.offset...])
        state.offset += advanced
        return value
    }
    
    func readS32Leb128() -> UInt32 {
        let (value, advanced) = decodeSLEB128(state.bytes[state.offset...])
        state.offset += advanced
        return value
    }

    func readUInt32() -> UInt32 {
        let bytes = read(4)
        return UInt32(bytes[bytes.startIndex + 0])
            + (UInt32(bytes[bytes.startIndex + 1]) << 8)
            + (UInt32(bytes[bytes.startIndex + 2]) << 16)
            + (UInt32(bytes[bytes.startIndex + 3]) << 24)
    }

    func readString() -> String {
        let length = Int(readU32Leb128())
        let bytes = state.bytes[state.offset ..< state.offset + length]
        let name = String(decoding: bytes, as: Unicode.ASCII.self)
        state.offset += length
        return name
    }

    func readTable() throws -> (type: ElementType, limits: Limits) {
        let rawType = readU8Fixed()
        guard let elementType = ElementType(rawValue: rawType) else {
            throw Error.invalidElementType(rawType)
        }
        let hasMax = readU8Fixed() != 0
        let initial = readU32Leb128()
        let max = hasMax ? readU32Leb128() : nil
        return (elementType, Limits(initial: initial, max: max))
    }

    func readMemory() throws -> Limits {
        let flags = readU8Fixed()
        let hasMax = (flags & LIMITS_HAS_MAX_FLAG) != 0
        let isShared = (flags & LIMITS_IS_SHARED_FLAG) != 0
        let initial = readU32Leb128()
        let max = hasMax ? readU32Leb128() : nil
        return Limits(initial: initial, max: max, isShared: isShared)
    }

    func readGlobalHeader() throws -> (type: ValueType, mutable: Bool) {
        let globalType = try readValueType()
        let mutable = readU8Fixed() != 0
        return (globalType, mutable)
    }

    func readValueType() throws -> ValueType {
        let rawType = readU8Fixed()
        guard let type = ValueType(rawValue: rawType) else {
            throw Error.invalidValueType(rawType)
        }
        return type
    }
    
    func readI32InitExpr(segmentIndex: Int) throws {
        let code = readU8Fixed()
        guard let constOp = ConstOpcode(rawValue: code) else {
            throw Error.expectConstOpcode(code)
        }
        switch constOp {
        case .i32Const:
            let value = readU32Leb128()
            delegate.onInitExprI32ConstExpr(segmentIndex, value)
        case .f32Const, .f64Const, .i64Const:
            throw Error.expectI32Const(constOp)
        }
        let endCode = readU8Fixed()
        guard let opcode = Opcode(rawValue: endCode),
              opcode == .end else {
            throw Error.expectEnd
        }
    }
    
    func readBytes() -> (data: ArraySlice<UInt8>, size: Int) {
        let size = Int(readU32Leb128())
        let data = state.bytes[state.offset..<state.offset + size]
        state.offset += size
        return (data, size)
    }

    // MARK: - Entry point
    func readModule() throws {
        let maybeMagic = read(4)
        assert(maybeMagic.elementsEqual(magic))
        let maybeVersion = read(4)
        assert(maybeVersion.elementsEqual(version))
        try readSections()
    }

    func readSections() throws {
        var isEOF: Bool { state.offset >= length }
        while !isEOF {
            let sectionCode = readU8Fixed()
            let size = readU32Leb128()
            guard let section = BinarySection(rawValue: sectionCode) else {
                throw Error.invalidSectionCode(sectionCode)
            }
            sectionEnd = state.offset + Int(size)
            delegate.beginSection(section, size: size)

            switch section {
            case .custom:
                try readCustomSection(sectionSize: size)
            case .function:
                try readFunctionSection(sectionSize: size)
            case .import:
                try readImportSection(sectionSize: size)
            case .table:
                try readTableSection(sectionSize: size)
            case .memory:
                try readMemorySection(sectionSize: size)
            case .export:
                try readExportSection(sectionSize: size)
            case .elem:
                try readElementSection(sectionSize: size)
            default:
                print("Warning: Section '\(section)' is currently not supported")
            }

            state.offset = sectionEnd
        }
    }

    func readFunctionSection(sectionSize _: UInt32) throws {
        let functionCount = Int(readU32Leb128())
        delegate.onFunctionCount(functionCount)
    }

    func readImportSection(sectionSize _: UInt32) throws {
        let importCount = Int(readU32Leb128())
        for importIdx in 0 ..< importCount {
            let module = readString()
            let field = readString()
            let rawKind = readU8Fixed()
            let kind = ExternalKind(rawValue: rawKind)
            switch kind {
            case .func:
                let signagureIdx = Int(readU32Leb128())
                delegate.onImportFunc(
                    importIdx,
                    module, field,
                    funcImportCount,
                    signagureIdx
                )
                funcImportCount += 1
            case .table:
                _ = try readTable()
            // onImportTable
                tableImportCount += 1
            case .memory:
                let limits = try readMemory()
                delegate.onImportMemory(
                    importIdx,
                    module, field,
                    memoryImportCount,
                    limits
                )
                memoryImportCount += 1
            case .global:
                let (type, mutable) = try readGlobalHeader()
                delegate.onImportGlobal(
                    importIdx,
                    module, field,
                    globalImportCount,
                    type, mutable
                )
                globalImportCount += 1
            default:
                if let kind = kind {
                    fatalError("Error: Import kind '\(kind)' is not supported")
                } else {
                    fatalError("Error: Import kind '(rawKind = \(rawKind))' is not supported")
                }
            }
        }
    }
    
    func readTableSection(sectionSize: UInt32) throws {
        let tablesCount = Int(readU32Leb128())
        assert(tablesCount <= 1)
        for i in 0..<tablesCount {
            let tableIdx = tableImportCount + i
            let (elemTy, limits) = try readTable()
            delegate.onTable(tableIdx, elemTy, limits)
        }
    }
    
    func readMemorySection(sectionSize: UInt32) throws {
        let memoriesCount = Int(readU32Leb128())
        assert(memoriesCount <= 1)
        for i in 0..<memoriesCount {
            let memoryIdx = memoryImportCount + i
            let limits = try readMemory()
            delegate.onMemory(memoryIdx, limits)
        }
    }
    
    func readExportSection(sectionSize: UInt32) throws {
        let exportsCount = Int(readU32Leb128())
        for i in 0..<exportsCount {
            let name = readString()
            let rawKind = readU8Fixed()
            guard let kind = ExternalKind(rawValue: rawKind) else {
                throw Error.invalidValueType(rawKind)
            }
            let itemIndex = Int(readU32Leb128())
            delegate.onExport(i, kind, itemIndex, name)
        }
    }
    
    func readElementSection(sectionSize: UInt32) throws {
        let segmentsCount = Int(readU32Leb128())
        for i in 0..<segmentsCount {
            _ = readU32Leb128() // tableIndex
            try readI32InitExpr(segmentIndex: i)
            let funcIndicesCount = Int(readU32Leb128())
            
            for _ in 0..<funcIndicesCount {
                let funcIdx = Int(readU32Leb128())
                delegate.onElementSegmentFunctionIndex(i, funcIdx)
            }
        }
    }
    
    func readDataSection(sectionSize: UInt32) throws {
        // BeginDataSection
        let segmentsCount = Int(readU32Leb128())
        // OnDataSegmentCount
        for i in 0..<segmentsCount {
            let memoryIndex = Int(readU32Leb128())
            delegate.beginDataSegment(i, memoryIndex)
            // BeginDataSegmentInitExpr
            try readI32InitExpr(segmentIndex: i)
            // EndDataSegmentInitExpr
            let (data, size) = readBytes()
            delegate.onDataSegmentData(i, data, size)
            // EndDataSegment
        }
        // EndDataSection
    }

    func readCustomSection(sectionSize: UInt32) throws {
        let sectionName = readString()
        // BeginCustomSection
        switch sectionName {
        case "name":
            try readNameSection(sectionSize: sectionSize)
        case _ where sectionName.hasPrefix("reloc."):
            try readRelocSection(sectionSize: sectionSize)
        default:
            print("Warning: Custom section '\(sectionName)' is currently not supported")
        }
    }

    func readNameSection(sectionSize: UInt32) throws {
        delegate.beginNamesSection(sectionSize)

        while state.offset < sectionEnd {
            let subsectionType = readU8Fixed()
            let subsectionSize = Int(readU32Leb128())
            let subsectionEnd = state.offset + subsectionSize

            switch NameSectionSubsection(rawValue: subsectionType) {
            case .function:
                // OnFunctionNameSubsection
                let namesCount = readU32Leb128()
                for _ in 0 ..< namesCount {
                    let funcIdx = Int(readU32Leb128())
                    let funcName = readString()
                    delegate.onFunctionName(funcIdx, funcName)
                }
            default:
                // Skip
                state.offset = subsectionEnd
            }
        }
    }
    
    func readRelocSection(sectionSize: UInt32) throws {
        let sectionIndex = Int(readU32Leb128())
        let relocsCount = Int(readU32Leb128())
        delegate.onRelocCount(relocsCount, sectionIndex)

        for _ in 0..<relocsCount {
            let rawType = readU8Fixed()
            guard let type = RelocType(rawValue: rawType) else {
                throw Error.invalidRelocType(rawType)
            }
            let offset = readU32Leb128()
            let index = readU32Leb128()
            let addend: UInt32
            switch type {
            case .memoryAddressLEB,
                 .memoryAddressSLEB,
                 .memoryAddressI32:
                addend = readS32Leb128()
            default:
                addend = 0
            }
            delegate.onReloc(type, offset, index, addend)
        }
    }
}
