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

protocol SynthesizedTarget: DefinedTarget {}

extension Never: SynthesizedTarget {
    var name: String {
        switch self {}
    }

    var context: String {
        switch self {}
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
    enum Synthesized: SynthesizedTarget {
        case ctorsCaller(inits: [InitFunction])
        case weakUndefStub(FunctionImport)
        var name: String {
            switch self {
            case .ctorsCaller: return "__wasm_call_ctors"
            case .weakUndefStub(let target):
                return target.name
            }
        }
        var context: String { return "_linker" }
    }

    fileprivate(set) var target: Target
    let flags: SymbolFlags
    init(target: Target, flags: SymbolFlags) {
        self.target = target
        self.flags = flags
    }
}

extension FunctionSymbol.Synthesized {
    func writeCtorsCallerCode(writer: BinaryWriter, inits: [InitFunction], relocator: Relocator) throws {
        let placeholder = try writer.writeSizePlaceholder()
        let codeStart = writer.offset
        try writer.writeULEB128(UInt32(0)) // num locals
        for initFn in inits {
            try writer.writeFixedUInt8(Opcode.call.rawValue)
            guard case let .function(symbol) = initFn.binary.symbols[initFn.symbolIndex] else {
                fatalError()
            }
            guard case let .defined(target) = symbol.target else {
                fatalError()
            }
            let index = relocator.functionIndex(for: target)
            try writer.writeULEB128(UInt32(index))
            // TODO: Drop returned values to support non-void return ctors based on signatures
        }
        try writer.writeFixedUInt8(Opcode.end.rawValue)
        let codeSize = writer.offset - codeStart
        try writer.fillSizePlaceholder(placeholder, value: codeSize)
    }

    func writeSignature(writer: BinaryWriter) throws {
        switch self {
        case .ctorsCaller:
            try writer.writeFixedUInt8(FUNC_TYPE_CODE)
            try writer.writeULEB128(UInt32(0)) // params
            try writer.writeULEB128(UInt32(0)) // returns
        case .weakUndefStub:
            // reuse signature
            break
        }
    }
    
    var reuseSignatureIndex: (InputBinary, Index)? {
        switch self {
        case .ctorsCaller: return nil
        case .weakUndefStub(let target):
            return (target.selfBinary!, target.signatureIdx)
        }
    }
    func writeCode(writer: BinaryWriter, relocator: Relocator) throws {
        switch self {
        case let .ctorsCaller(inits):
            try writeCtorsCallerCode(writer: writer, inits: inits, relocator: relocator)
        case .weakUndefStub:
            let unreachableFn: [UInt8] = [
                0x03, // ULEB:   length
                0x00, // ULEB:   num locals
                0x00, // Opcode: unreachable
                0x0b, // Opcode: end
            ]
            try writer.writeBytes(unreachableFn[...])
        }
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
        let offset: Offset
        let context: String
        let binary: InputBinary
    }

    struct UndefinedSegment: UndefinedTarget {
        let name: String
        let module: String = "env"
    }
    
    struct Synthesized: SynthesizedTarget {
        let name: String
        let context: String
        let address: Offset
    }

    typealias Target = SymbolTarget<DefinedSegment, UndefinedSegment, Synthesized>

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
    private var synthesizedFunctionIndexMap: [String: Index] = [:]
    private var synthesizedDataIndexMap: [String: Index] = [:]
    private var _synthesizedGlobals: [GlobalSymbol.Synthesized] = []
    private var _synthesizedFunctions: [FunctionSymbol.Synthesized] = []
    private var _synthesizedData: [DataSymbol.Synthesized] = []

    func symbols() -> [Symbol] {
        Array(symbolMap.values)
    }

    func synthesizedGlobalIndex(for target: GlobalSymbol.Synthesized) -> Index? {
        synthesizedGlobalIndexMap[target.name]
    }

    func synthesizedGlobals() -> [GlobalSymbol.Synthesized] {
        return _synthesizedGlobals
    }

    func synthesizedFuncIndex(for target: FunctionSymbol.Synthesized) -> Index? {
        synthesizedFunctionIndexMap[target.name]
    }

    func synthesizedFuncs() -> [FunctionSymbol.Synthesized] {
        return _synthesizedFunctions
    }

    func find(_ name: String) -> Symbol? {
        return symbolMap[name]
    }

    func addFunctionSymbol(_ target: FunctionSymbol.Target,
                           flags: SymbolFlags) -> FunctionSymbol
    {
        func indexSynthesizedFn() {
            guard case let .synthesized(target) = target else { return }
            synthesizedFunctionIndexMap[target.name] = _synthesizedFunctions.count
            _synthesizedFunctions.append(target)
        }
        guard let existing = symbolMap[target.name] else {
            let newSymbol = FunctionSymbol(target: target, flags: flags)
            symbolMap[target.name] = .function(newSymbol)
            indexSynthesizedFn()
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
        case (.undefined, .defined), (.undefined, .synthesized):
            existingFn.target = target
            indexSynthesizedFn()
            return existingFn
        case (.undefined, .undefined), (.defined, .undefined),
             (.synthesized, .undefined),
             (.defined, .defined) where flags.isWeak,
             (.synthesized, .synthesized) where flags.isWeak,
             (.defined, .synthesized) where flags.isWeak,
             (.synthesized, .defined) where flags.isWeak:
            return existingFn
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

    func addGlobalSymbol(_ target: GlobalSymbol.Target,
                         flags: SymbolFlags) -> GlobalSymbol
    {
        func indexSynthesizedGlobal() {
            guard case let .synthesized(target) = target else { return }
            synthesizedGlobalIndexMap[target.name] = _synthesizedGlobals.count
            _synthesizedGlobals.append(target)
        }
        guard let existing = symbolMap[target.name] else {
            let newSymbol = GlobalSymbol(target: target, flags: flags)
            symbolMap[target.name] = .global(newSymbol)
            indexSynthesizedGlobal()
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
            indexSynthesizedGlobal()
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
        func indexSynthesizedData() {
            guard case let .synthesized(target) = target else { return }
            synthesizedDataIndexMap[target.name] = _synthesizedData.count
            _synthesizedData.append(target)
        }
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
        case (.undefined, .defined), (.undefined, .synthesized):
            existingData.target = target
            indexSynthesizedData()
            return existingData
        case (.undefined, .undefined), (.defined, .undefined),
             (.synthesized, .undefined),
             (.defined, .defined) where flags.isWeak,
             (.synthesized, .synthesized) where flags.isWeak,
             (.defined, .synthesized) where flags.isWeak,
             (.synthesized, .defined) where flags.isWeak:
            return existingData
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
}

private func reportSymbolConflict(name: String, oldContext: String, newContext: String) -> Never {
    fatalError("""
        Error: symbol conflict: \(name)
        >>> defined in \(oldContext)
        >>> defined in \(newContext)
    """)
}
