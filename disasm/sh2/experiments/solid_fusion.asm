/* Approved isolated solid-coordinator fusion; feature OFF by default.
 * Exact 580-byte overlay. Absolute callback pointer preserves SDRAM caller.
 * Callback/soft-fill instruction bytes unchanged; 01F0 is a LIVE RTS delay.
 * Only dead 01CC and 01F2 become stride/color literals. See complete proposal:
 * analysis/VR60_SOLID_FUSION_20260921.md and hash-bound layout-proof-r5.
 */
.section .text
.global fusion_begin
fusion_begin:
o000:
.short 0x4f22
o002:
mov.l purge_base,r1
o004:
.short 0x58e9
o006:
.short 0xe000
o008:
.short 0x218b
o00a:
.short 0x2102
o00c:
.short 0x1104
o00e:
.short 0x1108
o010:
.short 0x110c
o012:
.short 0x6983
o014:
.short 0x7920
o01e:
.short 0x6185
o020:
.short 0x6285
o022:
.short 0x4111
o024:
bf o0c8
o026:
.short 0x8581
o028:
.short 0x6523
o02a:
.short 0x3200
o02c:
bt o01e
o02e:
.short 0x3208
o030:
.short 0x4215
o032:
bt o0c8
o034:
mov.l coeff_base,r0
o036:
.short 0x662b
o038:
.short 0x4200
o03a:
.short 0x032d
o03c:
.short 0x8580
o03e:
.short 0x6c13
o040:
.short 0x4c28
o042:
.short 0x3108
o044:
.short 0x231f
o046:
.short 0x6195
o048:
.short 0x6295
o04a:
.short 0x4111
o04c:
bf o0c8
o04e:
.short 0x8591
o050:
.short 0x3200
o052:
bt o046
o054:
.short 0x3208
o056:
.short 0x4215
o058:
bt o0c8
o05a:
.short 0x0a1a
o05c:
.short 0x4a08
o05e:
mov.l coeff_base,r0
o060:
.short 0x672b
o062:
.short 0x4200
o064:
.short 0x032d
o066:
.short 0x8590
o068:
.short 0x6d13
o06a:
.short 0x4d28
o06c:
.short 0x3108
o06e:
.short 0x231f
o070:
mov.w fraction_mask,r0
extu.w r0,r0
o072:
.short 0x2c0b
o074:
.short 0x2d0b
o076:
.short 0x0b1a
o078:
.short 0x4b08
o07a:
.short 0x3dc0
o07c:
bt o094
o07e:
.short 0x3dc7
o080:
bt o0b0
o082:
bra o09a
o084:
.short 0x6063
o094:
.short 0x3ba7
o096:
bt o0b0
o098:
.short 0x6063
o09a:
.short 0x6673
o09c:
.short 0x6703
o09e:
.short 0x6083
o0a0:
.short 0x6893
o0a2:
.short 0x6903
o0a4:
.short 0x60a3
o0a6:
.short 0x6ab3
o0a8:
.short 0x6b03
o0aa:
.short 0x60c3
o0ac:
.short 0x6cd3
o0ae:
.short 0x6d03
o0b0:
bsr setup
o0b2:
.short 0x51e9
o0b4:
mov r14,r0
tst #4,r0
bf dither_call
add #-22,r0
lds r0,pr
jmp @r14
mov r5,r1
o0c8:
.short 0x4f26
o0ca:
.short 0x000b
o0cc:
.short 0x0009
o0ce:
.short 0x6185
o0d0:
.short 0x6285
o0d2:
.short 0x8581
o0d4:
.short 0x4011
o0d6:
bf o12c
o0d8:
.short 0x3200
o0da:
bt o0ce
o0dc:
.short 0x3208
o0de:
.short 0x4215
o0e0:
bt o0c8
o0e2:
mov.l coeff_base,r0
o0e4:
.short 0x662b
o0e6:
.short 0x4200
o0e8:
.short 0x032d
o0ea:
.short 0x8580
o0ec:
.short 0x6c13
o0ee:
.short 0x4c28
o0f0:
.short 0x3108
o0f2:
.short 0x231f
o0f4:
.short 0x0a1a
o0f6:
.short 0x4a08
o0f8:
.short 0x4710
o0fa:
bf/s o0b4
o0fc:
.short 0x3dbc
o0fe:
.short 0x6195
o100:
.short 0x6295
o102:
.short 0x8591
o104:
.short 0x3200
o106:
bt o0fe
o108:
.short 0x3208
o10a:
.short 0x4215
o10c:
bt o0c8
o10e:
mov.l coeff_base,r0
o110:
.short 0x672b
o112:
.short 0x4200
o114:
.short 0x032d
o116:
.short 0x8590
o118:
.short 0x6d13
o11a:
.short 0x4d28
o11c:
.short 0x3108
o11e:
.short 0x231f
o120:
.short 0x0b1a
o122:
bra o0b4
o124:
.short 0x4b08
o12c:
.short 0x3dbc
o12e:
.short 0x6153
o130:
.short 0x4e2b
o132:
.short 0x4f26
dither_setup:
and r0,r4
mov r5,r0
tst #1,r0
bf dither_parity
swap.b r4,r4
dither_parity:
mov.l dither_base,r0
shll8 r5
shll r5
add r0,r5
dither_wait:
mov.w @(10,gbr),r0
tst #2,r0
bf dither_wait
rts
add #108,r14
purge_base:
.long 0x40000000
coeff_base:
.long 0x060048d0
setup:
mov.l callback_pointer,r14
.short 0x851f
mov.w color_mask,r4
tst #2,r0
bf dither_setup
and r4,r0
swap.b r0,r4
or r0,r4
mov.l solid_base,r0
shll8 r5
shll r5
rts
add r0,r5
dither_call:
.short 0x4e0b
o0b6:
.short 0x6153
o0b8:
mov.w stride,r0
o0ba:
.short 0x350c
o0bc:
.short 0x4610
o0be:
bf/s o0f8
o0c0:
.short 0x3cac
o0c2:
bra o0d0
o0c4:
.short 0x6185
solid_base:
.long 0x24004000
dither_base:
.long 0x24024000
callback_pointer:
.long 0xc0000188
fraction_mask:
.short 0x8000
solid_continue:
mov.w stride,r0
add r0,r5
dt r6
bf/s solid_right
add r10,r12
bra o0d0
mov.w @r8+,r1
solid_right:
dt r7
bt/s o0fe
add r11,r13
mov r5,r1
solid_callback:
.short 0x62c9
.short 0x622f
.short 0x63d9
.short 0x633f
.short 0x312c
.short 0x3320
.short 0x891e
.short 0xc505
.short 0xc802
.short 0x8ffc
.short 0xe001
.short 0x2208
.short 0x8902
.short 0x2140
.short 0x7101
.short 0x7201
.short 0x2308
.short 0x8f01
.short 0x6033
.short 0x0544
.short 0x3028
.short 0x7001
.short 0xe202
.short 0x3023
.short 0x8f0a
.short 0x4001
.short 0x70ff
.short 0xc102
.short 0x6013
.short 0x4001
.short 0xc103
.short 0x6043
.short 0x000b
.short 0xc104
stride:
.short 0x0200
.short 0xc104
.short 0x000b
.short 0x0009
.short 0xc505
.short 0xc802
.short 0x8bfc
.short 0x000b
.short 0x2140
.short 0xe202
.short 0x3023
.short 0x8bf5
.short 0x4001
.short 0x2141
.short 0x4010
.short 0x8ffc
.short 0x7102
.short 0x000b
.short 0x0009
color_mask:
.short 0xff00
.short 0x62c9
.short 0x622f
.short 0x63d9
.short 0x633f
.short 0x6448
.short 0x313c
.short 0x3320
.short 0x8917
.short 0x6033
.short 0xc801
.short 0x8f03
.short 0x6048
.short 0x2100
.short 0x71ff
.short 0x73ff
.short 0x7101
.short 0x6033
.short 0x3028
.short 0x7001
.short 0xe302
.short 0x3033
.short 0x8f03
.short 0x4001
.short 0x4010
.short 0x8ffd
.short 0x2145
.short 0x6023
.short 0xc801
.short 0x8900
.short 0x2144
.short 0x000b
.short 0x0009
.short 0x6023
.short 0xc801
.short 0x8b02
.short 0x6048
.short 0x000b
.short 0x2100
.short 0x000b
.short 0x2140


