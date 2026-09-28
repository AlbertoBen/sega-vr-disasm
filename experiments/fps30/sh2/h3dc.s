        .text
/* cmd $3D with car interpolation: the 68K streams a packed block of 148
   words: the 60-word camera block, then 5 words (+$12..+$1A) of each of the
   17 object records ($FF61CC + n*$3C), then 3 pad words.  It is DMAed to a
   scratch buffer (2600F000, untouched in boot/menus/two races) and scattered
   into the SDRAM scene copy at 0600C000; everything else in the block is
   unchanged since the last full transfer, except $FF674C (COMM4). */
h3dc:
        sts.l   pr,@-r15
        mov     #0,r0
        mov.b   r0,@(1,r8)
        mov.b   @(1,r8),r0
        mov.l   L_tmp,r1
        mov.l   L_dma,r0
        jsr     @r0
        nop
        mov.l   L_wait,r0
        jsr     @r0
        nop
        mov.l   L_tmp,r1
        mov.l   L_cam,r2
        mov     #30,r3                  /* 60 words = 30 longs */
.cam:   mov.l   @r1+,r0
        dt      r3
        mov.l   r0,@r2
        bf/s    .cam
        add     #4,r2
        mov.l   L_obj,r2
        mov     #17,r3
.rec:   mov.w   @r1+,r0
        mov.w   r0,@r2
        mov.w   @r1+,r0
        mov.w   r0,@(2,r2)
        mov.w   @r1+,r0
        mov.w   r0,@(4,r2)
        mov.w   @r1+,r0
        mov.w   r0,@(6,r2)
        mov.w   @r1+,r0
        mov.w   r0,@(8,r2)
        dt      r3
        bf/s    .rec
        add     #0x3C,r2
        mov.l   L_comm4,r1
        mov.w   @r1,r0
        mov.l   L_c74c,r1
        mov.w   r0,@r1
        mov.l   L_cont,r0
        jmp     @r0
        nop
        .align 2
L_tmp:  .long   0x2600F000
L_cam:  .long   0x2600C100
L_obj:  .long   0x2600C1DE
L_dma:  .long   0x06004448
L_wait: .long   0x06004480
L_cont: .long   0x02301510
L_comm4: .long  0x20004028
L_c74c: .long   0x2600C74C
