import XCTest

@testable import ChibiLink

class NopDelegate: BinaryReaderDelegate {
    var state: BinaryReaderState!
    func setState(_ state: BinaryReaderState) {
        self.state = state
    }

    func beginSection(_: SectionCode, size _: Size) {}
    func beginNamesSection(_: Size) {}
    func onFunctionName(_: Int, _: String) {}
    func onFunctionCount(_: Int) {}
    func onImportFunc(_: Int, _: String, _: String, _: Int, _: Int) {}
    func onImportGlobal(_: Int, _: String, _: String, _: Int, _: ValueType, _: Bool) {}
    func onImportTable(_ importIndex: Index, _ module: String, _ field: String, _ tableIndex: Index) {}
    func onMemory(_: Int, _: Limits) {}
    func onExport(_: Int, _: ExternalKind, _: Int, _: String) {}
    func onElementSegmentFunctionIndexCount(_: Int, _: Int) {}
    func onInitExprI32ConstExpr(_: Int, _: UInt32) {}
    func beginDataSegment(_: Int, _: Int) {}
    func onDataSegmentData(_: Int, _: Range<Int>) {}
    func onRelocCount(_: Int, _: Int) {}
    func onReloc(_: RelocType, _: Offset, _: Index, _: Int32) {}
    func onFunctionSymbol(_: Index, _: UInt32, _: String?, _: Index) {}

    func onGlobalSymbol(_: Index, _: UInt32, _: String?, _: Index) {}

    func onDataSymbol(
        _: Index, _: UInt32, _: String, _: (segmentIndex: Index, offset: Offset, size: Size)?
    ) {}
    func onTableSymbol(_ index: Index, _ flags: UInt32, _ name: String?, _ itemIndex: Index) {}
    func onUnknownSymbol(_ index: Index, _ flags: UInt32) {}

    func onSegmentInfo(_: Index, _: String, _: Int, _: UInt32) {}
    func onInitFunction(_ initSymbol: Index, _ priority: UInt32) {}
}

func testRead<D: BinaryReaderDelegate>(_ delegate: D, options: [String] = [], _ content: String)
    throws
{
    let output = compileWat(content, options: options)
    let bytes = try Array(Data(contentsOf: output))
    let reader = BinaryReader(bytes: bytes, delegate: delegate)
    try reader.readModule()
}

class BinaryReaderTests: XCTestCase {
    func testEmpty() throws {
        try testRead(
            NopDelegate(),
            """
            (module)
            """
        )
    }

    func testBasic() throws {
        class Delegate: NopDelegate {
            override func onFunctionCount(_ count: Int) {
                XCTAssertEqual(count, 1)
            }

            override func onExport(
                _ exportIndex: Int, _: ExternalKind, _ itemIndex: Int, _ name: String
            ) {
                XCTAssertEqual(exportIndex, 0)
                XCTAssertEqual(itemIndex, 0)
                XCTAssertEqual(name, "main")
            }
        }
        try testRead(
            Delegate(),
            """
            (module
              (type (;0;) (func (result i32)))
              (func (;0;) (type 0) (result i32)
                i32.const -420
                return)
              (export "main" (func 0)))
            """
        )
    }

    func testBasic2() throws {
        class Delegate: NopDelegate {
            override func onFunctionCount(_ count: Int) {
                XCTAssertEqual(count, 1)
            }

            override func onImportFunc(
                _ importIndex: Int,
                _ module: String, _ field: String,
                _ funcIndex: Int,
                _: Int
            ) {
                XCTAssertEqual(importIndex, 0)
                XCTAssertEqual(funcIndex, 0)
                XCTAssertEqual(module, "foo")
                XCTAssertEqual(field, "bar")
            }

            override func onMemory(_ memoryIndex: Int, _ pageLimits: Limits) {
                XCTAssertEqual(memoryIndex, 0)
                XCTAssertEqual(pageLimits.initial, 1)
                XCTAssertEqual(pageLimits.max, 1)
            }

            override func onInitExprI32ConstExpr(_ segmentIndex: Int, _ value: UInt32) {
                XCTAssertEqual(segmentIndex, 0)
                XCTAssertEqual(value, 0)
            }

            override func onElementSegmentFunctionIndexCount(_ segmentIndex: Int, _ indexCount: Int)
            {
                XCTAssertEqual(segmentIndex, 0)
                XCTAssertEqual(indexCount, 1)
            }

            override func beginDataSegment(_: Int, _ memoryIndex: Int) {
                XCTAssertEqual(memoryIndex, 0)
            }
        }
        let content = """
            (module
              (import "foo" "bar" (func (result i32)))

              (global i32 (i32.const 1))

              (table anyfunc (elem 0))

              (memory (data "hello"))
              (func (result i32)
                (i32.add (call 0) (i32.load8_s (i32.const 1)))))

            """
        try testRead(Delegate(), content)
        class RelocDelegate: NopDelegate {
            var sections: [SectionCode] = []
            var expectedSections: [SectionCode] = [.code]
            override func beginSection(_ section: SectionCode, size _: Size) {
                sections.append(section)
            }

            override func onRelocCount(_: Int, _ sectionIndex: Int) {
                let section = sections[sectionIndex]
                let expected = expectedSections.removeFirst()
                XCTAssertEqual(section, expected)
            }
        }
        let delegate = RelocDelegate()
        try testRead(delegate, options: ["-r"], content)
    }

    func testSegmentInfo() throws {
        class Delegate: NopDelegate {
            typealias Info = (
                index: Index, name: String, alignment: Int, flags: UInt32
            )
            var infoList: [Info] = []
            override func onSegmentInfo(
                _ index: Index, _ name: String, _ alignment: Int, _ flags: UInt32
            ) {
                infoList.append((index, name, alignment, flags))
            }
        }
        let content = """
            target datalayout = "e-m:e-p:32:32-i64:64-n32:64-S128"
            target triple = "wasm32-unknown-unknown"

            @bss = hidden global i32 zeroinitializer, align 4
            @foo = hidden global i32 zeroinitializer, section "WowZero!", align 4
            @bar = hidden constant i32 42, section "MyAwesomeSection", align 4
            @baz = hidden global i32 7, section "AnotherGreatSection", align 4
            """

        let output = compileLLVMIR(content)
        let bytes = try Array(Data(contentsOf: output))
        let delegate = Delegate()
        let reader = BinaryReader(bytes: bytes, delegate: delegate)
        try reader.readModule()
        XCTAssertEqual(delegate.infoList.count, 4)
        XCTAssertEqual(delegate.infoList[0].name, ".bss.bss")
    }
}
