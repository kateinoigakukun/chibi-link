#if canImport(Darwin)
    import Darwin
#elseif canImport(WASILibc)
    import WASILibc

/// Enumeration describing **a subset of** POSIX error codes.
public enum POSIXErrorCode: Int32 {
    /// Interrupted system call.
    case EINTR           = 4
    /// Permission denied.
    case EACCES          = 13
    // Is a directory.
    case EISDIR          = 21
    /// No such file or directory.
    case ENOENT          = 2
    /// Not a directory.
    case ENOTDIR         = 20
}

#elseif canImport(Glibc)
    import Glibc
#endif

enum FileSystemError: Error {
    case invalidAccess
    case ioError
    case isDirectory
    case noEntry
    case notDirectory
    case unsupported
    case unknownOSError(Int32)
}

extension FileSystemError {
    init(errno: Int32) {
        switch POSIXErrorCode(rawValue: errno) {
        case .EACCES:
            self = .invalidAccess
        case .EISDIR:
            self = .isDirectory
        case .ENOENT:
            self = .noEntry
        case .ENOTDIR:
            self = .notDirectory
        default:
            self = .unknownOSError(errno)
        }
    }
}

func readFileContents(_ filename: String) throws -> [UInt8] {
    print("Info: Reading \(filename)")
    let fd = fopen(filename, "rb")
    guard fd != nil else { throw FileSystemError(errno: errno) }
    defer { fclose(fd) }
    var bytes: [UInt8] = []
    var tmpBuffer = [UInt8](repeating: 0, count: 1 << 12)
    while true {
        let n = fread(&tmpBuffer, 1, tmpBuffer.count, fd)
        if n < 0 {
            if errno == EINTR { continue }
            throw FileSystemError.ioError
        }
        if n == 0 {
            if ferror(fd) != 0 {
                throw FileSystemError.ioError
            }
            break
        }
        bytes.append(contentsOf: tmpBuffer[..<n])
    }
    return bytes
}
