let magic: [UInt8] = [0x00, 0x61, 0x73, 0x6D]
let version: [UInt8] = [0x01, 0x00, 0x00, 0x00]

typealias Index = Int
typealias Offset = Int
typealias Size = Int

enum SectionCode: UInt8, CaseIterable {
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
    case call = 0x10
}

enum RelocType: UInt8, Equatable {
    case FUNCTION_INDEX_LEB     =  0
    case TABLE_INDEX_SLEB       =  1
    case TABLE_INDEX_I32        =  2
    case MEMORY_ADDR_LEB        =  3
    case MEMORY_ADDR_SLEB       =  4
    case MEMORY_ADDR_I32        =  5
    case TYPE_INDEX_LEB         =  6
    case GLOBAL_INDEX_LEB       =  7
    case FUNCTION_OFFSET_I32    =  8
    case SECTION_OFFSET_I32     =  9
//  case EVENT_INDEX_LEB        = 10
    case MEMORY_ADDR_REL_SLEB   = 11
    case TABLE_INDEX_REL_SLEB   = 12
    case GLOBAL_INDEX_I32       = 13
    case MEMORY_ADDR_LEB64      = 14
    case MEMORY_ADDR_SLEB64     = 15
    case MEMORY_ADDR_I64        = 16
    case MEMORY_ADDR_REL_SLEB64 = 17
    case TABLE_INDEX_SLEB64     = 18
    case TABLE_INDEX_I64        = 19
//  case TABLE_NUMBER_LEB       = 20
//  case MEMORY_ADDR_TLS_SLEB   = 21
//  case FUNCTION_OFFSET_I64    = 22
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
    case section = 3
    case event = 4
    case table = 5
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

let PAGE_SIZE: Int = 65536

let FUNC_TYPE_CODE: UInt8 = 0x60
