import ChibiLink
import ArgumentParser

struct ChibiLinkCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "chibi-link",
        abstract: "A linker for WebAssembly object files."
    )
    
    @Argument(help: "Input files.")
    var filenames: [String]
    
    @Option(name: .shortAndLong, help: "Output file.")
    var output: String
    
    @Option(name: .shortAndLong, help: "Export symbols.")
    var export: [String] = []

    @Option(name: .long, help: "Where to start to place global data")
    var globalBase: Int = 1024

    func run() throws {
        let outputStream = try FileOutputByteStream(path: output)
        try performLinker(filenames, outputStream: outputStream, exports: export, globalBase: globalBase)
    }
}

ChibiLinkCLI.main()
