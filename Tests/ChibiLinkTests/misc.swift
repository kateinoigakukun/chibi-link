import Foundation
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

func compileWat(_ content: String, options: [String] = []) -> URL {
    let module = createFile(content)
    let (output, _) = makeTemporaryFile()
    exec("/usr/local/bin/wat2wasm", [module.path, "-o", output.path] + options)
    return output
}

func createInputBinary(_ url: URL) -> InputBinary {
    let bytes = try! Array(Data(contentsOf: url))
    return InputBinary(filename: url.lastPathComponent, data: bytes)
}
