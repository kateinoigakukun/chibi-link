struct ElementSegment {
    let offset: Offset
    let elementCount: Int
}

typealias InputElementSection = GenericInputSection<InputVectorContent<ElementSegment>>
