#!/usr/bin/env python3
"""Create an Ares-compatible Mega Drive / 32X ROM image.

The VR60 research build intentionally stops at 0x3f0000 for an old PicoDrive
compatibility workaround even though its header declares a 4 MiB cartridge.
Ares validates the declared range, so keep the canonical research ROM intact
and generate a separate, padded image with a recalculated Sega checksum.
"""

from __future__ import annotations

import argparse
import hashlib
from pathlib import Path


CHECKSUM_OFFSET = 0x18E
ROM_START_OFFSET = 0x1A0
ROM_END_OFFSET = 0x1A4
CHECKSUM_DATA_OFFSET = 0x200
MAX_SUPPORTED_SIZE = 0x400000


def read_be32(data: bytes | bytearray, offset: int) -> int:
    return int.from_bytes(data[offset : offset + 4], "big")


def sega_checksum(data: bytes | bytearray) -> int:
    payload = data[CHECKSUM_DATA_OFFSET:]
    if len(payload) & 1:
        payload += b"\xff"
    return sum(
        int.from_bytes(payload[index : index + 2], "big")
        for index in range(0, len(payload), 2)
    ) & 0xFFFF


def make_ares_rom(source: Path, destination: Path) -> tuple[int, int, str]:
    if source.resolve() == destination.resolve():
        raise ValueError("source and destination must be different files")

    rom = bytearray(source.read_bytes())
    if len(rom) < CHECKSUM_DATA_OFFSET:
        raise ValueError("input is too small to contain a Mega Drive ROM header")

    rom_start = read_be32(rom, ROM_START_OFFSET)
    rom_end = read_be32(rom, ROM_END_OFFSET)
    declared_size = rom_end - rom_start + 1

    if rom_start != 0:
        raise ValueError(f"unsupported ROM start 0x{rom_start:08X}; expected zero")
    if declared_size <= 0 or declared_size > MAX_SUPPORTED_SIZE:
        raise ValueError(f"unsupported declared ROM size 0x{declared_size:X}")
    if len(rom) > declared_size:
        raise ValueError(
            f"input size 0x{len(rom):X} exceeds declared size 0x{declared_size:X}"
        )

    rom.extend(b"\xff" * (declared_size - len(rom)))
    checksum = sega_checksum(rom)
    rom[CHECKSUM_OFFSET : CHECKSUM_OFFSET + 2] = checksum.to_bytes(2, "big")

    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_bytes(rom)
    digest = hashlib.sha256(rom).hexdigest()
    return len(rom), checksum, digest


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Pad a 32X ROM to its declared size and update its Sega checksum."
    )
    parser.add_argument("source", type=Path, help="canonical input ROM")
    parser.add_argument("destination", type=Path, help="separate Ares ROM output")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    size, checksum, digest = make_ares_rom(args.source, args.destination)
    print(f"Ares ROM: {args.destination}")
    print(f"Size: 0x{size:X} ({size} bytes)")
    print(f"Checksum: 0x{checksum:04X}")
    print(f"SHA-256: {digest}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
