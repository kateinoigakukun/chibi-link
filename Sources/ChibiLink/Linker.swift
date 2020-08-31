class Linker {
    private var inputs: [InputBinary] = []

    func append(_ binary: InputBinary) {
        inputs.append(binary)
    }

    func calculateRelocOffsets() {}

    func link() {}
}

func performLinker(_ filenames: [String]) throws {
    let linker = Linker()
    for filename in filenames {
        let bytes = try readFileContents(filename)
        let binary = InputBinary(filename: filename, data: bytes)
        let collector = LinkInfoCollector(binary: binary)
        let reader = BinaryReader(bytes: bytes, delegate: collector)
        try reader.readModule()
        linker.append(binary)
    }
}
