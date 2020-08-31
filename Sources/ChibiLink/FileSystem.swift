#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

enum FileSystemError: Error {
    case ioError(Int32)
}

func readFileContents(_ filename: String) throws -> [UInt8] {
    let fd = fopen(filename, "rb")
    defer { fclose(fd) }
    var bytes: [UInt8] = []
    var tmpBuffer = [UInt8](repeating: 0, count: 1 << 12)
    while true {
        let n = fread(&tmpBuffer, 1, tmpBuffer.count, fd)
        if n < 0 {
            if errno == EINTR { continue }
            throw FileSystemError.ioError(errno)
        }
        if n == 0 {
            if ferror(fd) != 0 {
                throw FileSystemError.ioError(errno)
            }
            break
        }
        bytes.append(contentsOf: tmpBuffer)
    }
    return bytes
}
