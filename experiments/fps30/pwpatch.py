"""Post-patch: ring-status wait loops that newer PicoDrive DRCs can put to
sleep forever (SDRAM poll lost wakeup).
Usage: pwpatch.py in.32x out.32x [pw.bin]"""
import sys, os
here = os.path.dirname(os.path.abspath(__file__))
r = bytearray(open(sys.argv[1], 'rb').read())
b = open(sys.argv[3] if len(sys.argv) > 3 else os.path.join(here, 'pw', 'pw.bin'), 'rb').read()
assert set(r[0x307A00:0x307A00 + 0x80]) == {0xFF}
r[0x307A00:0x307A00 + len(b)] = b
T = {'A': 0x02307A00, 'B': 0x02307A14, 'C': 0x02307A28, 'D': 0x02307A3C}
def put(off, old, new):
    assert r[off:off + len(old) // 2] == bytes.fromhex(old), (hex(off), r[off:off + 12].hex())
    r[off:off + len(new) // 2] = bytes.fromhex(new)
def lit(off, new):
    assert r[off:off + 4] == bytes.fromhex('20000000'), hex(off)
    r[off:off + 4] = new.to_bytes(4, 'big')
S = 0x20000 - 0x06000000
put(0x060034EE + S, 'd00551e9210b851ec80889fc', 'd00551e9402b000900090009'); lit(0x23504, T['A'])
put(0x06003536 + S, '56e9d308236b853ec80889fc', '56e9d308432b000900090009'); lit(0x2355C, T['B'])
put(0x0600356C + S, '56e9d309236b853ec80889fc', '56e9d309432b000900090009'); lit(0x23594, T['C'])
put(0x06003862 + S, '56e9d111216b851ec80889fc', '56e9d111412b000900090009'); lit(0x238AC, T['D'])
# Car-select slowdown (B-004 single-shot cmd $22): restore the original
# 3-phase sh2_send_cmd ($00E35A, 90 bytes) and the Master's cmd $22 handler
# pointer. Car select goes back to the original 30 redraws/s (frame-exact).
put(0xE35A, '4a3900a1512066f823c800a1512613c100a1512623c900a1512a3f00e24813c000a15125301f13fc002200a1512113fc000100a151204a3900a1512166f84e754e714e714e714e714e714e714e714e714e714e714e714e714e71', '4a3900a1512066f823c900a1512833fc010100a1512c13fc002200a1512113fc000100a151204a3900a1512c66f833c000a1512833c100a1512a33fc010100a1512c4a3900a1512c66f823c800a1512833fc010100a1512c4e75')
put(0x20808, '023010f0', '06005198')
# mdrv .wait_prev: bf -> bf/s with the following "mov #1,r13" as delay slot
i = r.find(bytes.fromhex('85be88088bfced01'), 0x300000)
if i > 0:
    r[i + 4:i + 6] = bytes.fromhex('8ffc')
    print('mdrv wait_prev at', hex(i))
c = sum(int.from_bytes(r[k:k + 2], 'big') for k in range(0x200, len(r), 2)) & 0xFFFF
r[0x18E:0x190] = c.to_bytes(2, 'big')
open(sys.argv[2], 'wb').write(r)
import hashlib; print('sha256', hashlib.sha256(r).hexdigest())
