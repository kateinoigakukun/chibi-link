class Linker {
    private var inputs: [InputBinary] = []

    func append(_ binary: InputBinary) {
        inputs.append(binary)
    }

    struct ExportInfo {
        let export: Export
        let binary: InputBinary
    }

    func resolveSymbols() {
        var exportList: [ExportInfo] = []
        var exportIndexMap: [String: Int] = [:]
        for binary in inputs {
            for export in binary.exports {
                let info = ExportInfo(export: export, binary: binary)
                exportList.append(info)
                // TODO: Diagnose if same name export exists and
                // has different module
                exportIndexMap[export.name] = exportList.count - 1
            }
        }

        for binary in inputs {
            for funcImport in binary.funcImports {
                guard let exportIndex = exportIndexMap[funcImport.field] else {
                    print("Warning: undefined symbol: \(funcImport.field)")
                    continue
                }

                let info = exportList[exportIndex]
                funcImport.unresolved = false
                funcImport.foreignBinary = info.binary
                funcImport.foreignIndex = info.export.index
                binary.unresolvedFunctionImportsCount -= 1
            }
        }
    }

    func calculateRelocOffsets() {
        var memoryPageOffset: Offset = 0
        var tableElementCount: Int = 0
        var totalFunctionImports: Int = 0
        var totalGlobalImports: Int = 0

        typealias PartialOffsetSet = (
            importedFunctionIndexOffset: Offset,
            importedGlobalindexOffset: Offset,
            memoryPageOffset: Offset,
            tableIndexOffset: Offset
        )
        var partialOffsets: [PartialOffsetSet] = []

        for binary in inputs {
            let offsetSet: PartialOffsetSet = (
                importedFunctionIndexOffset: totalFunctionImports,
                importedGlobalindexOffset: totalGlobalImports,
                memoryPageOffset: memoryPageOffset,
                tableIndexOffset: tableElementCount
            )
            partialOffsets.append(offsetSet)

            var resolvedCount: Size = 0
            for (idx, funcImport) in binary.funcImports.enumerated() {
                if !funcImport.unresolved {
                    // when resolved
                    resolvedCount += 1
                } else {
                    funcImport.relocatedFunctionIndex = totalFunctionImports + idx - resolvedCount
                }
            }

            memoryPageOffset += binary.memoryPageCount
            totalFunctionImports += binary.unresolvedFunctionImportsCount
            totalGlobalImports += binary.globalImports.count
            tableElementCount += binary.tableElemSize
        }

        var typeCount: Int = 0
        var globalCount: Int = 0
        var functionCount: Int = 0

        for (index, binary) in inputs.enumerated() {
            let partial = partialOffsets[index]
            let offsetSet = InputBinary.RelocOffsets(
                importedFunctionIndexOffset: partial.importedFunctionIndexOffset,
                importedGlobalindexOffset: partial.importedGlobalindexOffset,
                memoryPageOffset: partial.memoryPageOffset,
                tableIndexOffset: partial.tableIndexOffset,
                typeIndexOffset: typeCount,
                globalIndexOffset: totalGlobalImports - binary.globalImports.count + globalCount,
                functionIndexOffset: totalFunctionImports - binary.funcImports.count + functionCount
            )
            binary.relocOffsets = offsetSet
            for sec in binary.sections {
                switch sec.sectionCode {
                case .type:
                    typeCount += sec.count!
                case .global:
                    globalCount += sec.count!
                case .function:
                    functionCount += sec.count!
                default: break
                }
            }
        }
    }

    func link() {
        calculateRelocOffsets()
    }
}

func performLinker(_ filenames: [String]) throws {
    let linker = Linker()
    let symtab = SymbolTable()
    for filename in filenames {
        let bytes = try readFileContents(filename)
        let binary = InputBinary(filename: filename, data: bytes)
        let collector = LinkInfoCollector(binary: binary, symbolTable: symtab)
        let reader = BinaryReader(bytes: bytes, delegate: collector)
        try reader.readModule()
        linker.append(binary)
    }
}
