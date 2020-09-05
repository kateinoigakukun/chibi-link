#if DEBUG
    class NameSection: CustomSection {
        var section: BinarySection { .custom }
        var size: OutputSectionSize { .unknown }
        var name: String { "name" }
        private let inputs: [InputBinary]
        private let funcSection: FunctionSection
        init(inputs: [InputBinary], funcSection: FunctionSection) {
            self.inputs = inputs
            self.funcSection = funcSection
        }

        func writeCustomContent(writer: BinaryWriter, relocator _: Relocator) throws {
            try writer.writeFixedUInt8(NameSectionSubsection.function.rawValue)
            let placeholder = try writer.writeSizePlaceholder()
            let contentStart = writer.offset

            let count = inputs.reduce(0) {
                $0 + $1.debugNames.dropFirst($1.funcImports.count).count
            }
            try writer.writeULEB128(UInt32(count))
            for binary in inputs {
                guard let base = funcSection.indexOffset(for: binary) else { continue }
                let names = binary.debugNames.dropFirst(binary.funcImports.count)
                for (index, name) in names.enumerated() {
                    try writer.writeIndex(base + index)
                    try writer.writeString(name)
                }
            }
            let contentSize = writer.offset - contentStart
            try writer.fillSizePlaceholder(placeholder, value: contentSize)
        }
    }

#endif
