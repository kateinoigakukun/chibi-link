class OutputCodeSection: OutputVectorSection {
    var section: SectionCode { .code }
    var size: OutputSectionSize { .unknown }
    let count: Int
    let sections: [InputVectorSection]

    init(sections: [InputSection], symbolTable: SymbolTable) {
        var totalCount = symbolTable.synthesizedFuncs().count
        var vectorSections: [InputVectorSection] = []
        for section in sections {
            guard case let .rawVector(code, section) = section,
                code == .code
            else { preconditionFailure() }
            totalCount += section.content.count
            vectorSections.append(section)
        }

        self.sections = vectorSections
        count = totalCount
    }

    func writeVectorContent(writer: BinaryWriter, relocator: Relocator) throws {
        for synthesizedFunc in relocator.symbolTable.synthesizedFuncs() {
            try synthesizedFunc.writeCode(writer: writer, relocator: relocator)
        }
        for section in sections {
            let body = relocator.relocate(chunk: section)
            let payload = body[
                (section.sectionStart + section.content.payloadOffset - section.offset)...]
            try writer.writeBytes(payload)
        }
    }
}
