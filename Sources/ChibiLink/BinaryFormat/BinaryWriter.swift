
class BinaryWriter {
    private let stream: OutputByteStream
    var offset: Offset { stream.currentOffset }
    init(stream: OutputByteStream) {
        self.stream = stream
    }

    // MARK: - Utilities

    struct Placeholder<Value> {
        fileprivate let offset: Offset
    }

    func writeSizePlaceholder() throws -> Placeholder<Size> {
        let offset = stream.currentOffset
        let placeholder = Placeholder<Size>(offset: offset)
        let dummyBytes = encodeULEB128(0 as UInt, padTo: LEB128.maxLength)
        try stream.write(dummyBytes)
        return placeholder
    }

    func fillSizePlaceholder(_ placeholder: Placeholder<Size>, value: Size) throws {
        let bytes = encodeULEB128(UInt32(value), padTo: LEB128.maxLength)
        try stream.write(bytes, at: placeholder.offset)
    }

    func writeIndex(_ index: Index) throws {
        try writeULEB128(UInt32(index))
    }

    func writeFixedUInt8(_ value: UInt8) throws {
        try stream.write([value])
    }

    func writeULEB128<T>(_ value: T) throws
        where T: UnsignedInteger, T: FixedWidthInteger
    {
        let bytes = encodeULEB128(value)
        try stream.write(bytes)
    }

    func writeSLEB128<T>(_ value: T) throws
        where T: SignedInteger, T: FixedWidthInteger
    {
        let bytes = encodeSLEB128(value)
        try stream.write(bytes)
    }

    func writeString(_ value: String) throws {
        let lengthBytes = encodeULEB128(UInt32(value.count))
        try stream.write(lengthBytes)
        try stream.writeString(value)
    }

    func writeBytes(_ bytes: ArraySlice<UInt8>) throws {
        try stream.write(bytes)
    }

    // MARK: - Wasm binary format writers

    func writeHeader() throws {
        try stream.write(magic)
        try stream.write(version)
    }

    func writeSectionCode(_ code: BinarySection) throws {
        try writeFixedUInt8(code.rawValue)
    }

    func writeImport(_ theImport: OutputImportSeciton.Import) throws {
        try writeString(theImport.module)
        try writeString(theImport.field)
        switch theImport.kind {
        case let .function(signatureIndex):
            try writeFixedUInt8(ExternalKind.func.rawValue)
            try writeULEB128(UInt32(signatureIndex))
        case let .global(type, mutable):
            try writeFixedUInt8(ExternalKind.global.rawValue)
            try writeFixedUInt8(type.rawValue)
            try writeFixedUInt8(mutable ? 0 : 1)
        }
    }

    func writeExport(_ theExport: OutputExportSection.Export) throws {
        try writeString(theExport.name)
        switch theExport.kind {
        case let .function(index):
            try writeFixedUInt8(ExternalKind.func.rawValue)
            try writeULEB128(UInt32(index))
        case let .global(index):
            try writeFixedUInt8(ExternalKind.global.rawValue)
            try writeULEB128(UInt32(index))
        case let .memory(index):
            try writeFixedUInt8(ExternalKind.memory.rawValue)
            try writeULEB128(UInt32(index))
        }
    }

    enum InitExpr {
        case i32(Int32)
    }

    func writeI32InitExpr(_ expr: InitExpr) throws {
        switch expr {
        case let .i32(value):
            try writeFixedUInt8(ConstOpcode.i32Const.rawValue)
            try writeSLEB128(value)
            try writeFixedUInt8(Opcode.end.rawValue)
        }
    }

    func writeDataSegment(_ segment: OutputSegment, startOffset: Offset, relocate: (OutputSegment.Chunk) -> [UInt8]) throws {
        try writeIndex(0) // memory index
        // TODO: i64?
        try writeI32InitExpr(.i32(Int32(startOffset)))
        try writeULEB128(UInt32(segment.size))
        let base = stream.currentOffset
        for chunk in segment.chunks {
            let written = stream.currentOffset - base
            let padding = chunk.offset - written
            let paddingBytes = [UInt8](repeating: 0, count: padding)
            try stream.write(paddingBytes)
            try stream.write(relocate(chunk))
        }
    }

    func writeTable(type: ElementType, limits: Limits) throws {
        try writeFixedUInt8(type.rawValue)
        let hasMax = limits.max != nil
        try writeFixedUInt8(hasMax ? 1 : 0)
        try writeULEB128(UInt32(limits.initial))
        if let max = limits.max {
            try writeULEB128(UInt32(max))
        }
    }
}
