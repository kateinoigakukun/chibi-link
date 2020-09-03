@testable import ChibiLink
import XCTest

enum Input {
    case wat(String)
    case llvm(String)
}

@discardableResult
func testLink(_ contents: [String: Input]) throws -> [UInt8] {
    let linker = Linker()
    var inputs: [InputBinary] = []
    let symtab = SymbolTable()
    for (filename, input) in contents {
        let relocatable: URL = {
            switch input {
            case let .wat(content):
                return compileWat(content, options: ["-r"])
            case let .llvm(content):
                return compileLLVMIR(content)
            }
        }()
        let binary = createInputBinary(relocatable, filename: filename)
        let collector = LinkInfoCollector(binary: binary, symbolTable: symtab)
        let reader = BinaryReader(bytes: binary.data, delegate: collector)
        try reader.readModule()
        linker.append(binary)
        inputs.append(binary)
        print("Linking \(relocatable)")
    }
    linker.link()
    let stream = InMemoryOutputByteStream()
    let writer = OutputWriter(stream: stream, symbolTable: symtab, inputs: inputs)
    try writer.writeBinary()
    return stream.bytes
}

class LinkerTests: XCTestCase {
    func testMergeFunction() throws {
        try testLink([
            "lib.wat": .wat("""
            (module
              (func (result i32)
                (i32.add (i32.const 0) (i32.const 1))
              )
            )
            """),
            "main.wat": .wat("""
            (module
              (func (result i32)
                (i32.add (i32.const 0) (i32.const 2))
              )
            )
            """),
        ])
    }

    func testMergeImports() throws {
        let bytes = try testLink([
            "foo.wat": .wat("""
            (module
              (import "foo" "bar" (func (result i32)))
              (func (result i32)
                (i32.add (call 0) (i32.const 1))
              )
            )
            """),
            "main.wat": .wat("""
            (module
              (import "foo" "fizz" (func (result i32)))
              (func (result i32)
                (i32.add (call 0) (i32.const 1))
              )
            )
            """),
        ])

        class Collector: NopDelegate {
            var importedFunctions: [String] = []
            override func onImportFunc(
                _: Index,
                _: String, _ field: String,
                _: Index,
                _: Index
            ) {
                importedFunctions.append(field)
            }
        }
        let collector = Collector()
        let reader = BinaryReader(bytes: bytes, delegate: collector)
        let (output, handle) = makeTemporaryFile()
        handle.write(Data(bytes))
        print(output)
        try reader.readModule()
        XCTAssertEqual(collector.importedFunctions.sorted(), ["bar", "fizz"])
    }

    func testRelocData() throws {
        let bytes = try testLink([
            "foo.ll": .llvm("""
            target datalayout = "e-m:e-p:32:32-i64:64-n32:64-S128"
            target triple = "wasm32-unknown-unknown"

            @bss = hidden global i32 zeroinitializer, align 4
            @foo = hidden global i32 zeroinitializer, section "WowZero!", align 4
            @bar = hidden constant i32 42, section "MyAwesomeSection", align 4
            @baz = hidden global i32 7, section "AnotherGreatSection", align 4
            """),
            "main.ll": .llvm("""
            target datalayout = "e-m:e-p:32:32-i64:64-n32:64-S128"
            target triple = "wasm32-unknown-unknown"

            @foo = external global i32, align 4

            define void @_start() {
                %val = load i32, i32* @foo, align 4
                %tobool = icmp ne i32 %val, 0
                br i1 %tobool, label %call_fn, label %return
            call_fn:
                call void @_start()
                br label %return
            return:
                ret void
            }
            """),
        ])

        class Collector: NopDelegate {
            var importedFunctions: [String] = []
        }
        let collector = Collector()
        let reader = BinaryReader(bytes: bytes, delegate: collector)
        let (output, _) = makeTemporaryFile()
        print(output)
        try Data(bytes).write(to: output)
        try reader.readModule()
    }
}
