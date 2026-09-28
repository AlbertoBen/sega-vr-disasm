#!/usr/bin/env python3
"""VR 30-FPS: apply the SH2 patches to the assembled 30-FPS scheduler ROM.

usage: make_band_rom.py in.32x bin_dir msolid_addr out.32x

bin_dir holds the assembled helpers (see build_vr30.sh):
  mdrv.bin  Master band driver (linked at 0x02306000)        -> file 0x306000
  h3dc.bin  Master command $3D, camera-only scene transfer   -> file 0x307000
  cclr.bin  CPU-store line clear (replaces the VDP fill)      -> file 0x307100
  hud9.bin  cached HUD type-9 sprite blit                     -> file 0x307500
  fsw.bin   render-job start waits for a pending FB swap      -> file 0x307700

Patches (every one checks the bytes it replaces first):
  * band split: Master copy of the 580-byte cmd1 rasterizer at 0x306800
    (file 0x23A70) with its four cache-purge stores NOPed and both callback
    literals retargeted (solid -> msolid CPU-store span, dither -> the copy's
    own 0x1F4 callback); literal 0x0600122C (file 0x2122C, only loaded by
    060011EE): join 06004438 -> 0x02306000 (the driver tail-jumps to 06004438)
  * Master command $3D -> h3dc (camera-only EXTRA)
  * 060044F6 VDP-fill line clear -> cclr
  * stock cmd $02: geometry before the join (same order as the $3F handler)
  * HUD type-9 RLE sprite -> hud9, via a trampoline in the 12 NOPs of the
    stock $02 handler (6000D10..6000D27)
  * job start (first Slave command send in 2304C20) -> fsw
Sega checksum recomputed.
"""
import hashlib, os, sys

src, bindir, msolid, out = sys.argv[1], sys.argv[2], int(sys.argv[3], 0), sys.argv[4]
rom = bytearray(open(src, 'rb').read())
DRV, RAS, OVL = 0x306000, 0x306800, 0x23A70


def blob(name):
    return open(os.path.join(bindir, name), 'rb').read()


def place(off, data, end):
    """write data at off; it must fit before end and land on unused (0xFF) ROM"""
    assert off + len(data) <= end, 'helper at %06X too large' % off
    assert set(rom[off:off + len(data)]) == {0xFF}, 'area %06X not free' % off
    rom[off:off + len(data)] = data


def put(off, old, new):
    assert rom[off:off + len(old) // 2] == bytes.fromhex(old), 'unexpected bytes at %06X' % off
    rom[off:off + len(new) // 2] = bytes.fromhex(new)


# --- band split -------------------------------------------------------------
place(DRV, blob('mdrv.bin'), RAS)
ras = bytearray(rom[OVL:OVL + 580])
for off, want in ((0x0A, 0x2102), (0x0C, 0x1104), (0x0E, 0x1108), (0x10, 0x110C)):
    assert int.from_bytes(ras[off:off + 2], 'big') == want
    ras[off:off + 2] = b'\x00\x09'
assert int.from_bytes(ras[0x15C:0x160], 'big') == 0xC0000188
assert int.from_bytes(ras[0x184:0x188], 'big') == 0xC00001F4
ras[0x15C:0x160] = msolid.to_bytes(4, 'big')
ras[0x184:0x188] = (0x02000000 + RAS + 0x1F4).to_bytes(4, 'big')
assert set(rom[RAS:RAS + 0x300]) == {0xFF}
rom[RAS:RAS + 580] = ras
put(0x2122C, '06004438', '%08x' % (0x02000000 + DRV))

# --- camera-only scene transfer (command $3D) ---------------------------------
place(0x307000, blob('h3dc.bin'), 0x307100)
put(0x20874, '06000490', '02307000')

# --- CPU line clear ---------------------------------------------------------
place(0x307100, blob('cclr.bin'), 0x307500)
put(0x244F6, 'de0d6023', 'de0d6023')
rom[0x244F6:0x24504] = bytes.fromhex('d002402b000900090009') + bytes.fromhex('02307100')

# --- stock cmd $02: geometry before the join --------------------------------
put(0x20D28, 'b2180009d011400b0009b0bf0009b1b90009', 'b2180009b0c20009b1bc0009d00f400b0009')

# --- cached HUD type-9 blit -------------------------------------------------
place(0x307500, blob('hud9.bin'), 0x307700)
put(0x20D10, '0009' * 12, 'a00a0009d001402b00090009' + '02307500' + '0009' * 4)
put(0x23CEE, '02fa', 'd048')

# --- job start waits for a pending frame-buffer swap -------------------------
place(0x307700, blob('fsw.bin'), 0x307A00)
put(0x304C74, '0600441c', '02307700')

payload = rom[0x200:]
ck = sum(int.from_bytes(payload[i:i + 2], 'big') for i in range(0, len(payload), 2)) & 0xFFFF
rom[0x18E:0x190] = ck.to_bytes(2, 'big')
open(out, 'wb').write(rom)
print('checksum %04X sha256 %s' % (ck, hashlib.sha256(rom).hexdigest()))
