        .text
        .align 2
! Ring-status waits without DRC poll-loop classification (add #0 in the
! bt/s delay slot marks the address register as modified by the loop).
trA:    mov.l   K20,r0
        or      r0,r1
1:      mov.w   @(28,r1),r0
        tst     #8,r0
        bt/s    1b
        add     #0,r1
        mov.l   bA,r0
        jmp     @r0
        nop
        .align 2
trB:    mov.l   K20,r3
        or      r6,r3
2:      mov.w   @(28,r3),r0
        tst     #8,r0
        bt/s    2b
        add     #0,r3
        mov.l   bB,r0
        jmp     @r0
        nop
        .align 2
trC:    mov.l   K20,r3
        or      r6,r3
3:      mov.w   @(28,r3),r0
        tst     #8,r0
        bt/s    3b
        add     #0,r3
        mov.l   bC,r0
        jmp     @r0
        nop
        .align 2
trD:    mov.l   K20,r1
        or      r6,r1
4:      mov.w   @(28,r1),r0
        tst     #8,r0
        bt/s    4b
        add     #0,r1
        mov.l   bD,r0
        jmp     @r0
        nop
        .align 2
K20:    .long   0x20000000
bA:     .long   0x060034FA
bB:     .long   0x06003542
bC:     .long   0x06003578
bD:     .long   0x0600386E
