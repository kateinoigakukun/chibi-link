# chibi-link

A toy linker for WebAssembly object files.

Features

- Support linking object files produced by LLVM
- Pure Swift
- No Foundation dependency

## How to use

### Link

```sh
$ swift run lib.o main.o -o output.wasm
```

### Link WebAssembly on WebAssembly runtime 😲

```sh
$ ~/Library/Developer/Toolchains/swift-wasm-5.3.0-RELEASE.xctoolchain/usr/bin/swift --version
SwiftWasm Swift version 5.3 (swiftlang-5.3.0)
Target: x86_64-apple-darwin19.6.0

$ ~/Library/Developer/Toolchains/swift-wasm-5.3.0-RELEASE.xctoolchain/usr/bin/swift build --triple wasm32-unknown-wasi
$ wasmtime run --mapdir=/var/tmp::$(pwd) .build/wasm32-unknown-wasi/release/chibi-link.wasm -- \
  /var/tmp/lib.o /var/tmp/main.o -o /var/tmp/output.wasm
```
