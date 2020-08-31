class Linker {
    private var inputs: [InputBinary] = []

    func append(_ binary: InputBinary) {
        inputs.append(binary)
    }

    func calculateRelocOffsets() {
        var memoryPageOffset: Offset = 0
        var typeCount: Int = 0
        var globalCount: Int = 0
        var functionCount: Int = 0
        var tableElementCount: Int = 0
        var totalFunctionImports: Int = 0
        var totalGlobalImports: Int = 0
        
        for binary in inputs {
            let offsets = InputBinary.RelocOffsets(
                importedFunctionIndexOffset: totalFunctionImports,
                importedGlobalindexOffset: totalGlobalImports,
                memoryPageOffset: memoryPageOffset
            )
            binary.relocOffsets = offsets
            
            var resolvedCount: Size = 0
            for (idx, funcImport) in binary.funcImports.enumerated() {
                if funcImport.active {
                    resolvedCount += 1
                } else {
                    funcImport.relocatedFunctionIndex = totalFunctionImports + idx - resolvedCount
                }
            }
            
            memoryPageOffset += binary.memoryPageCount!
            totalFunctionImports += binary.unresolvedFunctionImportsCount
            totalGlobalImports += binary.globalImports.count
        }
        
        for binary in inputs {
            binary.relocOffsets?.tableIndexOffset = tableElementCount
            tableElementCount += binary.tableElemSize

            for sec in binary.sections {
                switch sec.sectionCode {
                case .type:
                    binary.relocOffsets?.typeIndexOffset = typeCount
                    typeCount += sec.count!
                case .global:
                    binary.relocOffsets?.globalIndexOffset = totalGlobalImports - sec.binary!.globalImports.count + globalCount
                    globalCount += sec.count!
                case .function:
                    binary.relocOffsets?.functionIndexOffset = totalFunctionImports -
                        sec.binary!.funcImports.count + functionCount
                    functionCount += sec.count!
                default: break
                }
            }
            
        }
    }

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
