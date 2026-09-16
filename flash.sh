#!/usr/bin/env bash
# Build and flash the MeshStar relay through the STM32 ROM bootloader.
#   ./flash.sh [/dev/ttyUSB0]
# Before running: hold BOOT0, press and release RESET, release BOOT0.
# The DX-LR30's CH340 has no DTR/RTS wiring, so the bootloader must be
# entered by hand, and this board's bootloader talks at 57600 baud.
# Needs: rustup target thumbv7m-none-eabi, llvm-tools, `pip install stm32loader`.
set -euo pipefail
PORT="${1:-/dev/ttyUSB0}"
cd "$(dirname "$0")"
cargo build --release
ELF=target/thumbv7m-none-eabi/release/meshstar-specter-dx-lr30
HOST="$(rustc -vV | sed -n 's/^host: //p')"
OBJCOPY="$(rustc --print sysroot)/lib/rustlib/$HOST/bin/llvm-objcopy"
"$OBJCOPY" -O binary "$ELF" target/relay.bin
"$(rustc --print sysroot)/lib/rustlib/$HOST/bin/llvm-size" "$ELF"
python3 -m stm32loader -p "$PORT" -b 57600 -f F1 -e -w -v target/relay.bin
echo "flashed. Press RESET (BOOT0 released). Console: python3 -m serial.tools.miniterm $PORT 115200"
