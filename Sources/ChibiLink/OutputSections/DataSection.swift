class OutputSegment {
    let name: String
    private(set) var alignment: Int = 1
    private(set) var size: Size = 0
    typealias Chunk = (
        offset: Offset,
        segment: DataSegment
    )
    private(set) var chunks: [Chunk] = []
    init(name: String) {
        self.name = name
    }

    func addInput(_ input: DataSegment) {
        alignment = max(alignment, input.info.alignment)
        size = align(size, to: 1 << input.info.alignment)
        chunks.append((size, input))
        size += input.size
    }
}

struct DataSection: VectorSection {
    var section: BinarySection { .data }
    var size: OutputSectionSize { .unknown }
    let count: Size

    typealias LocatedSegment = (
        segment: OutputSegment, offset: Offset
    )
    private let segments: [LocatedSegment]
    private let outputOffsetByInputSegName: [String: Offset]

    func startVirtualAddress(for binary: DataSegment) -> Offset? {
        return outputOffsetByInputSegName[binary.info.name]
    }

    init(sections: [Section]) {
        var totalCount: Int = 0
        var segmentMap: [String: OutputSegment] = [:]
        var inputsByOutput: [String: [String]] = [:]
        for segment in sections.lazy.flatMap(\.dataSegments) {
            let info = segment.info!
            let inputName = info.name
            let outputName = getOutputSegmentName(inputName)
            let outSegment: OutputSegment
            if let existing = segmentMap[outputName] {
                outSegment = existing
            } else {
                outSegment = OutputSegment(name: outputName)
                segmentMap[info.name] = outSegment
            }
            inputsByOutput[outputName, default: []].append(inputName)
            outSegment.addInput(segment)
            totalCount += 1
        }
        count = totalCount
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

    func writeVectorContent(writer: BinaryWriter) throws {
        for (segment, offset) in segments {
            try writer.writeDataSegment(
                segment, startOffset: offset
            )
        }
    }
}

fileprivate func getOutputSegmentName(_ name: String) -> String {
    if (name.hasPrefix(".tdata") || name.hasPrefix(".tbss")) {
        return ".tdata"
    }
    if (name.hasPrefix(".text.")) {
        return ".text"
    }
    if (name.hasPrefix(".data.")) {
        return ".data"
    }
    if (name.hasPrefix(".bss.")) {
        return ".bss"
    }
    if (name.hasPrefix(".rodata.")) {
        return ".rodata"
    }
    return name
}
