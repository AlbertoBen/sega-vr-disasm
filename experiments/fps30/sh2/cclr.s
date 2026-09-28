        .text
/* CPU-store replacement for the VDP-fill line clear 060044F6.
   In: r1 = first word address (FB word index), r2 = words-1 per line (0x9F),
       r3 = lines.  Line stride 0x100 words.  Fills with 0.
   Leaves the registers as the original does: r14 = 20004100, r2 = 0x100,
   r3 = 0, r1 = r1 + lines*0x100. */
cclr:
        mov.l   r4,@-r15
        mov.l   r5,@-r15
        mov.l   r6,@-r15
        mov.l   L_vdp,r14
.wfen:  mov.w   @(10,r14),r0            /* wait for any fill in flight */
        tst     #2,r0
        bf      .wfen
        mov     r2,r6
        add     #1,r6
        shlr2   r6
        shlr2   r6                      /* 16-word (32-byte) groups */
        mov.l   L_fb,r4
        extu.w  r1,r5                   /* r1 comes from mov.w: $9400-$FFFF
                                           are sign-extended; the VDP fill
                                           register only saw the low 16 bits */
        shll    r5
        add     r4,r5                   /* byte address of first line */
        mov.w   L_stride,r4             /* 512 bytes */
        mov     #0,r0
.line:  mov     r5,r4
        mov     r6,r7
.grp:   mov.l   r0,@r4
        mov.l   r0,@(4,r4)
        mov.l   r0,@(8,r4)
        mov.l   r0,@(12,r4)
        mov.l   r0,@(16,r4)
        mov.l   r0,@(20,r4)
        mov.l   r0,@(24,r4)
        mov.l   r0,@(28,r4)
        dt      r7
        bf/s    .grp
        add     #32,r4
        mov.w   L_stride,r4
        add     r4,r5
        mov.w   L_w100,r4
        dt      r3
        bf/s    .line
        add     r4,r1
        mov     r4,r2
        mov.l   @r15+,r6
        mov.l   @r15+,r5
        rts
        mov.l   @r15+,r4
        .align  1
L_stride: .word 512
L_w100:   .word 0x100
        .align  2
L_vdp:  .long   0x20004100
L_fb:   .long   0x24000000
