enum OutputSectionSize {
    case fixed(Size)
    case unknown
}

protocol OutputSection {
    var section: BinarySection { get }
    var size: OutputSectionSize { get }
    func write(writer: BinaryWriter) throws
    func writeContent(writer: BinaryWriter) throws
}

extension OutputSection {
    func write(writer: BinaryWriter) throws {
        try writer.writeSectionCode(section)
        switch size {
        case let .fixed(size):
            try writer.writeULEB128(UInt32(size))
            try writeContent(writer: writer)
        case .unknown:
            let placeholder = try writer.writeSizePlaceholder()
            let contentStart = writer.offset
            try writeContent(writer: writer)
            let contentSize = writer.offset - contentStart
            try writer.fillSizePlaceholder(placeholder, value: contentSize)
        }
    }
}

protocol VectorSection: OutputSection {
    var count: Int { get }
    func writeVectorContent(writer: BinaryWriter) throws
}

extension VectorSection {
    func writeContent(writer: BinaryWriter) throws {
        try writer.writeULEB128(UInt32(count))
        try writeVectorContent(writer: writer)
    }
}
