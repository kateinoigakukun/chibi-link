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
        EXPECT_DECODE_ULEB128_EQ(63 as UInt32, [0x3f])
        EXPECT_DECODE_ULEB128_EQ(64 as UInt32, [0x40])
        EXPECT_DECODE_ULEB128_EQ(0x7f as UInt32, [0x7f])
        EXPECT_DECODE_ULEB128_EQ(0x80 as UInt32, [0x80, 0x01])
        EXPECT_DECODE_ULEB128_EQ(0x81 as UInt32, [0x81, 0x01])
        EXPECT_DECODE_ULEB128_EQ(0x90 as UInt32, [0x90, 0x01])
        EXPECT_DECODE_ULEB128_EQ(0xff as UInt32, [0xff, 0x01])
        EXPECT_DECODE_ULEB128_EQ(0x100 as UInt32, [0x80, 0x02])
        EXPECT_DECODE_ULEB128_EQ(0x101 as UInt32, [0x81, 0x02])
        EXPECT_DECODE_ULEB128_EQ(4294975616 as UInt64, [0x80, 0xc1, 0x80, 0x80, 0x10])
        EXPECT_DECODE_ULEB128_EQ(0 as UInt32, [0x80, 0x00])
        EXPECT_DECODE_ULEB128_EQ(0 as UInt32, [0x80, 0x80, 0x00])
        EXPECT_DECODE_ULEB128_EQ(0x7f as UInt32, [0xff, 0x00])
        EXPECT_DECODE_ULEB128_EQ(0x7f as UInt32, [0xff, 0x80, 0x00])
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
        EXPECT_DECODE_SLEB128_EQ(63, [0x3f])
        EXPECT_DECODE_SLEB128_EQ(-64, [0x40])
        EXPECT_DECODE_SLEB128_EQ(-63, [0x41])
        EXPECT_DECODE_SLEB128_EQ(-1, [0x7f])
        EXPECT_DECODE_SLEB128_EQ(128, [0x80, 0x01])
        EXPECT_DECODE_SLEB128_EQ(129, [0x81, 0x01])
        EXPECT_DECODE_SLEB128_EQ(-129, [0xff, 0x7e])
        EXPECT_DECODE_SLEB128_EQ(-128, [0x80, 0x7f])
        EXPECT_DECODE_SLEB128_EQ(-127, [0x81, 0x7f])
        EXPECT_DECODE_SLEB128_EQ(64, [0xc0, 0x00])
        EXPECT_DECODE_SLEB128_EQ(-12345, [0xc7, 0x9f, 0x7f])
    }
}
