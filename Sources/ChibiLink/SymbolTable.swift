enum Symbol {
    case function
    case global
    case data
}

struct SymbolFlags {
    let rawValue: UInt32
    private var binding: UInt32 { rawValue & SYMBOL_BINDING_MASK }
    var isWeak: Bool { binding == SYMBOL_BINDING_WEAK }
    var isLocal: Bool { binding == SYMBOL_BINDING_LOCAL }
    private var visibility: UInt32 { rawValue & SYMBOL_VISIBILITY_MASK }
    var isHidden: Bool { visibility == SYMBOL_VISIBILITY_HIDDEN }
    var isExported: Bool { rawValue & SYMBOL_EXPORTED != 0 }
}

typealias IndexableTarget = (
    itemIndex: Index,
    name: String, InputBinary
)

enum SymbolTarget<Target, Import> {
    case defined(Target)
    case undefined(Import)
}

final class FunctionSymbol {
    typealias Target = SymbolTarget<IndexableTarget, FunctionImport>
    let target: Target
    let flags: SymbolFlags
    init(target: Target, flags: SymbolFlags) {
        self.target = target
        self.flags = flags
    }
}

final class GlobalSymbol {
    typealias Target = SymbolTarget<IndexableTarget, GlobalImport>
    let target: Target
    let flags: SymbolFlags
    
    internal init(target: Target, flags: SymbolFlags) {
        self.target = target
        self.flags = flags
    }
}

final class DataSymbol {
    typealias Name = String
    typealias Pointer = (
        segmentIndex: Index,
        offset: Offset,
        size: Size
    )
    typealias Target = SymbolTarget<Pointer, Name>
    
    let target: Target
    let flags: SymbolFlags
    
    internal init(target: Target, flags: SymbolFlags) {
        self.target = target
        self.flags = flags
    }
    
}

class SymbolTable {
    
    func addFunctionSymbol(_ symbol: FunctionSymbol) {
        
    }

    func addGlobalSymbol(_ symbol: GlobalSymbol) {
        
    }
    
    func addDataSymbol(_ symbol: DataSymbol) {
        
    }
}
