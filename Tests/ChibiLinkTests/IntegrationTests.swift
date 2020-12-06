import XCTest

@testable import ChibiLink

class IntegrationTests: XCTestCase {
    func testLinkSwiftStdlib() throws {
        let outputs = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("output")
        let inputs: [URL] = [
            outputs.appendingPathComponent("shared_lib.wasm"),
            outputs.appendingPathComponent("main.o"),
        ]
        let output = outputs.appendingPathComponent("linked.wasm")
        let outputStream = try FileOutputByteStream(path: output.path)
        try performLinker(inputs.map(\.path), outputStream: outputStream)
        runWasm(output)
    }
}
