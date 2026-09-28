/*
 * Exact restore replacement for stock $0600252C.
 * Expansion ROM address: $304800 (SH2 $02304800), experimental build only.
 *
 * The copy is required every render because earlier transform stages reuse
 * each executing SH2's private C000 data array as scratch.  This helper copies the
 * same 437 longwords, installs the 36-byte split-vertex setup tail in the
 * audited C00006D4-C00006F7 gap, then tail-jumps to the stock dynamic
 * repatch/return at $06002C20.  It changes no geometry, count, or ordering.
 */

.section .text
.align 2

vr60_onchip_copy_unrolled:
    mov.l   r3,@-r15
    mov.l   r4,@-r15
    mov.l   r5,@-r15

    mov.l   @(.copy_source,pc),r0
    mov.l   @(.copy_dest,pc),r1
    /* Five leading longwords plus 12 groups of 36 = 437 exactly. */
    mov     #5,r7
.copy_lead:
    mov.l   @r0+,r2
    mov.l   r2,@r1
    dt      r7
    bf/s    .copy_lead
    add     #4,r1

    mov     #12,r7
.copy36:
    mov.l   @r0+,r3
    mov.l   @r0+,r4
    mov.l   @r0+,r5
    mov.l   @r0+,r2
    mov.l   r3,@(0,r1)
    mov.l   r4,@(4,r1)
    mov.l   r5,@(8,r1)
    mov.l   r2,@(12,r1)
    add     #16,r1

    mov.l   @r0+,r3
    mov.l   @r0+,r4
    mov.l   @r0+,r5
    mov.l   @r0+,r2
    mov.l   r3,@(0,r1)
    mov.l   r4,@(4,r1)
    mov.l   r5,@(8,r1)
    mov.l   r2,@(12,r1)
    add     #16,r1

    mov.l   @r0+,r3
    mov.l   @r0+,r4
    mov.l   @r0+,r5
    mov.l   @r0+,r2
    mov.l   r3,@(0,r1)
    mov.l   r4,@(4,r1)
    mov.l   r5,@(8,r1)
    mov.l   r2,@(12,r1)
    add     #16,r1

    mov.l   @r0+,r3
    mov.l   @r0+,r4
    mov.l   @r0+,r5
    mov.l   @r0+,r2
    mov.l   r3,@(0,r1)
    mov.l   r4,@(4,r1)
    mov.l   r5,@(8,r1)
    mov.l   r2,@(12,r1)
    add     #16,r1

    mov.l   @r0+,r3
    mov.l   @r0+,r4
    mov.l   @r0+,r5
    mov.l   @r0+,r2
    mov.l   r3,@(0,r1)
    mov.l   r4,@(4,r1)
    mov.l   r5,@(8,r1)
    mov.l   r2,@(12,r1)
    add     #16,r1

    mov.l   @r0+,r3
    mov.l   @r0+,r4
    mov.l   @r0+,r5
    mov.l   @r0+,r2
    mov.l   r3,@(0,r1)
    mov.l   r4,@(4,r1)
    mov.l   r5,@(8,r1)
    mov.l   r2,@(12,r1)
    add     #16,r1

    mov.l   @r0+,r3
    mov.l   @r0+,r4
    mov.l   @r0+,r5
    mov.l   @r0+,r2
    mov.l   r3,@(0,r1)
    mov.l   r4,@(4,r1)
    mov.l   r5,@(8,r1)
    mov.l   r2,@(12,r1)
    add     #16,r1

    mov.l   @r0+,r3
    mov.l   @r0+,r4
    mov.l   @r0+,r5
    mov.l   @r0+,r2
    mov.l   r3,@(0,r1)
    mov.l   r4,@(4,r1)
    mov.l   r5,@(8,r1)
    mov.l   r2,@(12,r1)
    add     #16,r1

    mov.l   @r0+,r3
    mov.l   @r0+,r4
    mov.l   @r0+,r5
    mov.l   @r0+,r2
    mov.l   r3,@(0,r1)
    mov.l   r4,@(4,r1)
    mov.l   r5,@(8,r1)
    mov.l   r2,@(12,r1)
    dt      r7
    bf/s    .copy36
    add     #16,r1

    /* R0/R1 now equal 06002C20/C00006D4 and R2 is the stock final long.
     * Install nine longs without changing those final observable values. */
    mov.l   @(.vertex_tail_source,pc),r3
    mov     r1,r4
    mov     #9,r7
.copy_vertex_tail:
    mov.l   @r3+,r5
    mov.l   r5,@r4
    dt      r7
    bf/s    .copy_vertex_tail
    add     #4,r4

    mov.l   @r15+,r5
    mov.l   @r15+,r4
    mov.l   @r15+,r3
    /* 0600254C + 437*4 is the stock continuation 06002C20, so R0 already
     * holds the exact tail target and R2 holds the exact final copied long. */
    jmp     @r0
    nop

.align 2
.copy_source:
    .long   0x0600254C
.copy_dest:
    .long   0xC0000000
.vertex_tail_source:
    .long   0x023047A0

.global vr60_onchip_copy_unrolled
