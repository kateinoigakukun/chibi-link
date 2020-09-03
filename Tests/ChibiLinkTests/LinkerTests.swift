@testable import ChibiLink
import XCTest

@discardableResult
func testLink(_ contents: [String: String]) throws -> URL {
    let linker = Linker()
    var inputs: [InputBinary] = []
    let symtab = SymbolTable()
    for (filename, content) in contents {
        let relocatable = compileWat(content, options: ["-r"])
        let binary = createInputBinary(relocatable, filename: filename)
        let collector = LinkInfoCollector(binary: binary, symbolTable: symtab)
        let reader = BinaryReader(bytes: binary.data, delegate: collector)
        try reader.readModule()
        linker.append(binary)
        inputs.append(binary)
        print("Linking \(relocatable)")
    }
    linker.link()
    let (output, handle) = makeTemporaryFile()
    try! handle.close()
    let stream = OutputByteStream(path: output.path)
    let writer = OutputWriter(stream: stream, symbolTable: symtab, inputs: inputs)
    try writer.writeBinary()
    return output
}

class LinkerTests: XCTestCase {
    func testMergeFunction() throws {
        try testLink([
            "lib.wat": """
            (module
              (func (result i32)
                (i32.add (i32.const 0) (i32.const 1))
              )
            )
            """,
            "main.wat": """
            (module
              (func (result i32)
                (i32.add (i32.const 0) (i32.const 2))
              )
            )
            """,
        ])
    }

    func testMergeImports() throws {
        let output = try testLink([
            "foo.wat": """
            (module
              (import "foo" "bar" (func (result i32)))
              (func (result i32)
                (i32.add (call 0) (i32.const 1))
              )
            )
            """,
            "main.wat": """
            (module
              (import "foo" "fizz" (func (result i32)))
              (func (result i32)
                (i32.add (call 0) (i32.const 1))
              )
            )
            """,
        ])
        let bytes = try Array(Data(contentsOf: output))
        class Collector: NopDelegate {
            var importedFunctions: [String] = []
            override func onImportFunc(
                _ importIndex: Index,
                _ module: String, _ field: String,
                _ funcIndex: Index,
                _ signatureIndex: Index
            ) {
                importedFunctions.append(field)
            }
        }
        let collector = Collector()
        let reader = BinaryReader(bytes: bytes, delegate: collector)
        try reader.readModule()
        XCTAssertEqual(collector.importedFunctions.sorted(), ["bar", "fizz"])
    }
}
