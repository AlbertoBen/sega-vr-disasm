/*
 * HUD type-9 (RLE sprite, drawn right-to-left with byte stores) replacement.
 * The RLE is decoded once into per-row zero-padded longword strips cached in
 * SDRAM (two slots, key: source + dst & 3), then blitted with longword stores
 * into the overwrite framebuffer mirror, where zero bytes are not written -
 * the result equals the RLE byte loop.  Sprites that do not fit are
 * remembered and drawn by the original loop.
 * In: r14 = entry (+4 dst, +8 src), r13 = row stride.  Clobbers r0-r9.
 * Slot header: +0 src, +4 dst&3, +8 rows, +10.. row long counts (bytes).
 */
        .text
        .global t9
        .equ    S0,      0x26016C00
        .equ    S1,      0x2600F800
        .equ    MISC,    0x26011A08      /* unused in S1's header? no: see below */
        .equ    MAXR,    112

t9:
        mov.l   @(8,r14),r8             /* src */
        mov.l   @(4,r14),r9             /* dst (exclusive right edge) */
        mov.l   L_fail,r5
        mov.l   @r5,r0
        cmp/eq  r8,r0
        bf      .go
        mov.l   L_orig9,r0
        jmp     @r0
        nop
.go:    mov     r9,r3
        mov     #3,r0
        and     r0,r3                   /* dst & 3 */
        mov.l   L_s0,r5
        mov.l   @r5,r0
        cmp/eq  r8,r0
        bf      .h1
        mov.l   @(4,r5),r0
        cmp/eq  r3,r0
        bt      .blit
.h1:    mov.l   L_s1,r5
        mov.l   @r5,r0
        cmp/eq  r8,r0
        bf      .miss
        mov.l   @(4,r5),r0
        cmp/eq  r3,r0
        bt      .blit
.miss:
        /* pre-pass: total longs over rows -> r4 */
        mov     r8,r1
        mov.w   @r1+,r7
        tst     r7,r7
        bt      .orig2
        mov     #MAXR,r0
        cmp/hi  r0,r7
        bt      .orig2
        mov     r9,r2
        add     #3,r2
        mov     #-4,r0
        and     r0,r2                   /* E */
        mov     #0,r4
.pr:    mov     #0,r6
.ps:    mov.w   @r1+,r0
        extu.w  r0,r0
        tst     r0,r0
        bt      .pe
        extu.b  r0,r0
        bra     .ps
        add     r0,r6
.pe:    mov     r9,r0
        sub     r6,r0
        mov     #-4,r6
        and     r6,r0                   /* A */
        mov     r2,r6
        sub     r0,r6
        shlr2   r6
        dt      r7
        bf/s    .pr
        add     r6,r4
        mov.w   L_cap1,r0
        cmp/hi  r0,r4
        bt      .big
        mov.l   L_s1,r5
        bra     .dec
        mov.w   L_cap1,r4
.big:   mov.w   L_cap0,r0
        cmp/hi  r0,r4
        bt      .memo
        mov.l   L_s0,r5
        bra     .dec
        mov.w   L_cap0,r4
.memo:  mov.l   L_fail,r1
        mov.l   r8,@r1
.orig2: mov.l   L_orig9,r0
        jmp     @r0
        nop

.dec:   /* r5 slot header, r4 capacity (longs) */
        mov.l   r10,@-r15
        mov.l   r11,@-r15
        mov.l   r12,@-r15
        mov.l   r4,@-r15                /* cap */
        mov     #0,r0
        mov.l   r0,@r5                  /* invalidate while decoding */
        mov     r8,r10                  /* keep src for the key */
        mov.w   @r8+,r7                 /* rows */
        tst     r7,r7
        bt      .fail
        mov     #MAXR,r0
        cmp/hi  r0,r7
        bt      .fail
        mov.l   r7,@(8,r5)
        mov     r9,r11
        add     #3,r11
        mov     #-4,r0
        and     r0,r11                  /* E */
        mov     r5,r12
        add     #16,r12                 /* row header */
        mov     r5,r2
        add     #0x7F,r2
        add     #1,r2                   /* data = header + 0x80 */
        mov     #0,r3                   /* total longs */
.row:   mov     r8,r1
        mov     #0,r6
.scan:  mov.w   @r1+,r0
        extu.w  r0,r0
        tst     r0,r0
        bt      .scanned
        extu.b  r0,r0
        bra     .scan
        add     r0,r6
.scanned:
        mov     r9,r4
        sub     r6,r4
        mov     #-4,r0
        and     r0,r4                   /* A */
        mov     r11,r6
        sub     r4,r6
        shlr2   r6                      /* L */
        add     r6,r3
        mov.l   @r15,r0
        cmp/hi  r0,r3
        bt      .fail
        mov     r6,r0
        mov.b   r0,@r12
        add     #1,r12
        mov     r2,r1
        tst     r6,r6
        bt      .zd
        mov     #0,r0
.z:     mov.l   r0,@r1
        dt      r6
        bf/s    .z
        add     #4,r1
.zd:    mov     r9,r0
        sub     r4,r0
        add     r2,r0
        mov     r1,r4                   /* next strip */
        mov     r0,r1                   /* cursor */
.tok:   mov.w   @r8+,r0
        extu.w  r0,r0
        tst     r0,r0
        bt      .rowend
        mov     r0,r6
        extu.b  r6,r6
        shlr8   r0
        tst     r0,r0
        bf      .paint
        bra     .tok
        sub     r6,r1
.paint: dt      r6
        bf/s    .paint
        mov.b   r0,@-r1
        bra     .tok
        nop
.rowend:
        mov     r4,r2
        dt      r7
        bf      .row
        mov     r9,r0
        and     #3,r0
        mov.l   r0,@(4,r5)
        mov.l   r10,@r5
        add     #4,r15
        mov.l   @r15+,r12
        mov.l   @r15+,r11
        mov.l   @r15+,r10
.blit:  /* r5 slot header */
        mov.l   @(8,r5),r7              /* rows */
        mov     r5,r4
        add     #16,r4
        mov     r5,r8
        add     #0x7F,r8
        add     #1,r8
        mov     r9,r3
        add     #3,r3
        mov     #-4,r0
        and     r0,r3                   /* E of row 0 */
.brow:  mov.b   @r4+,r0
        extu.b  r0,r2
        tst     r2,r2
        bt      .bnext
        mov     r2,r1
        shll2   r1
        neg     r1,r1
        add     r3,r1                   /* A */
.bl:    mov.l   @r8+,r0
        dt      r2
        mov.l   r0,@r1
        bf/s    .bl
        add     #4,r1
.bnext: dt      r7
        bf/s    .brow
        add     r13,r3
        rts
        nop
.fail:
        add     #4,r15
        mov.l   @r15+,r12
        mov.l   @r15+,r11
        mov.l   @r15+,r10
        mov.l   L_fail,r1
        mov.l   @(8,r14),r0
        mov.l   r0,@r1
.orig:
        mov.l   L_orig9,r0
        jmp     @r0
        nop
        .align  1
L_cap0: .word   1248            /* 0x26016C80..0x26017FFF */
L_cap1: .word   224             /* 0x2601F380..0x2601FFFF */
        .align  2
L_s0:    .long  S0
L_s1:    .long  S1
L_fail:  .long  0x26016C0C      /* S0 header +0C: unused word */
L_tog:   .long  0x2600F80C      /* S1 header +0C */
L_orig9: .long  0x06003FC6
