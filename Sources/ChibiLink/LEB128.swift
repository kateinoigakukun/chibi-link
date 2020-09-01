func decodeULEB128<T>(_ bytes: ArraySlice<UInt8>, _: T.Type) -> (value: T, offset: Int)
    where T: UnsignedInteger, T: FixedWidthInteger {
    var index: Int = bytes.startIndex
    var value: T = 0
    var shift: UInt = 0
    var byte: UInt8
    repeat {
        byte = bytes[index]
        index += 1
        value |= T(byte & 0x7F) << shift
        shift += 7
    } while byte >= 128
    return (value, index - bytes.startIndex)
}

func decodeSLEB128<T>(_ bytes: ArraySlice<UInt8>, _: T.Type) -> (value: T, offset: Int)
    where T: SignedInteger, T: FixedWidthInteger{
    var index: Int = bytes.startIndex
    var value: T = 0
    var shift: UInt = 0
    var byte: UInt8
    repeat {
        byte = bytes[index]
        index += 1
        value |= T(byte & 0x7F) << shift
        shift += 7
    } while byte >= 128
    if byte & 0x40 != 0 {
        value |= T(-1) << shift
    }
    return (value, index - bytes.startIndex)
}
