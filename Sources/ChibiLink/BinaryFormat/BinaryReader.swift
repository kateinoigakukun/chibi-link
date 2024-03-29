protocol BinaryReaderDelegate {
    func setState(_ state: BinaryReaderState)
    func beginSection(_ section: SectionCode, size: Size)
    func onImportFunc(
        _ importIndex: Index,
        _ module: String, _ field: String,
        _ funcIndex: Index,
        _ signatureIndex: Index
    )

    func onImportGlobal(
        _ importIndex: Index,
        _ module: String, _ field: String,
        _ globalIndex: Index,
        _ type: ValueType, _ mutable: Bool
    )

    func onImportTable(
        _ importIndex: Index,
        _ module: String, _ field: String,
        _ tableIndex: Index
    )

    func onFunctionCount(_ count: Int)

    func onMemory(_ memoryIndex: Index, _ pageLimits: Limits)
    func onExport(
        _ exportIndex: Index, _ kind: ExternalKind,
        _ itemIndex: Index, _ name: String)
    func onElementSegmentFunctionIndexCount(_ segmentIndex: Index, _ indexCount: Int)

    func beginDataSegment(_ segmentIndex: Index, _ memoryIndex: Index)
    func onDataSegmentData(_ segmentIndex: Index, _ dataRange: Range<Int>)

    func beginNamesSection(_ size: Size)
    func onFunctionName(_ index: Index, _ name: String)

    func onRelocCount(_ relocsCount: Int, _ sectionIndex: Index)

    func onReloc(
        _ type: RelocType, _ offset: Offset,
        _ index: Index, _ addend: Int32)

    func onInitExprI32ConstExpr(_ segmentIndex: Index, _ value: UInt32)

    func onFunctionSymbol(_ index: Index, _ flags: UInt32, _ name: String?, _ itemIndex: Index) throws
    func onGlobalSymbol(_ index: Index, _ flags: UInt32, _ name: String?, _ itemIndex: Index) throws
    func onDataSymbol(
        _ index: Index, _ flags: UInt32, _ name: String,
        _ content: (segmentIndex: Index, offset: Offset, size: Size)?
    ) throws
    func onTableSymbol(_ index: Index, _ flags: UInt32, _ name: String?, _ itemIndex: Index) throws
    func onUnknownSymbol(_ index: Index, _ flags: UInt32) throws
    func onSegmentInfo(
        _ index: Index, _ name: String,
        _ alignment: Int, _ flags: UInt32)
    func onInitFunction(_ initSymbol: Index, _ priority: UInt32)
}

class BinaryReaderState {
    fileprivate(set) var offset: Offset = 0
    let bytes: [UInt8]

    init(bytes: [UInt8]) {
        self.bytes = bytes
    }
}

class BinaryReader<Delegate: BinaryReaderDelegate> {
    enum Error: Swift.Error {
        case invalidSectionCode(UInt8)
        case invalidElementType(UInt8)
        case invalidValueType(UInt8)
        case invalidExternalKind(UInt8)
        case invalidRelocType(UInt8)
        case expectConstOpcode(UInt8)
        case expectI32Const(ConstOpcode)
        case expectEnd
        case unsupportedImportKind(ExternalKind)
        case invalidImportKind(UInt8)
        case invalidSymbolType(UInt8)
    }

    typealias State = BinaryReaderState
    let length: Int
    let state: State
    var delegate: Delegate

    var funcImportCount = 0
    var tableImportCount = 0
    var memoryImportCount = 0
    var globalImportCount = 0
    var sectionEnd: Int!

    init(bytes: [UInt8], delegate: Delegate) {
        length = bytes.count
        state = State(bytes: bytes)
        self.delegate = delegate
        delegate.setState(state)
    }

    // MARK: - Reader Utilities

    @discardableResult
    func read(_ length: Int) -> ArraySlice<UInt8> {
        let result = state.bytes[state.offset..<state.offset + length]
        state.offset += length
        return result
    }

    func readU8Fixed() -> UInt8 {
        let byte = state.bytes[state.offset]
        state.offset += 1
        return byte
    }

    func readU32Leb128() -> UInt32 {
        let (value, advanced) = decodeULEB128(state.bytes[state.offset...], UInt32.self)
        state.offset += advanced
        return value
    }

    func readS32Leb128() -> Int32 {
        let (value, advanced) = decodeSLEB128(state.bytes[state.offset...], Int32.self)
        state.offset += advanced
        return value
    }

    func readString() -> String {
        let length = Int(readU32Leb128())
        let bytes = state.bytes[state.offset..<state.offset + length]
        let name = String(decoding: bytes, as: Unicode.UTF8.self)
        state.offset += length
        return name
    }

    func readIndex() -> Index { Index(readU32Leb128()) }
    func readOffset() -> Offset { Offset(readU32Leb128()) }

    func readTable() throws -> (type: ElementType, limits: Limits) {
        let rawType = readU8Fixed()
        guard let elementType = ElementType(rawValue: rawType) else {
            throw Error.invalidElementType(rawType)
        }
        let hasMax = readU8Fixed() != 0
        let initial = Size(readU32Leb128())
        let max = hasMax ? Size(readU32Leb128()) : nil
        return (elementType, Limits(initial: initial, max: max, isShared: false))
    }

    func readMemory() throws -> Limits {
        let flags = readU8Fixed()
        let hasMax = (flags & LIMITS_HAS_MAX_FLAG) != 0
        let isShared = (flags & LIMITS_IS_SHARED_FLAG) != 0
        let initial = Size(readU32Leb128())
        let max = hasMax ? Size(readU32Leb128()) : nil
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

    func readI32InitExpr(segmentIndex: Index) throws {
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
            opcode == .end
        else {
            throw Error.expectEnd
        }
    }

    func readBytes() -> (data: ArraySlice<UInt8>, size: Size) {
        let size = Size(readU32Leb128())
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
            let size = Size(readU32Leb128())
            guard let section = SectionCode(rawValue: sectionCode) else {
                throw Error.invalidSectionCode(sectionCode)
            }
            sectionEnd = state.offset + size
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
            case .data:
                try readDataSection(sectionSize: size)
            case .type, .dataCount, .code:
                // Don't parse contents
                break
            default:
                warning("Section '\(section)' is currently not supported")
            }

            state.offset = sectionEnd
        }
    }

    func readFunctionSection(sectionSize _: Size) throws {
        let functionCount = Int(readU32Leb128())
        delegate.onFunctionCount(functionCount)
        // skip contents
    }

    func readImportSection(sectionSize _: Size) throws {
        let importCount = Int(readU32Leb128())
        for importIdx in 0..<importCount {
            let module = readString()
            let field = readString()
            let rawKind = readU8Fixed()
            let kind = ExternalKind(rawValue: rawKind)
            switch kind {
            case .func:
                let signagureIdx = readIndex()
                delegate.onImportFunc(
                    importIdx,
                    module, field,
                    funcImportCount,
                    signagureIdx
                )
                funcImportCount += 1
            case .table:
                _ = try readTable()
                delegate.onImportTable(
                    importIdx,
                    module, field,
                    tableImportCount
                )
                tableImportCount += 1
            case .memory:
                _ = try readMemory()
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
                    throw Error.unsupportedImportKind(kind)
                } else {
                    throw Error.invalidImportKind(rawKind)
                }
            }
        }
    }

    func readTableSection(sectionSize _: Size) throws {
        let tablesCount = Int(readU32Leb128())
        assert(tablesCount <= 1)
        for _ in 0..<tablesCount {
            _ = try readTable()
        }
    }

    func readMemorySection(sectionSize _: Size) throws {
        let memoriesCount = Int(readU32Leb128())
        assert(memoriesCount <= 1)
        for i in 0..<memoriesCount {
            let memoryIdx: Index = memoryImportCount + i
            let limits = try readMemory()
            delegate.onMemory(memoryIdx, limits)
        }
    }

    func readExportSection(sectionSize _: Size) throws {
        let exportsCount = Int(readU32Leb128())
        for i in 0..<exportsCount {
            let name = readString()
            let rawKind = readU8Fixed()
            guard let kind = ExternalKind(rawValue: rawKind) else {
                throw Error.invalidValueType(rawKind)
            }
            let itemIndex = readIndex()
            delegate.onExport(i, kind, itemIndex, name)
        }
    }

    func readElementSection(sectionSize _: Size) throws {
        let segmentsCount = Int(readU32Leb128())
        for i in 0..<segmentsCount {
            _ = readIndex()  // tableIndex
            try readI32InitExpr(segmentIndex: i)
            let funcIndicesCount = Int(readU32Leb128())
            delegate.onElementSegmentFunctionIndexCount(i, funcIndicesCount)
            for _ in 0..<funcIndicesCount {
                _ = readIndex()  // funcIdx
            }
        }
    }

    func readDataSection(sectionSize _: Size) throws {
        // BeginDataSection
        let segmentsCount = Int(readU32Leb128())
        // OnDataSegmentCount
        for i in 0..<segmentsCount {
            let memoryIndex = readIndex()
            delegate.beginDataSegment(i, memoryIndex)
            // BeginDataSegmentInitExpr
            try readI32InitExpr(segmentIndex: i)
            // EndDataSegmentInitExpr
            let size = Size(readU32Leb128())
            let range = state.offset..<state.offset + size
            state.offset += size
            delegate.onDataSegmentData(i, range)
            // EndDataSegment
        }
        // EndDataSection
    }

    func readCustomSection(sectionSize: Size) throws {
        let sectionName = readString()
        // BeginCustomSection
        switch sectionName {
        case "name":
            try readNameSection(sectionSize: sectionSize)
        case "linking":
            try readLinkingSection(sectionSize: sectionSize)
        case _
        where sectionName.hasPrefix("reloc.")
            && !sectionName.hasPrefix("reloc..debug_"):
            try readRelocSection(sectionSize: sectionSize)
        default:
            warning("Custom section '\(sectionName)' is currently not supported")
        }
    }

    func readNameSection(sectionSize: Size) throws {
        delegate.beginNamesSection(sectionSize)

        while state.offset < sectionEnd {
            let subsectionType = readU8Fixed()
            let subsectionSize = Size(readU32Leb128())
            let subsectionEnd = state.offset + subsectionSize

            switch NameSectionSubsection(rawValue: subsectionType) {
            case .function:
                // OnFunctionNameSubsection
                let namesCount = readU32Leb128()
                for _ in 0..<namesCount {
                    let funcIdx = readIndex()
                    let funcName = readString()
                    delegate.onFunctionName(funcIdx, funcName)
                }
            default:
                // Skip
                state.offset = subsectionEnd
            }
        }
    }

    func readRelocSection(sectionSize _: Size) throws {
        let sectionIndex = readIndex()
        let relocsCount = Int(readU32Leb128())
        delegate.onRelocCount(relocsCount, sectionIndex)

        for _ in 0..<relocsCount {
            let rawType = readU8Fixed()
            guard let type = RelocType(rawValue: rawType) else {
                throw Error.invalidRelocType(rawType)
            }
            let offset = readOffset()
            let index = readIndex()
            let addend: Int32
            switch type {
            case .MEMORY_ADDR_LEB,
                .MEMORY_ADDR_SLEB,
                .MEMORY_ADDR_I32:
                addend = readS32Leb128()
            default:
                addend = 0
            }
            delegate.onReloc(type, offset, index, addend)
        }
    }

    func readLinkingSection(sectionSize _: Size) throws {
        // BeginLinkingSection
        let version = readU32Leb128()
        assert(version == 2)
        while state.offset < sectionEnd {
            let linkingTypeCode = readU8Fixed()
            let linkingType = LinkingEntryType(rawValue: linkingTypeCode)
            let subSectionSize = readOffset()
            let subSectionEnd = state.offset + subSectionSize

            switch linkingType {
            case .symbolTable:
                try readSymbolTable()
            case .segmentInfo:
                readSegmentInfo()
            case .initFunctions:
                readInitFunctions()
            default:
                if let linkingType = linkingType {
                    warning(
                        "Linking subsection '\(String(describing: linkingType))' is not supported now"
                    )
                } else {
                    warning(
                        "Linking subsection unknown code '\(linkingTypeCode)' is not supported now")
                }
                state.offset = subSectionEnd
            }
        }
    }

    func readSymbolTable() throws {
        let count = Int(readU32Leb128())
        for i in 0..<count {
            let symTypeCode = readU8Fixed()
            let symFlags = readU32Leb128()
            guard let symType = SymbolType(rawValue: symTypeCode) else {
                throw Error.invalidSymbolType(symTypeCode)
            }
            let binding = symFlags & SYMBOL_BINDING_MASK

            switch symType {
            case .function, .global, .event, .table:
                let itemIndex = Index(readU32Leb128())
                var name: String?
                let isDefined = symFlags & SYMBOL_FLAG_UNDEFINED == 0
                let isExplicit = symFlags & SYMBOL_EXPLICIT_NAME != 0
                if isDefined || isExplicit {
                    name = readString()
                }
                switch symType {
                case .function:
                    try delegate.onFunctionSymbol(i, symFlags, name, itemIndex)
                case .global:
                    try delegate.onGlobalSymbol(i, symFlags, name, itemIndex)
                case .table:
                    try delegate.onTableSymbol(i, symFlags, name, itemIndex)
                default:
                    throw Error.invalidSymbolType(symType.rawValue)
                }
            case .data:
                let name = readString()
                var content: (segmentIndex: Index, offset: Offset, size: Size)?
                if symFlags & SYMBOL_FLAG_UNDEFINED == 0 {
                    content = (
                        Index(readU32Leb128()),
                        Offset(readU32Leb128()),
                        Size(readU32Leb128())
                    )
                }
                try delegate.onDataSymbol(i, symFlags, name, content)
            case .section:
                if binding != SYMBOL_BINDING_LOCAL {
                    warning("\(binding) is expected to be SYMBOL_BINDING_LOCAL")
                }
                _ = readU32Leb128()  // section index
                try delegate.onUnknownSymbol(i, symFlags)
            }
        }
    }

    func readSegmentInfo() {
        let count = Int(readU32Leb128())
        for i in 0..<count {
            let name = readString()
            let alignment = readU32Leb128()
            let flags = readU32Leb128()
            delegate.onSegmentInfo(i, name, Int(alignment), flags)
        }
    }

    func readInitFunctions() {
        let count = Int(readU32Leb128())
        for _ in 0..<count {
            let priority = readU32Leb128()
            let symbolIndex = readIndex()
            delegate.onInitFunction(symbolIndex, priority)
        }
    }
}
