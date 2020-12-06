class DataSegment {
    let index: Index
    let memoryIndex: Index
    var offset: Offset!
    var size: Size!
    var info: Info!
    var data: ArraySlice<UInt8>!

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
