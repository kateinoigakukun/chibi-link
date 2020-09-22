class FunctionImport {
    let module: String
    let field: String
    let signatureIdx: Int
    weak var selfBinary: InputBinary?

    init(module: String, field: String, signatureIdx: Int, selfBinary: InputBinary) {
        self.module = module
        self.field = field
        self.signatureIdx = signatureIdx
        self.selfBinary = selfBinary
    }
}

class GlobalImport {
    internal init(module: String, field: String, type: ValueType, mutable: Bool) {
        self.module = module
        self.field = field
        self.type = type
        self.mutable = mutable
    }

    let module: String
    let field: String
    let type: ValueType
    let mutable: Bool
}

class Export {
    let kind: ExternalKind
    let name: String
    let index: Index

    init(kind: ExternalKind, name: String, index: Index) {
        self.kind = kind
        self.name = name
        self.index = index
    }
}

struct InitFunction {
    let priority: UInt32
    let symbolIndex: Index
    weak var binary: InputBinary!
}

class InputBinary {
    let filename: String
    let data: [UInt8]

    var sections: [InputSection] = []
    var funcImports: [FunctionImport] = []
    var globalImports: [GlobalImport] = []
    var exports: [Export] = []
    var functionCount: Int!
    var debugNames: [String] = []
    var symbols: [Symbol] = []
    var initFunctions: [InitFunction] = []

    init(filename: String, data: [UInt8]) {
        self.filename = filename
        self.data = data
    }
}
