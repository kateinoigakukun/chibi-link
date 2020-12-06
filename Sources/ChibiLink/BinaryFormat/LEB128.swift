enum LEB128 {
    static let maxLength: Int = 5
}

func decodeULEB128<T>(_ bytes: ArraySlice<UInt8>, _: T.Type) -> (value: T, offset: Int)
    where T: UnsignedInteger, T: FixedWidthInteger
{
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
    where T: SignedInteger, T: FixedWidthInteger
{
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

func encodeULEB128<T>(_ value: T, padTo: Int? = nil,
                      writer: (_ offset: Int, _ value: UInt8) -> Void
) where T: UnsignedInteger, T: FixedWidthInteger {
    var value = value
    var length = 0
    var needPad: Bool {
        guard let padTo = padTo else { return false }
        return length < padTo
    }
    repeat {
        var byte = UInt8(value & 0x7F)
        value >>= 7
        let offset = length
        length += 1
        if value != 0 || needPad {
            byte |= 0x80
        }
        writer(offset, byte)
    } while value != 0

    if let padTo = padTo, length < padTo {
        while length < padTo - 1 {
            writer(length, 0x80)
            length += 1
        }
        writer(length, 0x00)
    }
}

func encodeULEB128<T>(_ value: T, padTo: Int? = nil) -> [UInt8]
    where T: UnsignedInteger, T: FixedWidthInteger
{
    var results: [UInt8] = []
    encodeULEB128(value, padTo: padTo, writer: { results.append($1) })
    return results
}

func encodeSLEB128<T>(
    _ value: T, padTo: Int? = nil,
    writer: (_ offset: Int, _ value: UInt8) -> Void
) where T: SignedInteger, T: FixedWidthInteger {
    var value = value
    var length = 0
    var hasMore: Bool
    var needPad: Bool {
        guard let padTo = padTo else { return false }
        return length < padTo
    }
    repeat {
        var byte = UInt8(value & 0x7F)
        value >>= 7
        let offset = length
        length += 1
        hasMore = !(
            (value == 0 && (byte & 0x40) == 0) ||
                (value == -1 && (byte & 0x40) != 0)
        )
        if hasMore || needPad {
            byte |= 0x80
        }
        writer(offset, byte)
    } while hasMore

    if let padTo = padTo, length < padTo {
        let padValue: UInt8 = value < 0 ? 0x7F : 0x00
        while length < padTo - 1 {
            writer(length, padValue | 0x80)
            length += 1
        }
        writer(length, padValue)
    }
}

func encodeSLEB128<T>(_ value: T, padTo: Int? = nil) -> [UInt8]
    where T: SignedInteger, T: FixedWidthInteger
{
    var results: [UInt8] = []
    encodeSLEB128(value, padTo: padTo, writer: { results.append($1) })
    return results
}
