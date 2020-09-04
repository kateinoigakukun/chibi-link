class OutputSegment {
    let name: String
    private(set) var alignment: Int = 1
    private(set) var size: Size = 0
    typealias Chunk = (
        offset: Offset,
        segment: DataSegment
    )
    private(set) var chunks: [Chunk] = []
    private(set) var relocs: [Relocation] = []
    init(name: String) {
        self.name = name
    }

    func addInput(_ input: DataSegment) {
        alignment = max(alignment, input.info.alignment)
        size = align(size, to: 1 << input.info.alignment)
        chunks.append((size, input))
        size += input.size
    }

    func addReloc(_ reloc: Relocation) {
        relocs.append(reloc)
    }
}

struct DataSection: VectorSection {
    var section: BinarySection { .data }
    var size: OutputSectionSize { .unknown }
    let count: Size

    typealias LocatedSegment = (
        segment: OutputSegment, offset: Offset
    )
    let segments: [LocatedSegment]
    private let outputOffsetByInputSegName: [String: Offset]

    func startVirtualAddress(for binary: DataSegment) -> Offset? {
        return outputOffsetByInputSegName[binary.info.name]
    }

    init(sections: [Section]) {
        var segmentMap: [String: OutputSegment] = [:]
        var inputsByOutput: [String: [String]] = [:]
        for section in sections {
            var relocs = section.relocations.sorted(by: {
                $0.offset > $1.offset
            })
            let segments = section.dataSegments.sorted(by: {
                $0.offset < $1.offset
            })
            let vectorHeaderSize = section.payloadOffset! - section.offset
            for segment in segments {
                let info = segment.info!
                let inputName = info.name
                let outputName = getOutputSegmentName(inputName)
                let outSegment: OutputSegment
                if let existing = segmentMap[outputName] {
                    outSegment = existing
                } else {
                    outSegment = OutputSegment(name: outputName)
                    segmentMap[outputName] = outSegment
                }
                inputsByOutput[outputName, default: []].append(inputName)
                outSegment.addInput(segment)

                while let headReloc = relocs.last,
                    headReloc.offset <= (vectorHeaderSize + segment.offset + segment.size)
                {
                    relocs.removeLast()
                    outSegment.addReloc(headReloc)
                }
            }
        }
        count = segmentMap.count
        let segmentList = Array(segmentMap.values.sorted(by: { $0.name > $1.name }))
        var segments: [LocatedSegment] = []
        var memoryOffset: Offset = 0
        var outputOffsetByInputSegName: [String: Offset] = [:]
        for segment in segmentList {
            let inputs = inputsByOutput[segment.name]!
            for input in inputs {
                outputOffsetByInputSegName[input] = memoryOffset
            }
            memoryOffset = align(memoryOffset, to: segment.alignment)
            segments.append((segment, memoryOffset))
            memoryOffset += segment.size
        }
        self.segments = segments
        self.outputOffsetByInputSegName = outputOffsetByInputSegName
    }

    func writeVectorContent(writer: BinaryWriter, relocator _: Relocator) throws {
        for (segment, offset) in segments {
            try writer.writeDataSegment(
                segment, startOffset: offset
            ) { chunk in
                Array(chunk)
//                relocator.relocate(section: <#T##Section#>)
            }
        }
    }
}

private func getOutputSegmentName(_ name: String) -> String {
    if name.hasPrefix(".tdata") || name.hasPrefix(".tbss") {
        return ".tdata"
    }
    if name.hasPrefix(".text.") {
        return ".text"
    }
    if name.hasPrefix(".data.") {
        return ".data"
    }
    if name.hasPrefix(".bss.") {
        return ".bss"
    }
    if name.hasPrefix(".rodata.") {
        return ".rodata"
    }
    return name
}
