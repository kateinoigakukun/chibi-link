#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

protocol OutputByteStream {
    /// The head offset that the stream is writing at.
    var currentOffset: Offset { get }
    /// Write `bytes` at `currentOffset` and move the current offset
    func write(_ bytes: ArraySlice<UInt8>) throws
    /// Write `bytes` at `currentOffset` and move the current offset
    func write(_ bytes: Array<UInt8>) throws
    /// Write `value` as UTF-8 bytes at `currentOffset` and move the current offset
    func writeString(_ value: String) throws
    /// Write `bytes` at `offset`. Doesn't move current offset
    func write(_ bytes: Array<UInt8>, at offset: Offset) throws
}

extension OutputByteStream {
    func write(_ bytes: Array<UInt8>) throws {
        try write(bytes[...])
    }
}

class FileOutputByteStream: OutputByteStream {
    private let filePointer: UnsafeMutablePointer<FILE>
    private(set) var currentOffset: Offset = 0
    convenience init(path: String) {
        self.init(filePointer: fopen(path, "wb"))
    }
    init(filePointer: UnsafeMutablePointer<FILE>) {
        self.filePointer = filePointer
    }

    deinit { fclose(filePointer) }

    func write(_ bytes: Array<UInt8>, at offset: Offset) throws {
        let original = self.currentOffset
        fseek(filePointer, offset, SEEK_SET)
        try write(bytes)
        fseek(filePointer, original, SEEK_SET)
        currentOffset -= bytes.count
    }
    
    private func _write(_ ptr: UnsafeRawPointer, length: Int) throws {
        while true {
            let n = fwrite(ptr, 1, length, filePointer)
            if n < 0 {
                if errno == EINTR { continue }
                throw FileSystemError.ioError(errno)
            } else if n != length {
                throw FileSystemError.ioError(errno)
            }
            break
        }
        currentOffset += length
    }
    func write(_ bytes: ArraySlice<UInt8>) throws {
        try bytes.withUnsafeBytes { bytesPtr in
            try _write(bytesPtr.baseAddress!, length: bytesPtr.count)
        }
    }

    func writeString(_ value: String) throws {
        var value = value
        try value.withUTF8 { (bufferPtr) in
            try _write(bufferPtr.baseAddress!, length: bufferPtr.count)
        }
    }
}
