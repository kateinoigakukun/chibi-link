@testable import ChibiLink
import XCTest

class IntegrationTests: XCTestCase {
    func testLinkSwiftStdlib() throws {
        let experiment = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("TokamakPad")
            .appendingPathComponent("Experiment")
        let inputs: [URL] = [
            experiment.appendingPathComponent("shared_lib.wasm"),
            experiment.appendingPathComponent("main.o"),
        ]
        let output = experiment.appendingPathComponent("linked.wasm")
        try performLinker(inputs.map(\.path), output: output.path)
        let bytes = try Data(contentsOf: output)
        let reader = BinaryReader(bytes: Array(bytes), delegate: NopDelegate())
        try reader.readModule()
    }
}
