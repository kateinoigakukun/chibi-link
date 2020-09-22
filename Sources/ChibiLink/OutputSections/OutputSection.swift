enum OutputSectionSize {
    case fixed(Size)
    case unknown
}

protocol OutputSection {
    var section: BinarySection { get }
    var size: OutputSectionSize { get }
    func write(writer: BinaryWriter, relocator: Relocator) throws
    func writeContent(writer: BinaryWriter, relocator: Relocator) throws
}

extension OutputSection {
    func write(writer: BinaryWriter, relocator: Relocator) throws {
        try writer.writeSectionCode(section)
        switch size {
        case let .fixed(size):
            try writer.writeULEB128(UInt32(size))
            try writeContent(writer: writer, relocator: relocator)
        case .unknown:
            let placeholder = try writer.writeSizePlaceholder()
            let contentStart = writer.offset
            try writeContent(writer: writer, relocator: relocator)
            let contentSize = writer.offset - contentStart
            try writer.fillSizePlaceholder(placeholder, value: contentSize)
        }
    }
}

protocol OutputVectorSection: OutputSection {
    var count: Int { get }
    func writeVectorContent(writer: BinaryWriter, relocator: Relocator) throws
}

extension OutputVectorSection {
    func writeContent(writer: BinaryWriter, relocator: Relocator) throws {
        try writer.writeULEB128(UInt32(count))
        try writeVectorContent(writer: writer, relocator: relocator)
    }
}

protocol OutputCustomSection: OutputSection {
    var name: String { get }
    func writeCustomContent(writer: BinaryWriter, relocator: Relocator) throws
}

extension OutputCustomSection {
    func writeContent(writer: BinaryWriter, relocator: Relocator) throws {
        try writer.writeString(name)
        try writeCustomContent(writer: writer, relocator: relocator)
    }
}
