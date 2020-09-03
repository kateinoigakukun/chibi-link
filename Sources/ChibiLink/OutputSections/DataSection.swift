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

    private let segments: [OutputSegment]

    init(sections: [Section]) {
        var totalCount: Int = 0
        var segmentMap: [String: OutputSegment] = [:]
        for segment in sections.lazy.flatMap(\.dataSegments) {
            let info = segment.info!
            let outSegment: OutputSegment
            if let existing = segmentMap[info.name] {
                outSegment = existing
            } else {
                outSegment = OutputSegment(name: info.name)
                segmentMap[info.name] = outSegment
            }

            outSegment.addInput(segment)
            totalCount += 1
        }
        count = totalCount
        segments = Array(segmentMap.values.sorted(by: { $0.name > $1.name }))
    }

    func writeVectorContent(writer: BinaryWriter) throws {
        var memoryOffset: Offset = 0
        for segment in segments {
            memoryOffset = align(memoryOffset, to: segment.alignment)
            try writer.writeDataSegment(
                segment, startOffset: memoryOffset
            )
            memoryOffset += segment.size
        }
    }
}
