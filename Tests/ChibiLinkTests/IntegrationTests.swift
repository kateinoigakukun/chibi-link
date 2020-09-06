@testable import ChibiLink
import XCTest

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
        try performLinker(inputs.map(\.path), output: output.path)
        runWasm(output)
    }
}
