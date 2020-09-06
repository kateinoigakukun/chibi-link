#!/bin/bash

set -e

fixture="$(cd "$(dirname $0)/../" && pwd)"
scripts=$fixture/scripts
source $scripts/config.sh

workdir=$(mktemp -d)
cd $workdir

# Extract object files from libswiftSwiftOnoneSupport.a to force link
mkdir -p $workdir/swiftSwiftOnoneSupport
pushd $workdir/swiftSwiftOnoneSupport > /dev/null
llvm-ar x $SWIFT_TOOLCHAIN/lib/swift_static/wasi/libswiftSwiftOnoneSupport.a
popd > /dev/null

# Link shared library
"$WASM_LD" \
  $SWIFT_TOOLCHAIN/share/wasi-sysroot/lib/wasm32-wasi/crt1.o \
  $SWIFT_TOOLCHAIN/lib/swift_static/wasi/wasm32/swiftrt.o \
  $SWIFT_TOOLCHAIN/lib/clang/10.0.0/lib/wasi/libclang_rt.builtins-wasm32.a \
  $workdir/swiftSwiftOnoneSupport/*.o \
  -L$SWIFT_TOOLCHAIN/lib/swift_static/wasi \
  -L$SWIFT_TOOLCHAIN/share/wasi-sysroot/usr/lib/swift \
  -L$SWIFT_TOOLCHAIN/share/wasi-sysroot/lib/wasm32-wasi \
  -lswiftCore \
  -lswiftImageInspectionShared \
  -lswiftWasiPthread \
  -licuuc \
  -licudata \
  -ldl \
  -lc++ \
  -lc++abi \
  -lc \
  -lm \
  -lwasi-emulated-mman \
  --error-limit=0 \
  --no-gc-sections \
  --no-threads \
  --allow-undefined \
  --relocatable \
  -o $fixture/output/shared_lib.wasm
