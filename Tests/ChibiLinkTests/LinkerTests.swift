@testable import ChibiLink
import XCTest

func testLink(_ contents: [String: String]) throws {
    let linker = Linker()
    for (filename, content) in contents {
        let relocatable = compileWat(content, options: ["-r"])
        let binary = createInputBinary(relocatable, filename: filename)
        let collector = LinkInfoCollector(binary: binary)
        let reader = BinaryReader(bytes: binary.data, delegate: collector)
        try reader.readModule()
        linker.append(binary)
    }
    linker.link()
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

    func testImports() throws {
        try testLink([
            "foo.wat": """
            (module
              (func (result i32)
                (i32.add (i32.const 0) (i32.const 1))
              )
              (export "bar" (func 0))
            )
            """,
            "main.wat": """
            (module
              (import "foo" "bar" (func (result i32)))
            )
            """,
        ])
    }
}
