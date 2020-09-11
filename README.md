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
$ swift build -c release
$ wasmtime run --mapdir=/var/tmp::$(pwd) .build/wasm32-unknown-wasi/release/chibi-link -- \
  /var/tmp/lib.o /var/tmp/main.o -o /var/tmp/output.wasm
```
