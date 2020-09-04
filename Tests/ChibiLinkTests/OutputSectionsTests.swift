@testable import ChibiLink
import XCTest

@discardableResult
func testSections(_ contents: [String: Input]) throws -> [BinarySection: [Section]] {
    let linker = Linker()
    var inputs: [InputBinary] = []
    let symtab = SymbolTable()
    for (filename, input) in contents {
        let relocatable = compile(input.relocatable())
        let binary = createInputBinary(relocatable, filename: filename)
        let collector = LinkInfoCollector(binary: binary, symbolTable: symtab)
        let reader = BinaryReader(bytes: binary.data, delegate: collector)
        try reader.readModule()
        linker.append(binary)
        inputs.append(binary)
        print("Linking \(relocatable)")
    }
    linker.link()
    var sectionsMap: [BinarySection: [Section]] = [:]
    for sec in inputs.lazy.flatMap(\.sections) {
        sectionsMap[sec.sectionCode, default: []].append(sec)
    }
    return sectionsMap
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
        let dataSections = sections[.data]!
        let outSection = DataSection(sections: dataSections)
        XCTAssertEqual(outSection.count, 2)
        XCTAssertEqual(outSection.count, outSection.segments.count)

        let anotherSeg = outSection.segments[0].segment
        XCTAssertEqual(anotherSeg.name, "another_sec")
        XCTAssertEqual(anotherSeg.relocs.count, 1)

        let dataSeg = outSection.segments[1].segment
        XCTAssertEqual(dataSeg.name, ".data")
        XCTAssertEqual(dataSeg.relocs.count, 1)
    }
}
