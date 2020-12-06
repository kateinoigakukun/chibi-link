class DataSegment {
    let index: Index
    let memoryIndex: Index
    var offset: Offset!
    var info: Info!
    var dataRange: Range<Int>!

    struct Info {
        let name: String
        let alignment: Int
        let flags: UInt32
    }

    internal init(index: Index, memoryIndex: Index) {
        self.index = index
        self.memoryIndex = memoryIndex
    }
}

typealias InputDataSection = GenericInputSection<InputVectorContent<DataSegment>>
