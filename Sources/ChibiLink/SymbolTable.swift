struct SymbolFlags {
    let rawValue: UInt32
    private var binding: UInt32 { rawValue & SYMBOL_BINDING_MASK }
    var isWeak: Bool { binding == SYMBOL_BINDING_WEAK }
    var isLocal: Bool { binding == SYMBOL_BINDING_LOCAL }
    private var visibility: UInt32 { rawValue & SYMBOL_VISIBILITY_MASK }
    var isHidden: Bool { visibility == SYMBOL_VISIBILITY_HIDDEN }
    var isExported: Bool { rawValue & SYMBOL_EXPORTED != 0 }
    var isUndefined: Bool { rawValue & SYMBOL_FLAG_UNDEFINED != 0 }
}

protocol DefinedTarget {
    var name: String { get }
    var context: String { get }
}

protocol UndefinedTarget {
    var name: String { get }
    var module: String { get }
}

struct IndexableTarget: DefinedTarget {
    let itemIndex: Index
    let name: String
    let binary: InputBinary
    var context: String { binary.filename }
}

extension FunctionImport: UndefinedTarget {
    var name: String { field }
}

extension GlobalImport: UndefinedTarget {
    var name: String { field }
}

protocol SynthesizedTarget: DefinedTarget {
}

extension Never: SynthesizedTarget {
    var name: String {
        switch self {
        }
    }
    var context: String {
        switch self {
        }
    }
}

enum SymbolTarget<Target: DefinedTarget, Import: UndefinedTarget, Synthesized: SynthesizedTarget> {
    case defined(Target)
    case undefined(Import)
    case synthesized(Synthesized)

    var name: String {
        switch self {
        case let .defined(target): return target.name
        case let .undefined(target): return target.name
        case let .synthesized(target): return target.name
        }
    }
}

protocol SymbolProtocol {
    associatedtype Defined: DefinedTarget
    associatedtype Import: UndefinedTarget
    associatedtype Synthesized: SynthesizedTarget
    typealias Target = SymbolTarget<Defined, Import, Synthesized>
    var target: Target { get }
    var flags: SymbolFlags { get }
}

final class FunctionSymbol: SymbolProtocol {
    typealias Defined = IndexableTarget
    typealias Import = FunctionImport
    typealias Synthesized = Never

    fileprivate(set) var target: Target
    let flags: SymbolFlags
    init(target: Target, flags: SymbolFlags) {
        self.target = target
        self.flags = flags
    }
}

final class GlobalSymbol: SymbolProtocol {
    typealias Defined = IndexableTarget
    typealias Import = GlobalImport
    struct Synthesized: SynthesizedTarget {
        let name: String
        let context: String
        let type: ValueType
        let mutable: Bool
        let value: Int32
    }
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
        let segment: DataSegment
        let context: String
    }

    struct UndefinedSegment: UndefinedTarget {
        let name: String
        let module: String = "env"
    }

    typealias Target = SymbolTarget<DefinedSegment, UndefinedSegment, Never>

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

    #if DEBUG
    var function: FunctionSymbol? {
        guard case let .function(sym) = self else { return nil }
        return sym
    }
    var global: GlobalSymbol? {
        guard case let .global(sym) = self else { return nil }
        return sym
    }
    var data: DataSymbol? {
        guard case let .data(sym) = self else { return nil }
        return sym
    }
    #endif

    var isUndefined: Bool {
        func isUndef<T1, T2, T3>(_ target: SymbolTarget<T1, T2, T3>) -> Bool {
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
    private var synthesizedGlobalIndexMap: [String: Index] = [:]
    private var _synthesizedGlobals: [GlobalSymbol.Synthesized] = []

    func symbols() -> [Symbol] {
        Array(symbolMap.values)
    }

    func synthesizedGlobalIndex(for target: GlobalSymbol.Synthesized) -> Index? {
        synthesizedGlobalIndexMap[target.name]
    }
    
    func synthesizedGlobals() -> [GlobalSymbol.Synthesized] {
        return _synthesizedGlobals
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
        case (.defined, .defined) where flags.isWeak:
            return existingFn
        case let (.defined(existing), .defined(newTarget)):
            if flags.isWeak { return existingFn }
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
        
        defer {
            if case let .synthesized(target) = target {
                synthesizedGlobalIndexMap[target.name] = _synthesizedGlobals.count
                _synthesizedGlobals.append(target)
            }
        }
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
        case (.undefined, .defined), (.undefined, .synthesized):
            existingGlobal.target = target
            return existingGlobal
        case (.undefined, .undefined), (.defined, .undefined),
             (.synthesized, .undefined),
             (.defined, .defined) where flags.isWeak,
             (.synthesized, .synthesized) where flags.isWeak,
             (.defined, .synthesized) where flags.isWeak,
             (.synthesized, .defined) where flags.isWeak:
            return existingGlobal
        case let (.defined(existing as DefinedTarget), .defined(newTarget as DefinedTarget)),
             let (.synthesized(existing as DefinedTarget), .defined(newTarget as DefinedTarget)),
             let (.defined(existing as DefinedTarget), .synthesized(newTarget as DefinedTarget)),
             let (.synthesized(existing as DefinedTarget), .synthesized(newTarget as DefinedTarget)):
            reportSymbolConflict(
                name: existing.name,
                oldContext: existing.context, newContext: newTarget.context
            )
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
        case (.defined, .defined) where flags.isWeak:
            return existingData
        case let (.defined(existing), .defined(newTarget)):
            fatalError("""
                Error: symbol conflict: \(existing.name)
                >>> defined in \(newTarget.context)
                >>> defined in \(existing.context)
            """)
        }
    }
}

private func reportSymbolConflict(name: String, oldContext: String, newContext: String) -> Never {
    fatalError("""
        Error: symbol conflict: \(name)
        >>> defined in \(oldContext)
        >>> defined in \(newContext)
    """)
}
