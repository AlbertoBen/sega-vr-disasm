/*
 * Geometry-exact source/reference for the stock on-chip vertex transform at
 * C0000128 (ROM source 022674).  The runtime build places this leaf's hot
 * loop in C0000128-C00001AF and its setup/literals in the audited
 * C00006D4-C00006F7 gap.  Callback/template bytes at C00001B0+ therefore
 * remain completely stock: later renderer stages also use R12 as a base
 * pointer into that block.
 *
 * The four callback addresses used by the engine encode the scale class in
 * bit 1 of their low byte:
 *
 *   C00001B0 / 060026FC -> bit 1 clear -> scale 64
 *   C00001CE / 0600271A -> bit 1 set   -> scale 2048
 *
 * R12 is restored from context+28 before returning.  Geometry, fixed-point
 * arithmetic, clipping inputs, cursor movement and the observable register
 * ABI therefore match the stock routine.
 */

.section .text
.align 2

vr60_vertex_fast:
    mov.l   @(44,r14),r10
    mov.l   @(28,r14),r12

    mov     r12,r0
    mov     #64,r12
    tst     #2,r0
    bt      .scale_ready
    mov.w   @(.scale_2048,pc),r12
.scale_ready:

    mov.l   @(12,r14),r9
    mov.l   @(8,r14),r7
    mov.l   @(.vector_seed,pc),r5
    mov.w   @(.screen_base,pc),r6
    mov.l   @(.matrix_base,pc),r4

.vertex_loop:
    mov.w   @r13+,r0
    mov.w   @r13+,r1
    mov.w   @r13+,r2
    muls.w  r12,r2
    sts.l   macl,@-r5
    muls.w  r12,r1
    sts.l   macl,@-r5
    muls.w  r12,r0
    sts.l   macl,@-r5

    clrmac
    mac.l   @r4+,@r5+
    mac.l   @r4+,@r5+
    mac.l   @r4+,@r5+
    add     #-12,r5
    mov.l   @r4+,r2
    sts     mach,r0
    sts     macl,r3
    xtrct   r0,r3
    add     r2,r3
    mov.l   r3,@(0,r6)
    mov.l   r7,@(16,r6)
    mov     #0,r0
    mov.l   r0,@(20,r6)

    clrmac
    add     #-48,r4
    mac.l   @r4+,@r5+
    mov.l   r3,@(8,r10)
    mac.l   @r4+,@r5+
    mac.l   @r4+,@r5+
    add     #-12,r5
    mov.l   @r4+,r2
    sts     mach,r0
    sts     macl,r1
    clrmac
    xtrct   r0,r1
    add     r2,r1
    mov.l   r1,@(0,r10)

    mac.l   @r4+,@r5+
    mac.l   @r4+,@r5+
    mac.l   @r4+,@r5+
    nop                             /* preserve stock DIVU latency window */
    cmp/gt  r3,r9
    mov.l   @r4+,r8
    sts     mach,r0
    sts     macl,r2
    xtrct   r0,r2
    add     r8,r2
    mov.l   r2,@(4,r10)
    bt      .clip_done

    mov.l   @(28,r6),r3
    dmuls.l r3,r1
    sts     mach,r0
    dmuls.l r3,r2
    mov.w   r0,@(12,r10)
    sts     mach,r0
    mov.w   r0,@(14,r10)
.clip_done:
    dt      r11
    bf/s    .vertex_loop
    add     #16,r10

    mov.l   @(28,r14),r12
    rts
    add     #-12,r5

.align 2
.screen_base: .word 0xff00
.scale_2048:  .word 0x0800
.vector_seed: .long 0xc000077c
.matrix_base: .long 0xc0000760

.global vr60_vertex_fast
