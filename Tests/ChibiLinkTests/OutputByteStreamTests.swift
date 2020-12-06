import XCTest

@testable import ChibiLink

class OutputByteStreamTests: XCTestCase {
    func testWriteAt() throws {
        let (file, _) = makeTemporaryFile()
        do {
            let stream = try FileOutputByteStream(path: file.path)
            try stream.write([0, 0])
            try stream.write([0, 0, 0])
            try stream.write([1, 2, 3], at: 2)
            XCTAssertEqual(stream.currentOffset, 5)
            try stream.write([0, 0, 0])
            try stream.write([4, 5, 6], at: 5)
            XCTAssertEqual(stream.currentOffset, 8)
        }
        let bytes = try Data(contentsOf: file)
        XCTAssertEqual(Array(bytes), [0, 0, 1, 2, 3, 4, 5, 6])
    }
}
