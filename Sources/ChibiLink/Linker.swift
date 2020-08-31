class Linker {
    private var inputs: [LinkerInputBinary] = []

    func append(_ binary: LinkerInputBinary) {
        inputs.append(binary)
    }
}
