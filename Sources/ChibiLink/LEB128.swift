func decodeLEB128(_ bytes: ArraySlice<UInt8>) -> (value: UInt32, offset: Int) {
    var index: Int = bytes.startIndex
    var value: UInt32 = 0
    var shift: UInt = 0
    var byte: UInt8
    repeat {
        byte = bytes[index]
        index += 1
        value |= UInt32(byte & 0x7F) << shift
        shift += 7
    } while byte >= 128
    return (value, index - bytes.startIndex)
}

func decodeSLEB128(_ bytes: ArraySlice<UInt8>) -> (value: UInt32, offset: Int) {
    var index: Int = bytes.startIndex
    var value: UInt32 = 0
    var shift: UInt = 0
    var byte: UInt8
    repeat {
        byte = bytes[index]
        index += 1
        value |= UInt32(byte & 0x7F) << shift
        shift += 7
    } while byte >= 128
    if byte & 0x40 != 0 {
        value |= UInt32(bitPattern: -1) << shift
    }
    return (value, index - bytes.startIndex)
}
