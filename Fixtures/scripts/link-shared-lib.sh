#!/bin/bash

set -e

fixture="$(cd "$(dirname $0)/../" && pwd)"
scripts=$fixture/scripts
source $scripts/config.sh

workdir=$(mktemp -d)
cd $workdir

link-shared-object-library() {
  local inputs=(
    "$SWIFT_TOOLCHAIN/share/wasi-sysroot/lib/wasm32-wasi/crt1-command.o"
    "$SWIFT_TOOLCHAIN/lib/swift_static/wasi/wasm32/swiftrt.o"
    "$SWIFT_TOOLCHAIN/lib/clang/13.0.0/lib/wasi/libclang_rt.builtins-wasm32.a"
    "$SWIFT_TOOLCHAIN/lib/swift_static/wasi/libswiftWasiPthread.a"
    "$SWIFT_TOOLCHAIN/lib/swift_static/wasi/libswiftCore.a"
    "$SWIFT_TOOLCHAIN/lib/swift_static/wasi/libswift_Concurrency.a"
    "$SWIFT_TOOLCHAIN/lib/swift_static/wasi/libswiftSwiftOnoneSupport.a"
    "$SWIFT_TOOLCHAIN/lib/swift_static/wasi/libswiftWASILibc.a"
    "$SWIFT_TOOLCHAIN/lib/swift_static/wasi/libFoundation.a"
    "$SWIFT_TOOLCHAIN/lib/swift_static/wasi/libBlocksRuntime.a"
    "$SWIFT_TOOLCHAIN/share/wasi-sysroot/lib/wasm32-wasi/libc.a"
    "$SWIFT_TOOLCHAIN/share/wasi-sysroot/lib/wasm32-wasi/libc++.a"
    "$SWIFT_TOOLCHAIN/share/wasi-sysroot/lib/wasm32-wasi/libc++abi.a"
    "$SWIFT_TOOLCHAIN/lib/swift_static/wasi/libicuuc.a"
    "$SWIFT_TOOLCHAIN/lib/swift_static/wasi/libicudata.a"
    "$SWIFT_TOOLCHAIN/lib/swift_static/wasi/libicui18n.a"
    "$SWIFT_TOOLCHAIN/share/wasi-sysroot/lib/wasm32-wasi/libwasi-emulated-mman.a"
    "$SWIFT_TOOLCHAIN/share/wasi-sysroot/lib/wasm32-wasi/libwasi-emulated-signal.a"
    "$SWIFT_TOOLCHAIN/share/wasi-sysroot/lib/wasm32-wasi/libwasi-emulated-process-clocks.a"
  )
  local excludes=(
    "ImageInspectionCOFF.cpp.o"
  )
  local workdir=$(mktemp -d)
  local linkfile="$workdir/LinkInputs.filelist"

  # Extract object files from libswiftSwiftOnoneSupport.a to force link
  for obj in ${inputs[@]}; do
    if [[ $obj == *.o ]]; then
      echo $obj >> $linkfile
    else
      local obj_dir=$workdir/$(basename $obj)
      mkdir -p $obj_dir
      pushd $obj_dir > /dev/null
      "$SWIFT_TOOLCHAIN/bin/llvm-ar" x $obj

      for exobj in ${excludes[@]}; do
        rm -f $obj_dir/$exobj
      done
      popd > /dev/null
      echo $obj_dir/* >> $linkfile
    fi
  done
  echo $link_objects >> $linkfile

  "$SWIFT_TOOLCHAIN/bin/wasm-ld" \
    @$linkfile \
    --error-limit=0 \
    --no-gc-sections \
    --threads=1 \
    --allow-undefined \
    --relocatable --strip-debug \
    -o $fixture/output/shared_lib.wasm
}

link-shared-object-library
