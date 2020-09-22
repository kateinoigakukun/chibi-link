class DataSegment {
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

    internal init(memoryIndex: Index) {
        self.memoryIndex = memoryIndex
    }
}

typealias InputDataSection = GenericInputSection<InputVectorContent<DataSegment>>
