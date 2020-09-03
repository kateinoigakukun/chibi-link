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
        case .defined(let target): return target.name
        case .undefined(let target): return target.name
        }
    }
}

final class FunctionSymbol {
    typealias Target = SymbolTarget<IndexableTarget, FunctionImport>
    fileprivate var target: Target
    let flags: SymbolFlags
    fileprivate init(target: Target, flags: SymbolFlags) {
        self.target = target
        self.flags = flags
    }
}

final class GlobalSymbol {
    typealias Target = SymbolTarget<IndexableTarget, GlobalImport>
    fileprivate var target: Target
    let flags: SymbolFlags
    
    fileprivate init(target: Target, flags: SymbolFlags) {
        self.target = target
        self.flags = flags
    }
}

final class DataSymbol {
    struct DefinedSegment: DefinedTarget {
        let segmentIndex: Index
        let name: String
        let offset: Offset
        let size: Size
        let binary: InputBinary
    }
    struct UndefinedSegment: UndefinedTarget {
        let name: String
    }
    typealias Target = SymbolTarget<DefinedSegment, UndefinedSegment>
    
    fileprivate var target: Target
    let flags: SymbolFlags
    
    fileprivate init(target: Target, flags: SymbolFlags) {
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
        case .function(let symbol):
            return symbol.target.name
        case .data(let symbol):
            return symbol.target.name
        case .global(let symbol):
            return symbol.target.name
        }
    }
}

class SymbolTable {
    private var symbolMap: [String: Symbol] = [:]

    func addFunctionSymbol(_ target: FunctionSymbol.Target,
                           flags: SymbolFlags) -> FunctionSymbol {
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
                         flags: SymbolFlags) -> GlobalSymbol {
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
                       flags: SymbolFlags) -> DataSymbol {
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