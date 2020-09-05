@testable import ChibiLink
import XCTest

@discardableResult
func testSections(_ contents: [String: Input]) throws -> [BinarySection: OutputSection] {
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
    var sectionsMap: [BinarySection: [Section]] = [:]
    for sec in inputs.lazy.flatMap(\.sections) {
        sectionsMap[sec.sectionCode, default: []].append(sec)
    }
    let typeSection = TypeSection(sections: sectionsMap[.type] ?? [], symbolTable: symtab)
    let importSection = ImportSeciton(symbolTable: symtab, typeSection: typeSection)
    let funcSection = FunctionSection(
        sections: sectionsMap[.function] ?? [],
        typeSection: typeSection, importSection: importSection, symbolTable: symtab
    )
    let dataSection = DataSection(sections: sectionsMap[.data] ?? [])
    let codeSection = CodeSection(sections: sectionsMap[.code] ?? [], symbolTable: symtab)
    let tableSection = TableSection(inputs: inputs)
    let memorySection = MemorySection(dataSection: dataSection)
    let elemSection = ElementSection(
        sections: sectionsMap[.elem] ?? [], funcSection: funcSection
    )
    return [
        .type: typeSection,
        .import: importSection,
        .function: funcSection,
        .data: dataSection,
        .code: codeSection,
        .table: tableSection,
        .memory: memorySection,
        .elem: elemSection,
    ]
}

class OutputSectionsTests: XCTestCase {
    func testDataSection() throws {
        let sections = try testSections([
            "foo.ll": .llvm("""
            target datalayout = "e-m:e-p:32:32-i64:64-n32:64-S128"
            target triple = "wasm32-unknown-unknown"

            @hello_str = hidden global [12 x i8] c"hello world\\00"
            @bye_str   = hidden global [9 x i8] c"good bye\\00"
            """),
            "user.ll": .llvm("""
            target datalayout = "e-m:e-p:32:32-i64:64-n32:64-S128"
            target triple = "wasm32-unknown-unknown"

            @foo = hidden global i32 1, align 4
            @aligned_bar = hidden global i32 3, align 16

            @hello_str = external global i8*
            @external_ref1 = global i8** @hello_str, align 8
            @bye_str = external global i8*
            @external_ref2 = global i8** @bye_str, section "another_sec", align 4
            """),
        ])
        let outSection = sections[.data]! as! DataSection
        XCTAssertEqual(outSection.count, 2)
        XCTAssertEqual(outSection.count, outSection.segments.count)

        let anotherSeg = outSection.segments[0].segment
        XCTAssertEqual(anotherSeg.name, "another_sec")
        XCTAssertEqual(anotherSeg.chunks.count, 1)
        XCTAssertEqual(anotherSeg.chunks[0].relocs.count, 1)

        let dataSeg = outSection.segments[1].segment
        XCTAssertEqual(dataSeg.name, ".data")
        XCTAssertEqual(dataSeg.chunks.count, 5)
        XCTAssertEqual(dataSeg.chunks.flatMap(\.relocs).count, 1)
    }

    func testElementSection() throws {
        let sections = try testSections([
            "main.ll": .llvm("""
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
            """),
        ])
        let outSection = sections[.elem]! as! ElementSection
        XCTAssertEqual(outSection.elementCount, 1)
    }
}
