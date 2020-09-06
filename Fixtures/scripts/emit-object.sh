#!/bin/bash

source scripts/config.sh

source=$1
output=$2

$SWIFTC -emit-object $source -target wasm32-unknown-wasi -sdk $SWIFT_TOOLCHAIN/share/wasi-sysroot -o $output
