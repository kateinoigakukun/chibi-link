struct SymbolFlags {
    let rawValue: UInt32
    private var binding: UInt32 { rawValue & SYMBOL_BINDING_MASK }
    var isWeak: Bool { binding == SYMBOL_BINDING_WEAK }
    var isLocal: Bool { binding == SYMBOL_BINDING_LOCAL }
    private var visibility: UInt32 { rawValue & SYMBOL_VISIBILITY_MASK }
    var isHidden: Bool { visibility == SYMBOL_VISIBILITY_HIDDEN }
    var isExported: Bool { rawValue & SYMBOL_EXPORTED != 0 }
}

protocol DefinedTarget {
    var name: String { get }
    var binary: InputBinary { get }
}

protocol UndefinedTarget {
    var name: String { get }
    var module: String { get }
}

struct IndexableTarget: DefinedTarget {
    let itemIndex: Index
    let name: String
    let binary: InputBinary
}

extension FunctionImport: UndefinedTarget {
    var name: String { field }
}

extension GlobalImport: UndefinedTarget {
    var name: String { field }
}

enum SymbolTarget<Target: DefinedTarget, Import: UndefinedTarget> {
    case defined(Target)
    case undefined(Import)

    var name: String {
        switch self {
        case let .defined(target): return target.name
        case let .undefined(target): return target.name
        }
    }
}

protocol SymbolProtocol {
    associatedtype Defined: DefinedTarget
    associatedtype Import: UndefinedTarget
    typealias Target = SymbolTarget<Defined, Import>
    var target: Target { get }
    var flags: SymbolFlags { get }
}

final class FunctionSymbol: SymbolProtocol {
    typealias Target = SymbolTarget<IndexableTarget, FunctionImport>
    fileprivate(set) var target: Target
    let flags: SymbolFlags
    init(target: Target, flags: SymbolFlags) {
        self.target = target
        self.flags = flags
    }
}

final class GlobalSymbol: SymbolProtocol {
    typealias Target = SymbolTarget<IndexableTarget, GlobalImport>
    fileprivate(set) var target: Target
    let flags: SymbolFlags

    init(target: Target, flags: SymbolFlags) {
        self.target = target
        self.flags = flags
    }
}

final class DataSymbol: SymbolProtocol {
    struct DefinedSegment: DefinedTarget {
        let name: String
        let binary: InputBinary
        let segment: DataSegment
    }

    struct UndefinedSegment: UndefinedTarget {
        let name: String
        let module: String = "env"
    }

    typealias Target = SymbolTarget<DefinedSegment, UndefinedSegment>

    fileprivate(set) var target: Target
    let flags: SymbolFlags

    init(target: Target, flags: SymbolFlags) {
        self.target = target
        self.flags = flags
    }
}

enum Symbol {
    case function(FunctionSymbol)
    case global(GlobalSymbol)
    case data(DataSymbol)

    var name: String {
        switch self {
        case let .function(symbol):
            return symbol.target.name
        case let .data(symbol):
            return symbol.target.name
        case let .global(symbol):
            return symbol.target.name
        }
    }

    var isUndefined: Bool {
        func isUndef<T, U>(_ target: SymbolTarget<T, U>) -> Bool {
            guard case .undefined = target else { return false }
            return true
        }
        switch self {
        case let .function(symbol):
            return isUndef(symbol.target)
        case let .data(symbol):
            return isUndef(symbol.target)
        case let .global(symbol):
            return isUndef(symbol.target)
        }
    }

    var flags: SymbolFlags {
        switch self {
        case let .function(symbol):
            return symbol.flags
        case let .data(symbol):
            return symbol.flags
        case let .global(symbol):
            return symbol.flags
        }
    }
}

class SymbolTable {
    private var symbolMap: [String: Symbol] = [:]

    func symbols() -> [Symbol] {
        Array(symbolMap.values)
    }

    func find(_ name: String) -> Symbol? {
        return symbolMap[name]
    }

    func addFunctionSymbol(_ target: FunctionSymbol.Target,
                           flags: SymbolFlags) -> FunctionSymbol
    {
        guard let existing = symbolMap[target.name] else {
            let newSymbol = FunctionSymbol(target: target, flags: flags)
            symbolMap[target.name] = .function(newSymbol)
            return newSymbol
        }
        guard case let .function(existingFn) = existing else {
            fatalError("""
                Error: symbol type mismatch: \(existing.name)
                expected to be function but defined as \(existing)
            """)
        }
        // TODO: Handle flags
        switch (existingFn.target, target) {
        case let (.undefined, .defined(newTarget)):
            existingFn.target = .defined(newTarget)
            return existingFn
        case (.undefined, .undefined), (.defined, .undefined):
            return existingFn
        case let (.defined(existing), .defined(newTarget)):
            fatalError("""
                Error: symbol conflict: \(existing.name)
                >>> defined in \(newTarget.binary.filename)
                >>> defined in \(existing.binary.filename)
            """)
        }
    }

    func addGlobalSymbol(_ target: GlobalSymbol.Target,
                         flags: SymbolFlags) -> GlobalSymbol
    {
        guard let existing = symbolMap[target.name] else {
            let newSymbol = GlobalSymbol(target: target, flags: flags)
            symbolMap[target.name] = .global(newSymbol)
            return newSymbol
        }

        guard case let .global(existingGlobal) = existing else {
            fatalError("""
                Error: symbol type mismatch: \(existing.name)
                expected to be function but defined as \(existing)
            """)
        }
        switch (existingGlobal.target, target) {
        case let (.undefined, .defined(newTarget)):
            existingGlobal.target = .defined(newTarget)
            return existingGlobal
        case (.undefined, .undefined), (.defined, .undefined):
            return existingGlobal
        case let (.defined(existing), .defined(newTarget)):
            fatalError("""
                Error: symbol conflict: \(existing.name)
                >>> defined in \(newTarget.binary.filename)
                >>> defined in \(existing.binary.filename)
            """)
        }
    }

    func addDataSymbol(_ target: DataSymbol.Target,
                       flags: SymbolFlags) -> DataSymbol
    {
        guard let existing = symbolMap[target.name] else {
            let newSymbol = DataSymbol(target: target, flags: flags)
            symbolMap[target.name] = .data(newSymbol)
            return newSymbol
        }

        guard case let .data(existingData) = existing else {
            fatalError("""
                Error: symbol type mismatch: \(existing.name)
                expected to be function but defined as \(existing)
            """)
        }
        switch (existingData.target, target) {
        case let (.undefined, .defined(newTarget)):
            existingData.target = .defined(newTarget)
            return existingData
        case (.undefined, .undefined), (.defined, .undefined):
            return existingData
        case let (.defined(existing), .defined(newTarget)):
            fatalError("""
                Error: symbol conflict: \(existing.name)
                >>> defined in \(newTarget.binary.filename)
                >>> defined in \(existing.binary.filename)
            """)
        }
    }
}
