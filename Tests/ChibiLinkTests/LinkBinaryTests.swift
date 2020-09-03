@testable import ChibiLink
import XCTest

func testCollect(_ content: String, options: [String] = []) throws -> (InputBinary, URL) {
    let module = compileWat(content, options: options)
    let binary = createInputBinary(module)
    let symtab = SymbolTable()
    let collector = LinkInfoCollector(binary: binary, symbolTable: symtab)
    let reader = BinaryReader(bytes: binary.data, delegate: collector)
    try reader.readModule()
    return (binary, module)
}

class InputBinaryTests: XCTestCase {
    func testEmpty() throws {
        _ = try testCollect("""
        (module)
        """)
    }

    func testBasic1() throws {
        let (binary, _) = try testCollect(
            """
            (module
              (type (;0;) (func (result i32)))
              (func (;0;) (type 0) (result i32)
                i32.const -420
                return)
              (export "main" (func 0)))
            """
        )
        XCTAssertEqual(binary.sections.count, 4)
        XCTAssertEqual(binary.functionCount, 1)
        XCTAssertEqual(binary.exports.count, 1)
        let firstExport = try XCTUnwrap(binary.exports.first)
        XCTAssertEqual(firstExport.name, "main")
        XCTAssertEqual(firstExport.index, 0)
        XCTAssertEqual(firstExport.kind, .func)
    }

    func testBasic2() throws {
        let content =
            """
            (module
              (import "foo" "bar" (func (result i32)))

              (global i32 (i32.const 1))

              (table anyfunc (elem 0))

              (memory (data "hello"))
              (func (result i32)
                (i32.add (call 0) (i32.const 1))
              )
            )
            """
        let (binary1, _) = try testCollect(content)
        let expectedSections1: Set<BinarySection> = [
            .type, .import, .function, .global, .table, .elem, .memory, .data, .code,
        ]
        let actualSections1 = Set(binary1.sections.map(\.sectionCode))
        XCTAssertEqual(actualSections1, expectedSections1)
        XCTAssertEqual(binary1.tableElemSize, 1)
        XCTAssertEqual(binary1.functionCount, 1)
        XCTAssertEqual(binary1.funcImports.count, 1)
        let firstImport = try XCTUnwrap(binary1.funcImports.first)
        XCTAssertEqual(firstImport.unresolved, true)
        XCTAssertEqual(firstImport.module, "foo")
        XCTAssertEqual(firstImport.field, "bar")
        XCTAssertEqual(firstImport.signatureIdx, 0)

        XCTAssertEqual(binary1.unresolvedFunctionImportsCount, 1)

        let (binary2, _) = try testCollect(content, options: ["-r"])
        var expectedSections2 = expectedSections1
        expectedSections2.insert(.custom)
        let actualSections2 = Set(binary2.sections.map(\.sectionCode))
        XCTAssertEqual(actualSections2, expectedSections2)

        let elemSection = try XCTUnwrap(binary2.sections.first(where: { $0.sectionCode == .elem }))
        XCTAssertEqual(elemSection.relocations.count, 1)
        let elemFirstReloc = try XCTUnwrap(elemSection.relocations.first)
        XCTAssertEqual(elemFirstReloc.offset, 6)
        XCTAssertEqual(elemFirstReloc.type, .funcIndexLEB)
        XCTAssertEqual(elemFirstReloc.symbolIndex, 0)

        let codeSection = try XCTUnwrap(binary2.sections.first(where: { $0.sectionCode == .code }))
        XCTAssertEqual(codeSection.relocations.count, 1)
        let codeFirstReloc = try XCTUnwrap(codeSection.relocations.first)
        XCTAssertEqual(codeFirstReloc.offset, 4)
        XCTAssertEqual(codeFirstReloc.type, .funcIndexLEB)
        XCTAssertEqual(codeFirstReloc.symbolIndex, 0)
    }
}
