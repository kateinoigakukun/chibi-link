func debug(_ message: @autoclosure () -> String) {
    #if DEBUG
    print("Debug: \(message())")
    #endif
}

func warning(_ message: @autoclosure () -> String) {
    print("Warning: \(message())")
}
