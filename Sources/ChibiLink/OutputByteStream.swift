#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

class OutputByteStream {
    private let filePointer: UnsafeMutablePointer<FILE>
    private(set) var offset: Offset = 0

    init(filePointer: UnsafeMutablePointer<FILE>) {
        self.filePointer = filePointer
    }

    deinit { fclose(filePointer) }

    func write(_ bytes: ArraySlice<UInt8>) throws {
        try bytes.withUnsafeBytes { bytesPtr in
            while true {
                let n = fwrite(bytesPtr.baseAddress, 1, bytes.count, filePointer)
                if n < 0 {
                    if errno == EINTR { continue }
                    throw FileSystemError.ioError(errno)
                } else if n != bytesPtr.count {
                    throw FileSystemError.ioError(errno)
                }
            }
        }
        offset += bytes.count
    }
}
