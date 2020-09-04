@testable import ChibiLink
import Foundation

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

enum Input {
    case wat(String, options: [String])
    case llvm(String, options: [String])
    
    static func wat(_ input: String) -> Input {
        return .wat(input, options: [])
    }

    static func llvm(_ input: String) -> Input {
        return .llvm(input, options: [])
    }
    
    func relocatable() -> Input {
        switch self {
        case let .wat(content, options):
            return .wat(content, options: options + ["-r"])
        default:
            return self
        }
    }
}

func compileWat(_ content: String, options: [String] = []) -> URL {
    let module = createFile(content)
    let (output, _) = makeTemporaryFile()
    exec("/usr/local/bin/wat2wasm", [module.path, "-o", output.path] + options)
    return output
}

func compileLLVMIR(_ content: String, options: [String] = []) -> URL {
    let module = createFile(content)
    let (output, _) = makeTemporaryFile()
    exec("/usr/local/opt/llvm/bin/llc", [module.path, "-filetype=obj", "-o", output.path] + options)
    return output
}

func compile(_ input: Input) -> URL {
    switch input {
    case let .wat(content, options):
        return compileWat(content, options: options)
    case let .llvm(content, options):
        return compileLLVMIR(content, options: options)
    }
}

func createInputBinary(_ url: URL, filename: String? = nil) -> InputBinary {
    let bytes = try! Array(Data(contentsOf: url))
    let filename = filename ?? url.lastPathComponent
    return InputBinary(filename: filename, data: bytes)
}

class InMemoryOutputByteStream: OutputByteStream {
    private(set) var bytes: [UInt8] = []
    private(set) var currentOffset: Offset = 0

    func write(_ bytes: [UInt8], at offset: Offset) throws {
        for index in offset ..< (offset + bytes.count) {
            self.bytes[index] = bytes[index - offset]
        }
    }

    func write(_ bytes: ArraySlice<UInt8>) throws {
        self.bytes.append(contentsOf: bytes)
        currentOffset += bytes.count
    }

    func writeString(_ value: String) throws {
        bytes.append(contentsOf: value.utf8)
        currentOffset += value.utf8.count
    }
}
