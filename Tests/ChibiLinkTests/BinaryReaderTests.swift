import XCTest

@testable import ChibiLink

func exec(_ launchPath: String, _ arguments: [String]) {
    let process = Process()
    process.launchPath = launchPath
    process.arguments = arguments
    process.launch()
    process.waitUntilExit()
    assert(process.terminationStatus == 0)
}

func makeTemporaryFile() -> (URL, FileHandle) {
    let tempdir = URL(fileURLWithPath: NSTemporaryDirectory())
    let templatePath = tempdir.appendingPathComponent("chibi-link.XXXXXX")
    var template = [UInt8](templatePath.path.utf8).map { Int8($0) } + [Int8(0)]
    let fd = mkstemp(&template)
    if fd == -1 {
        fatalError("Failed to create temp directory")
    }
    let url = URL(fileURLWithPath: String(cString: template))
    let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    return (url, handle)
}

func createFile(_ content: String) -> URL {
    let (url, handle) = makeTemporaryFile()
    handle.write(content.data(using: .utf8)!)
    return url
}

class NopDelegate: BinaryReaderDelegate {
    var state: BinaryReader.State!
    func setState(_ state: BinaryReader.State) {
        self.state = state
    }

    func beginSection(_: BinarySection, size _: UInt32) {}
    func beginNamesSection(_: UInt32) {}
    func onFunctionName(_: Int, _: String) {}
    func onFunctionCount(_: Int) {}
    func onImportFunc(_: Int, _: String, _: String, _: Int, _: Int) {}
    func onImportMemory(_: Int, _: String, _: String, _: Int, _: Limits) {}
    func onImportGlobal(_: Int, _: String, _: String, _: Int, _: ValueType, _: Bool) {}
    func onTable(_: Int, _: ElementType, _: Limits) {}
    func onMemory(_: Int, _: Limits) {}
    func onExport(_: Int, _: ExternalKind, _: Int, _: String) {}
    func onElementSegmentFunctionIndexCount(_: Int, _: Int) {}
    func onInitExprI32ConstExpr(_: Int, _: UInt32) {}
    func beginDataSegment(_: Int, _: Int) {}
    func onDataSegmentData(_: Int, _: ArraySlice<UInt8>, _: Int) {}
    func onRelocCount(_: Int, _: Int) {}
    func onReloc(_: RelocType, _: UInt32, _: UInt32, _: UInt32) {}
}

func testRead(_ delegate: BinaryReaderDelegate, options: [String] = [], _ content: String) throws {
    let module = createFile(content)
    let (output, _) = makeTemporaryFile()
    exec("/usr/local/bin/wat2wasm", [module.path, "-o", output.path] + options)
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

            override func onExport(_ exportIndex: Int, _: ExternalKind, _ itemIndex: Int, _ name: String) {
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

            override func onTable(_ tableIndex: Int, _ type: ElementType, _: Limits) {
                XCTAssertEqual(tableIndex, 0)
                XCTAssertEqual(type, .funcRef)
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

            override func onElementSegmentFunctionIndexCount(_ segmentIndex: Int, _ indexCount: Int) {
                XCTAssertEqual(segmentIndex, 0)
                XCTAssertEqual(indexCount, 1)
            }

            override func beginDataSegment(_: Int, _ memoryIndex: Int) {
                XCTAssertEqual(memoryIndex, 0)
            }

            override func onDataSegmentData(_: Int, _ data: ArraySlice<UInt8>, _: Int) {
                let hello = String(decoding: data, as: Unicode.ASCII.self)
                XCTAssertEqual(hello, "hello")
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
            var sections: [BinarySection] = []
            var expectedSections: [BinarySection] = [.elem, .code]
            override func beginSection(_ section: BinarySection, size _: UInt32) {
                sections.append(section)
            }

            override func onRelocCount(_: Int, _ sectionIndex: Int) {
                let section = sections[sectionIndex]
                let expected = expectedSections.removeFirst()
                XCTAssertEqual(section, expected)
            }
        }
        try testRead(RelocDelegate(), options: ["-r"], content)
    }
}
