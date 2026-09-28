#!/bin/bash
# Build the VR 30-FPS ROM (Ares/PicoDrive-ready) from this repository.
#
# Needs: the repo's normal toolchain (tools/vasmm68k_mot, python3) plus a
# GNU SH toolchain (sh-elf-as/ld/objcopy/nm).  Set SH_PREFIX if it is not on
# PATH, e.g. SH_PREFIX=/opt/sh-elf/bin/sh-elf-
# Output: build/vr30fps.32x
set -e
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
FPS=$ROOT/experiments/fps30
OUT=$ROOT/build/fps30
SH=${SH_PREFIX:-sh-elf-}
case "$SH" in */*) export PATH="$(dirname "$SH"):$PATH" ;; esac   # the Makefile calls sh-elf-* too
mkdir -p "$OUT"
cd "$ROOT"

# 1. 68K + SH2 sources: scheduler, interpolation and render patches
make experimental-40fps-interp-fps-ares-rom >/dev/null   # generates all SH2 includes
tools/vasmm68k_mot -Fbin -m68000 -no-opt -spaces -quiet -D VR60_MODE0_ONLY=1 \
  -D VR60_EXPERIMENTAL_40FPS_INTERP=1 -D VR60_EXPERIMENTAL_COLD_BOOT_RENDER_PATCHES=1 \
  -D VR60_EXPERIMENTAL_ONCHIP_VERTEX_FAST=1 -D VR60_EXPERIMENTAL_ONCHIP_VERTEX_NOP_REMOVE=1 \
  -D VR60_EXPERIMENTAL_ONCHIP_VERTEX_BT_SCHEDULE=1 -D VR60_EXPERIMENTAL_SLAVE_CLEAR_OVERLAP=1 \
  -D VR60_EXPERIMENTAL_SCANLINE_PAIR_FUSED=1 -D VR60_FPS_COUNTER=1 \
  -D VR60_EXPERIMENTAL_30FPS_SCHED=1 \
  -D VR60_30_CAMONLY=1 -D VR60_30_EARLY_AUTH=1 -D VR60_30_AUTH3F=1 \
  -D VR60_30_PRESENT_WAIT=220 -D VR60_30_VBLANK_GUARD=1 -D VR60_30_CARS=1 \
  -D VR60_30_ANGLE_WRAP=1 -D VR60_30_HEADING_WRAP=1 -D VR60_30_DEMO=1 \
  -o "$OUT/sched.32x" disasm/vrd.asm
python3 tools/make_ares_rom.py "$OUT/sched.32x" "$OUT/sched_ares.32x"

# 2. SH2 helpers
asm() {  # name link_address|""
  ${SH}as --isa=sh2 -big -o "$OUT/$1.o" "$FPS/sh2/$1.s"
  if [ -n "$2" ]; then
    ${SH}ld -Ttext "$2" -o "$OUT/$1.elf" "$OUT/$1.o"
    ${SH}objcopy -O binary --only-section=.text "$OUT/$1.elf" "$OUT/$1.bin"
  else
    ${SH}objcopy -O binary -j .text "$OUT/$1.o" "$OUT/$1.bin"
  fi
}
asm mdrv 0x02306000
asm h3dc ""
asm cclr ""
asm hud9 0x02307500 2>/dev/null   # (branch-relaxation warnings are expected)
asm fsw  0x02307700
asm pw   0x02307A00
MSOLID=0x$(${SH}nm "$OUT/mdrv.elf" | awk '$3=="msolid"{print $1}')

# 3. patch
python3 "$FPS/make_band_rom.py" "$OUT/sched_ares.32x" "$OUT" "$MSOLID" "$OUT/band.32x"
python3 "$FPS/pwpatch.py" "$OUT/band.32x" "$ROOT/build/vr30fps.32x" "$OUT/pw.bin"
echo "built build/vr30fps.32x"
