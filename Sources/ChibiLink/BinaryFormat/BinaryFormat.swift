let magic: [UInt8] = [0x00, 0x61, 0x73, 0x6D]
let version: [UInt8] = [0x01, 0x00, 0x00, 0x00]

typealias Index = Int
typealias Offset = Int
typealias Size = Int

enum BinarySection: UInt8, CaseIterable {
    case custom = 0
    case type = 1
    case `import` = 2
    case function = 3
    case table = 4
    case memory = 5
    case global = 6
    case export = 7
    case start = 8
    case elem = 9
    case code = 10
    case data = 11
    case dataCount = 12
}

enum NameSectionSubsection: UInt8 {
    case function = 1
}

enum ExternalKind: UInt8, Equatable {
    case `func` = 0
    case table = 1
    case memory = 2
    case global = 3
    case except = 4
}

enum ValueType: UInt8, Equatable {
    case i32 = 0x7F
    case i64 = 0x7E
    case f32 = 0x7D
    case f64 = 0x7C
}

enum ElementType: UInt8, Equatable {
    case funcRef = 0x70
}

enum ConstOpcode: UInt8 {
    case i32Const = 0x41
    case i64Const = 0x42
    case f32Const = 0x43
    case f64Const = 0x44
}

enum Opcode: UInt8 {
    case end = 0x0B
}

enum RelocType: UInt8, Equatable {
    case functionIndexLEB = 0
    case tableIndexSLEB = 1
    case tableIndexI32 = 2
    case memoryAddressLEB = 3
    case memoryAddressSLEB = 4
    case memoryAddressI32 = 5
    case typeIndexLEB = 6
    case globalIndexLEB = 7
    case functionOffsetI32 = 8
    case sectionOffsetI32 = 9
//    case eventIndexLeb = 10
    case memoryAddressRelSLEB = 11
    case tableIndexRelSLEB = 12
    case globalIndexI32 = 13
    case memoryAddressLeb64 = 14
    case memoryAddressSLEB64 = 15
    case memoryAddressI64 = 16
    case memoryAddressRelSLEB64 = 17
    case tableIndexSLEB64 = 18
    case tableIndexI64 = 19
}

let LIMITS_HAS_MAX_FLAG: UInt8 = 0x1
let LIMITS_IS_SHARED_FLAG: UInt8 = 0x2
struct Limits {
    var initial: Size
    var max: Size?
    var isShared: Bool
}

enum LinkingEntryType: UInt8 {
    case segmentInfo = 5
    case initFunctions = 6
    case comdatInfo = 7
    case symbolTable = 8
}

enum SymbolType: UInt8 {
    case function = 0
    case data = 1
    case global = 2
}

let SYMBOL_FLAG_UNDEFINED: UInt32 = 0x10

let SYMBOL_VISIBILITY_MASK: UInt32 = 0x4
let SYMBOL_BINDING_MASK: UInt32 = 0x3

let SYMBOL_BINDING_GLOBAL: UInt32 = 0x0
let SYMBOL_BINDING_WEAK: UInt32 = 0x1
let SYMBOL_BINDING_LOCAL: UInt32 = 0x2

let SYMBOL_VISIBILITY_DEFAULT: UInt32 = 0x0
let SYMBOL_VISIBILITY_HIDDEN: UInt32 = 0x4

let SYMBOL_EXPORTED: UInt32 = 0x20
let SYMBOL_EXPLICIT_NAME: UInt32 = 0x40
let SYMBOL_NO_STRIP: UInt32 = 0x80