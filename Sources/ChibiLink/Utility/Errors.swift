#if canImport(Foundation)
    import protocol Foundation.LocalizedError
#else
    protocol LocalizedError: Swift.Error {
        var errorDescription: String? { get }
    }
#endif

extension Relocator.Error: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .weakUndefinedSymbol:
            return "unreachable: weak undef symbols should be replaced with synthesized stub function"
        case .unhandledRelocationType(let type):
            return "Unhandled relocation type: \(type)"
        }
    }
}

extension Symbol.UndefinedError: LocalizedError {
    var errorDescription: String? {
        "Undefined symbol: \(symbol.target.name)"
    }
}

extension OutputExportSection.Error: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .functionNotFound(let name):
            return "Export function '\(name)' not found"
        }
    }
}

extension BinaryReader.Error: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidSectionCode(let code):
            return "Invalid section code: \(code)."
        case .invalidElementType(let type):
            return "Invalid element type: \(type)"
        case .invalidValueType(let type):
            return "Invalid value type: \(type)"
        case .invalidExternalKind(let kind):
            return "Invalid external kind: \(kind)"
        case .invalidRelocType(let type):
            return "Invalid reloc type: \(type)"
        case .expectConstOpcode(let value):
            return "Invalid const opcode: \(value)"
        case .expectI32Const(let value):
            return "Expected i32 const opcode but found: \(value)"
        case .expectEnd:
            return "Expected end opcode"
        case .unsupportedImportKind(let kind):
            return "Import kind '\(kind)' is not supported"
        case .invalidImportKind(let rawKind):
            return "Import kind '(rawKind = \(rawKind))' is not supported"
        case .invalidSymbolType(let type):
            return "Invalid symbol type: \(type)"
        }
    }
}

extension Symbol.Error: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .conflict(let name, let oldContext, let newContext):
            return """
                Symbol conflict: \(name)
                >>> defined in \(oldContext)
                >>> defined in \(newContext)
            """
        case .unexpectedType(let symbol, let expectedType):
            guard let symbol = symbol else {
                return "Expected \(expectedType) symbol but found nil"
            }
            return """
                Symbol type mismatch: \(symbol.name)
                Expected to be \(expectedType) but defined as \(symbol)
            """
        }
    }
}
