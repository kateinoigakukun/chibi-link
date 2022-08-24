public func performLinker(
    _ filenames: [String], outputStream: OutputByteStream, exports: [String] = [],
    globalBase: Int = 1024
) throws {
    let symtab = SymbolTable()
    var inputs: [InputBinary] = []
    for filename in filenames {
        let bytes = try readFileContents(filename)
        let binary = InputBinary(id: inputs.count, filename: filename, data: bytes)
        let collector = LinkInfoCollector(binary: binary, symbolTable: symtab)
        let reader = BinaryReader(bytes: bytes, delegate: collector)
        try reader.readModule()
        inputs.append(binary)
    }
    let writer = OutputWriter(
        stream: outputStream, symbolTable: symtab, inputs: inputs, exportSymbols: exports)
    try writer.writeBinary(globalBase: globalBase)
}
