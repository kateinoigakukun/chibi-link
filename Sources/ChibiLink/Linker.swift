public func performLinker(_ filenames: [String], output: String, exports: [String] = []) throws {
    let symtab = SymbolTable()
    var inputs: [InputBinary] = []
    for filename in filenames {
        let bytes = try readFileContents(filename)
        let binary = InputBinary(filename: filename, data: bytes)
        let collector = LinkInfoCollector(binary: binary, symbolTable: symtab)
        let reader = BinaryReader(bytes: bytes, delegate: collector)
        try reader.readModule()
        inputs.append(binary)
    }
    let stream = FileOutputByteStream(path: output)
    let writer = OutputWriter(stream: stream, symbolTable: symtab, inputs: inputs, exportSymbols: exports)
    try writer.writeBinary()
}
