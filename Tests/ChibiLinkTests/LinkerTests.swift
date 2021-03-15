import XCTest

@testable import ChibiLink

@discardableResult
func testLink(_ contents: [String: Input]) throws -> [UInt8] {
    var inputs: [InputBinary] = []
    let symtab = SymbolTable()
    for (filename, input) in contents {
        let relocatable = compile(input.relocatable())
        let binary = createInputBinary(relocatable, filename: filename)
        let collector = LinkInfoCollector(binary: binary, symbolTable: symtab)
        let reader = BinaryReader(bytes: binary.data, delegate: collector)
        try reader.readModule()
        inputs.append(binary)
        print("Linking \(relocatable)")
    }
    let stream = InMemoryOutputByteStream()
    let writer = OutputWriter(stream: stream, symbolTable: symtab, inputs: inputs)
    try writer.writeBinary()
    return stream.bytes
}

class LinkerTests: XCTestCase {
    func testMergeFunction() throws {
        try testLink([
            "lib.wat": .wat(
                """
                (module
                  (func (result i32)
                    (i32.add (i32.const 0) (i32.const 1))
                  )
                )
                """),
            "main.wat": .wat(
                """
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
            "foo.wat": .wat(
                """
                (module
                  (import "foo" "bar" (func (result i32)))
                  (func (result i32)
                    (i32.add (call 0) (i32.const 1))
                  )
                )
                """),
            "main.wat": .wat(
                """
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

    func testMergeGlobals() throws {
        let bytes = try testLink([
            "foo.wat": .wat(
                """
                (module
                  (import "__extern" "bar" (global i32))
                  (global i32 (i32.const 1))
                )
                """),
            "main.wat": .wat(
                """
                (module
                    (global i64 (i64.const 2))
                )
                """),
        ])
        let reader = BinaryReader(bytes: bytes, delegate: NopDelegate())
        let (output, handle) = makeTemporaryFile()
        handle.write(Data(bytes))
        print(output)
        try reader.readModule()
    }

    func testMergeData() throws {
        let bytes = try testLink([
            "foo.ll": .llvm(
                """
                target datalayout = "e-m:e-p:32:32-i64:64-n32:64-S128"
                target triple = "wasm32-unknown-unknown"

                @bss = hidden global i32 zeroinitializer, align 4
                @foo = hidden global i32 zeroinitializer, section "WowZero!", align 4
                @bar = hidden constant i32 42, section "MyAwesomeSection", align 4
                @baz = hidden global i32 7, section "AnotherGreatSection", align 4
                """),
            "main.ll": .llvm(
                """
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

    func testRelocData() throws {
        let bytes = try testLink([
            "foo.ll": .llvm(
                """
                target datalayout = "e-m:e-p:32:32-i64:64-n32:64-S128"
                target triple = "wasm32-unknown-unknown"

                @hello_str = hidden global [12 x i8] c"hello world\\00"
                @bye_str   = hidden global [9 x i8] c"good bye\\00"
                """),
            "user.ll": .llvm(
                """
                target datalayout = "e-m:e-p:32:32-i64:64-n32:64-S128"
                target triple = "wasm32-unknown-unknown"

                @foo = hidden global i32 1, align 4
                @aligned_bar = hidden global i32 3, align 16

                @hello_str = external global i8*
                @external_ref1 = global i8** @hello_str, align 8
                @bye_str = external global i8*
                @external_ref2 = global i8** @bye_str, align 8
                """),
        ])

        let reader = BinaryReader(bytes: bytes, delegate: NopDelegate())
        let (output, _) = makeTemporaryFile()
        print(output)
        try Data(bytes).write(to: output)
        try reader.readModule()
    }

    func testRelocElem() throws {
        let bytes = try testLink([
            "main.ll": .llvm(
                """
                target triple = "wasm32-unknown-unknown"

                @indirect_func = local_unnamed_addr global i32 ()* @foo, align 4

                define i32 @foo() #0 {
                entry:
                  ret i32 2
                }

                define void @_start() local_unnamed_addr #1 {
                entry:
                  %0 = load i32 ()*, i32 ()** @indirect_func, align 4
                  %call = call i32 %0() #2
                  ret void
                }

                define void @call_ptr(i64 (i64)* %arg) {
                  %1 = call i64 %arg(i64 1)
                  ret void
                }
                """)
        ])
        let reader = BinaryReader(bytes: bytes, delegate: NopDelegate())
        let (output, _) = makeTemporaryFile()
        print(output)
        try Data(bytes).write(to: output)
        try reader.readModule()
    }

    func testExportedAttr() throws {
        let bytes = try testLink([
            "foo.ll": .llvm(
                """
                target triple = "wasm32-unknown-unknown"
                define hidden i32 @foo() #0 {
                    ret i32 0
                }
                attributes #0 = { "wasm-export-name"="exported_func" }
                """)
        ])
        class Collector: NopDelegate {
            var exported: [String] = []
            override func onExport(_: Int, _: ExternalKind, _: Int, _ name: String) {
                exported.append(name)
            }
        }
        let collector = Collector()
        let reader = BinaryReader(bytes: bytes, delegate: collector)
        let (output, _) = makeTemporaryFile()
        print(output)
        try Data(bytes).write(to: output)
        try reader.readModule()
        XCTAssertEqual(collector.exported.sorted(), ["exported_func", "memory"].sorted())
    }
}
