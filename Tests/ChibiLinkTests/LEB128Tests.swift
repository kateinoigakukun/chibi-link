@testable import ChibiLink
import XCTest

class LEB128Tests: XCTestCase {
    func testDecodeULEB128() {
        func EXPECT_DECODE_ULEB128_EQ<T>(
            _ expected: T, _ value: [UInt8],
            file: StaticString = #filePath, line: UInt = #line
        ) where T: UnsignedInteger, T: FixedWidthInteger {
            XCTAssertEqual(decodeULEB128(value[...], T.self).value, expected, file: file, line: line)
        }
        EXPECT_DECODE_ULEB128_EQ(0 as UInt32, [0x00])
        EXPECT_DECODE_ULEB128_EQ(1 as UInt32, [0x01])
        EXPECT_DECODE_ULEB128_EQ(63 as UInt32, [0x3F])
        EXPECT_DECODE_ULEB128_EQ(64 as UInt32, [0x40])
        EXPECT_DECODE_ULEB128_EQ(0x7F as UInt32, [0x7F])
        EXPECT_DECODE_ULEB128_EQ(0x80 as UInt32, [0x80, 0x01])
        EXPECT_DECODE_ULEB128_EQ(0x81 as UInt32, [0x81, 0x01])
        EXPECT_DECODE_ULEB128_EQ(0x90 as UInt32, [0x90, 0x01])
        EXPECT_DECODE_ULEB128_EQ(0xFF as UInt32, [0xFF, 0x01])
        EXPECT_DECODE_ULEB128_EQ(0x100 as UInt32, [0x80, 0x02])
        EXPECT_DECODE_ULEB128_EQ(0x101 as UInt32, [0x81, 0x02])
        EXPECT_DECODE_ULEB128_EQ(4_294_975_616 as UInt64, [0x80, 0xC1, 0x80, 0x80, 0x10])
        EXPECT_DECODE_ULEB128_EQ(0 as UInt32, [0x80, 0x00])
        EXPECT_DECODE_ULEB128_EQ(0 as UInt32, [0x80, 0x80, 0x00])
        EXPECT_DECODE_ULEB128_EQ(0x7F as UInt32, [0xFF, 0x00])
        EXPECT_DECODE_ULEB128_EQ(0x7F as UInt32, [0xFF, 0x80, 0x00])
        EXPECT_DECODE_ULEB128_EQ(0x80 as UInt32, [0x80, 0x81, 0x00])
        EXPECT_DECODE_ULEB128_EQ(0x80 as UInt32, [0x80, 0x81, 0x80, 0x00])
    }

    func testDecodeSLEB128() {
        func EXPECT_DECODE_SLEB128_EQ<T>(
            _ expected: T, _ value: [UInt8],
            file: StaticString = #filePath, line: UInt = #line
        ) where T: SignedInteger, T: FixedWidthInteger {
            XCTAssertEqual(decodeSLEB128(value[...], T.self).value, expected, file: file, line: line)
        }
        EXPECT_DECODE_SLEB128_EQ(0, [0x00])
        EXPECT_DECODE_SLEB128_EQ(1, [0x01])
        EXPECT_DECODE_SLEB128_EQ(63, [0x3F])
        EXPECT_DECODE_SLEB128_EQ(-64, [0x40])
        EXPECT_DECODE_SLEB128_EQ(-63, [0x41])
        EXPECT_DECODE_SLEB128_EQ(-1, [0x7F])
        EXPECT_DECODE_SLEB128_EQ(128, [0x80, 0x01])
        EXPECT_DECODE_SLEB128_EQ(129, [0x81, 0x01])
        EXPECT_DECODE_SLEB128_EQ(-129, [0xFF, 0x7E])
        EXPECT_DECODE_SLEB128_EQ(-128, [0x80, 0x7F])
        EXPECT_DECODE_SLEB128_EQ(-127, [0x81, 0x7F])
        EXPECT_DECODE_SLEB128_EQ(64, [0xC0, 0x00])
        EXPECT_DECODE_SLEB128_EQ(-12345, [0xC7, 0x9F, 0x7F])
    }

    func testEncodeULEB128() {
        func EXPECT_ULEB128_EQ<T>(
            _ expected: [UInt8], _ value: T, _ padTo: Int? = nil,
            file: StaticString = #filePath, line: UInt = #line
        ) where T: UnsignedInteger, T: FixedWidthInteger {
            XCTAssertEqual(encodeULEB128(value, padTo: padTo), expected, file: file, line: line)
        }

        EXPECT_ULEB128_EQ([0x00], 0 as UInt32)
        EXPECT_ULEB128_EQ([0x01], 1 as UInt32)
        EXPECT_ULEB128_EQ([0x3F], 63 as UInt32)
        EXPECT_ULEB128_EQ([0x40], 64 as UInt32)
        EXPECT_ULEB128_EQ([0x7F], 0x7F as UInt32)
        EXPECT_ULEB128_EQ([0x80, 0x01], 0x80 as UInt32)
        EXPECT_ULEB128_EQ([0x81, 0x01], 0x81 as UInt32)
        EXPECT_ULEB128_EQ([0x90, 0x01], 0x90 as UInt32)
        EXPECT_ULEB128_EQ([0xFF, 0x01], 0xFF as UInt32)
        EXPECT_ULEB128_EQ([0x80, 0x02], 0x100 as UInt32)
        EXPECT_ULEB128_EQ([0x81, 0x02], 0x101 as UInt32)

        EXPECT_ULEB128_EQ([0x80, 0x00], 0 as UInt32, 2)
        EXPECT_ULEB128_EQ([0x80, 0x80, 0x00], 0 as UInt32, 3)
        EXPECT_ULEB128_EQ([0xFF, 0x00], 0x7F as UInt32, 2)
        EXPECT_ULEB128_EQ([0xFF, 0x80, 0x00], 0x7F as UInt32, 3)
        EXPECT_ULEB128_EQ([0x80, 0x81, 0x00], 0x80 as UInt32, 3)
        EXPECT_ULEB128_EQ([0x80, 0x81, 0x80, 0x00], 0x80 as UInt32, 4)
    }

    func testEncodeSLEB128() {
        func EXPECT_SLEB128_EQ<T>(
            _ expected: [UInt8], _ value: T, _ padTo: Int? = nil,
            file: StaticString = #filePath, line: UInt = #line
        ) where T: SignedInteger, T: FixedWidthInteger {
            XCTAssertEqual(encodeSLEB128(value, padTo: padTo), expected, file: file, line: line)
        }

        EXPECT_SLEB128_EQ([0x00], 0)
        EXPECT_SLEB128_EQ([0x01], 1)
        EXPECT_SLEB128_EQ([0x7F], -1)
        EXPECT_SLEB128_EQ([0x3F], 63)
        EXPECT_SLEB128_EQ([0x41], -63)
        EXPECT_SLEB128_EQ([0x40], -64)
        EXPECT_SLEB128_EQ([0xBF, 0x7F], -65)
        EXPECT_SLEB128_EQ([0xC0, 0x00], 64)

        EXPECT_SLEB128_EQ([0x80, 0x00], 0, 2)
        EXPECT_SLEB128_EQ([0x80, 0x80, 0x00], 0, 3)
        EXPECT_SLEB128_EQ([0xFF, 0x80, 0x00], 0x7F, 3)
        EXPECT_SLEB128_EQ([0xFF, 0x80, 0x80, 0x00], 0x7F, 4)
        EXPECT_SLEB128_EQ([0x80, 0x81, 0x00], 0x80, 3)
        EXPECT_SLEB128_EQ([0x80, 0x81, 0x80, 0x00], 0x80, 4)
        EXPECT_SLEB128_EQ([0xC0, 0x7F], -0x40, 2)

        EXPECT_SLEB128_EQ([0xC0, 0xFF, 0x7F], -0x40, 3)
        EXPECT_SLEB128_EQ([0x80, 0xFF, 0x7F], -0x80, 3)
        EXPECT_SLEB128_EQ([0x80, 0xFF, 0xFF, 0x7F], -0x80, 4)
    }
}
