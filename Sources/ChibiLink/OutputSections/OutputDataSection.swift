class OutputSegment {
    let name: String
    private(set) var alignment: Int = 1
    private(set) var size: Size = 0
    struct Chunk {
        let offset: Offset
        let segment: DataSegment
        var relocs: [Relocation]
        weak var section: InputDataSection!
    }

    private(set) var chunks: [Chunk] = []
    init(name: String) {
        self.name = name
    }

    func addInput(_ input: DataSegment, relocs: [Relocation], section: InputDataSection) {
        alignment = max(alignment, input.info.alignment)
        size = align(size, to: 1 << input.info.alignment)
        chunks.append(Chunk(offset: size, segment: input, relocs: relocs, section: section))
        size += input.size
    }
}

extension OutputSegment.Chunk: RelocatableChunk {
    var sectionStart: Offset { section.offset }
    var relocations: [Relocation] { relocs }

    var parentBinary: InputBinary { section.binary }

    var relocationRange: Range<Index> {
        return segment.data.indices
    }
}

class OutputDataSection: OutputVectorSection {
    var section: SectionCode { .data }
    var size: OutputSectionSize { .unknown }
    let count: Size

    typealias LocatedSegment = (
        segment: OutputSegment, offset: Offset
    )
    let segments: [LocatedSegment]
    let initialMemorySize: Size
    private let outputOffsetByInputSegment: [OffsetKey: Offset]
    
    private struct OffsetKey: Hashable {
        let fileID: InputBinary.ID
        let segmentIndex: Index
    }

    func startVirtualAddress(for segment: DataSegment, binary: InputBinary) -> Offset? {
        let key = OffsetKey(fileID: binary.id, segmentIndex: segment.index)
        return outputOffsetByInputSegment[key]
    }

    init(sections: [InputSection]) {
        var segmentMap: [String: OutputSegment] = [:]
        for section in sections {
            guard case let .data(section) = section else { preconditionFailure() }
            var relocs = section.relocations.sorted(by: {
                $0.offset > $1.offset
            })
            let segments = section.content.elements.sorted(by: {
                $0.offset < $1.offset
            })
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

                var segmentRelocs: [Relocation] = []
                let rangeStart = segment.data.startIndex - section.offset
                let rangeEnd = segment.data.endIndex - section.offset
                while let headReloc = relocs.last,
                      (rangeStart..<rangeEnd).contains(headReloc.offset)
                {
                    relocs.removeLast()
                    segmentRelocs.append(headReloc)
                }
                outSegment.addInput(segment, relocs: segmentRelocs, section: section)
            }
            assert(relocs.isEmpty)
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
                let key = OffsetKey(fileID: chunk.parentBinary.id, segmentIndex: chunk.segment.index)
                assert(outputOffsetByInputSegName[key] == nil)
                outputOffsetByInputSegName[key] = memoryOffset + chunk.offset
            }
            memoryOffset += segment.size
        }
        self.segments = segments
        self.outputOffsetByInputSegment = outputOffsetByInputSegName
        initialMemorySize = memoryOffset
    }

    func writeVectorContent(writer: BinaryWriter, relocator: Relocator) throws {
        for (segment, offset) in segments {
            try writer.writeDataSegment(
                segment, startOffset: offset
            ) { chunk in
                return relocator.relocate(chunk: chunk)
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
