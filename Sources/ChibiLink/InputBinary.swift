class Section {}

class LinkerInputBinary {
    let filename: String
    let data: [UInt8]

    fileprivate var sections: [Section] = []

    init(filename: String, data: [UInt8]) {
        self.filename = filename
        self.data = data
    }
}

class LinkInfoReader {}
