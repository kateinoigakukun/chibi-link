class OutputSegment {
    let name: String
    private(set) var alignment: Int = 1
    private(set) var size: Size = 0
    struct Chunk {
        let offset: Offset
        let segment: DataSegment
        var relocs: [Relocation]
        weak var section: Section!
    }

    private(set) var chunks: [Chunk] = []
    init(name: String) {
        self.name = name
    }

    func addInput(_ input: DataSegment, relocs: [Relocation], section: Section) {
        alignment = max(alignment, input.info.alignment)
        size = align(size, to: 1 << input.info.alignment)
        chunks.append(Chunk(offset: size, segment: input, relocs: relocs, section: section))
        size += input.size
    }
}

extension OutputSegment.Chunk: RelocatableChunk {
    var relocations: [Relocation] { relocs }

    var parentBinary: InputBinary { section.parentBinary }

    var relocationRange: Range<Index> {
        section.relocationRange
    }
}

class DataSection: VectorSection {
    var section: BinarySection { .data }
    var size: OutputSectionSize { .unknown }
    let count: Size

    typealias LocatedSegment = (
        segment: OutputSegment, offset: Offset
    )
    let segments: [LocatedSegment]
    let initialMemorySize: Size
    private let outputOffsetByInputSegName: [OffsetKey: Offset]
    
    private struct OffsetKey: Hashable {
        let filename: String
        let name: String
    }

    func startVirtualAddress(for segment: DataSegment, binary: InputBinary) -> Offset? {
        let key = OffsetKey(filename: binary.filename, name: segment.info.name)
        return outputOffsetByInputSegName[key]
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
//                inputsByOutput[outputName, default: []].append(inputName)

                var segmentRelocs: [Relocation] = []
                while let headReloc = relocs.last,
                    headReloc.offset <= (vectorHeaderSize + segment.offset + segment.size)
                {
                    relocs.removeLast()
                    segmentRelocs.append(headReloc)
                }
                outSegment.addInput(segment, relocs: segmentRelocs, section: section)
            }
        }
        count = segmentMap.count
        let segmentList = Array(segmentMap.values.sorted(by: { $0.name > $1.name }))
        var segments: [LocatedSegment] = []
        var memoryOffset: Offset = 0
        var outputOffsetByInputSegName: [OffsetKey: Offset] = [:]
        for segment in segmentList {
            memoryOffset = align(memoryOffset, to: segment.alignment)
            segments.append((segment, memoryOffset))

            for chunk in segment.chunks {
                if chunk.segment.info.name == ".rodata..L.str" {
                    print("Debug: Hit Breakpoint")
                }
                let key = OffsetKey(filename: chunk.parentBinary.filename, name: chunk.segment.info.name)
                assert(outputOffsetByInputSegName[key] == nil)
                outputOffsetByInputSegName[key] = memoryOffset + chunk.offset
            }
            memoryOffset += segment.size
        }
        self.segments = segments
        self.outputOffsetByInputSegName = outputOffsetByInputSegName
        initialMemorySize = memoryOffset
    }

    func writeVectorContent(writer: BinaryWriter, relocator: Relocator) throws {
        for (segment, offset) in segments {
            try writer.writeDataSegment(
                segment, startOffset: offset
            ) { chunk in
                let section = relocator.relocate(chunk: chunk)
                // FIXME
                let offset = chunk.segment.data.startIndex - chunk.section.offset
                return Array(section[offset ..< offset + chunk.segment.size])
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
