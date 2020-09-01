
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
    func writeFixedUInt8(_ value: UInt8) throws {
        try stream.write([value])
    }
    func writeULEB128<T>(_ value: T) throws
        where T: UnsignedInteger, T: FixedWidthInteger {
        let bytes = encodeULEB128(value)
        try stream.write(bytes)
    }
    func writeString(_ value: String) throws {
        let lengthBytes = encodeULEB128(UInt32(value.count))
        try stream.write(lengthBytes)
        try stream.writeString(value)
    }

    // MARK: - Wasm binary format writers

    func writeHeader() throws {
        try stream.write(magic)
        try stream.write(version)
    }

    func writeSectionCode(_ code: BinarySection) throws {
        try writeFixedUInt8(code.rawValue)
    }

    func writeFunctionImport(_ funcImport: FunctionImport, typeIndexOffset: Offset) throws {
        try writeString(funcImport.module)
        try writeString(funcImport.field)
        try writeFixedUInt8(ExternalKind.func.rawValue)
        try writeULEB128(UInt32(funcImport.signatureIdx + typeIndexOffset))
    }
    
    
    func writeSectionPayload(_ section: Section) throws {
        let offset = section.payloadOffset!
        let bytes = section.binary!.data[offset..<offset + section.payloadSize!]
        try stream.write(bytes)
    }
}

class OutputWriter {
    let writer: BinaryWriter
    let inputs: [InputBinary]
    init(stream: OutputByteStream, inputs: [InputBinary]) {
        self.writer = BinaryWriter(stream: stream)
        self.inputs = inputs
    }

    func writeBinary() throws {
        try writer.writeHeader()

        var sectionsMap: [BinarySection: [Section]] = [:]
        for binary in inputs {
            for sec in binary.sections {
                sectionsMap[sec.sectionCode, default: []].append(sec)
            }
        }
        for section in BinarySection.allCases {
            guard let sections = sectionsMap[section] else { continue }
            try writeCombinedSection(section, sections)
        }
    }

    func writeCombinedSection(_ section: BinarySection, _ sections: [Section]) throws {
        guard !sections.isEmpty else { return }
        // FIXME: temporary
        guard section == .type || section == .import else { return }
        var totalCount: Index = 0
        var totalSize: Index = 0
        for sec in sections {
            totalCount += sec.count!
            totalSize += sec.payloadSize!
        }
        switch section {
        case .import:
            try writeImportSection()
        case .type:
            // FIXME
            try writer.writeSectionCode(.type)
            let lengthBytes = encodeULEB128(UInt32(totalCount))
            totalSize += lengthBytes.count
            try writer.writeULEB128(UInt32(totalSize))
            try writer.writeULEB128(UInt32(totalCount))
            
            for sec in sections {
                try writer.writeSectionPayload(sec)
            }
        default:
            print("Warning: Section '\(section)' is not yet supported to write out as combined section")
        }
    }

    func writeImportSection() throws {
        var importsCount = 0
        for binary in inputs {
            for funcImport in binary.funcImports {
                if funcImport.unresolved {
                    importsCount += 1
                }
            }
//            importsCount += binary.globalImports.count
        }
        try writer.writeSectionCode(.import)
        let placeholder = try writer.writeSizePlaceholder()
        let payloadStart = writer.offset
        
        try writer.writeULEB128(UInt32(importsCount))
        for binary in inputs {
            for funcImport in binary.funcImports {
                if funcImport.unresolved {
                    try writer.writeFunctionImport(
                        funcImport,
                        typeIndexOffset: binary.relocOffsets!.typeIndexOffset!
                    )
                }
            }
        }
        let payloadSize = writer.offset - payloadStart
        try writer.fillSizePlaceholder(placeholder, value: payloadSize)
    }
}
