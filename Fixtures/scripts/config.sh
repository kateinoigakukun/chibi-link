if [[ -z "${SWIFT_TOOLCHAIN}" ]]; then
  echo "ERROR: Please set SWIFT_TOOLCHAIN env variable"
  exit 1
fi
export WASM_LD=$SWIFT_TOOLCHAIN/bin/wasm-ld
export LLVM_AR=/usr/local/opt/llvm/bin/llvm-ar
export SWIFTC=$SWIFT_TOOLCHAIN/bin/swiftc
