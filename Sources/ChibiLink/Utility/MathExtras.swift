func align(_ value: Int, to align: Int) -> Int {
    assert(align != 0)
    return (value + align - 1) / align * align
}
