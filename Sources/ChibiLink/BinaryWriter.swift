
class BinaryWriter {
    let stream: OutputByteStream
    init(stream: OutputByteStream) {
        self.stream = stream
    }
    func writeHeader() throws {
        try stream.write(magic[...])
        try stream.write(version[...])
    }
    
    func writeFixedU32Leb128() {
        
    }

    struct Placeholder<Value> {
        fileprivate let offset: Offset
    }
    
    // FIXME: Create LEB128 type
    func writeSizePlaceholder() -> Placeholder<Size> {
        let offset = stream.offset
        let placeholder = Placeholder<Size>(offset: offset)
        return placeholder
    }
    func fillSizePlaceholder(_ placeholder: Placeholder<Size>, value: Size) {
        
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

        var sections: [BinarySection: [Section]] = [:]
        for binary in inputs {
            for sec in binary.sections {
                sections[sec.sectionCode, default: []].append(sec)
            }
        }
    }

    func writeCombinedSection(_ section: BinarySection, _ sections: [Section]) {
        guard !sections.isEmpty else { return }
        switch section {
        case .import:
            break
        default:
            fatalError("Error: Section '\(section)' is not yet supported to write out as combined section")
        }
    }

    func writeImportSection() {
        var importsCount = 0
        for binary in inputs {
            for funcImport in binary.funcImports {
                if funcImport.unresolved {
                    importsCount += 1
                }
            }
            importsCount += binary.globalImports.count
        }
        
        
    }

}
