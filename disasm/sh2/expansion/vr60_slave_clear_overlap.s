/*
 * vr60_slave_clear_overlap -- experimental dual-SH2 framebuffer clear.
 *
 * This file is wired only by VR60_EXPERIMENTAL_SLAVE_CLEAR_OVERLAP.  It is a
 * self-contained alternative to vr60_fill_pump.s so the two scheduling
 * experiments remain independently selectable for A/B testing.
 *
 * Proposed expansion allocation (all addresses are cacheable ROM aliases):
 *
 *   file $304C00 / SH2 $02304C00  Slave command-$08 clear100 handler
 *   file $304C20 / SH2 $02304C20  Master cmd-$02/interp overlap entry
 *
 * The first A/B exports only command $08 and the always-render Master entry.
 * Command $05 remains entirely stock.
 *
 * Geometry, descriptor counts, LOD inputs and draw order are untouched.  The
 * only reordered operation is the stock 320x100 framebuffer auto-fill.  The
 * Slave performs that exact fill while the Master finishes FIFO DMAC and runs
 * the exact stock transform dispatcher at $06000DC8.
 *
 * Integration contract
 * --------------------
 *  1. Install vr60_slave_clear100_cmd8 in Slave table entry 8:
 *       ROM file $0205E8 / runtime SDRAM $060005E8 = $02304C00.
 *  2. Cmd $02 and the interpolation handler call
 *       vr60_master_clear_overlap_always
 *     with the stock clear ABI (R1=$3000, R2=$009F, R3=100), then omit the
 *     original $06004480, $06004274, command-$04 submit and $06000DC8 calls.
 *  3. The helper waits for command $08 after transforming, performs the stock
 *     VDP setup and submits command $04 itself, then restores the transform's
 *     complete R0-R8/SR result before returning to render stage A.
 *  4. Command $05 remains entirely stock.  No other Slave command or COMM
 *     lane is changed.
 *
 * The Master entry deliberately returns the transform's R0-R8 and complete SR
 * (including T) unchanged across the clear join, VDP setup and command-$04
 * submit.  This reproduces the stock register state at render stage A.
 */

.ifndef VR60_EXPERIMENTAL_SLAVE_CLEAR_OVERLAP
.error "vr60_slave_clear_overlap requires VR60_EXPERIMENTAL_SLAVE_CLEAR_OVERLAP"
.endif

.section .text
.align 2

.global vr60_slave_clear100_cmd8
.global vr60_master_clear_overlap_always

/*
 * Slave jump-table command $08.
 *
 * This is the stock cmd-$04/cmd-$07 wrapper shape with only the exact stock
 * clear parameters changed to the Master cmd-$02/cmd-$05 values.  The stock
 * fill routine waits for FEN=0 after the final row.  Tail-calling $0600442C
 * then clears COMM2_HI ($20004024), which is the normal Slave completion ACK.
 * COMM7 is never read or written.
 */
vr60_slave_clear100_cmd8:
    sts.l   pr,@-r15
    mov.w   @(.clear_start,pc),r1
    mov.w   @(.clear_length,pc),r2
    mov.l   @(.stock_fill,pc),r0
    jsr     @r0
    mov     #100,r3
    mov.l   @(.slave_ack,pc),r0
    jmp     @r0
    lds.l   @r15+,pr

.align 2
.clear_start:   .word 0x3000
.clear_length:  .word 0x009f
.stock_fill:    .long 0x060044f6
.slave_ack:     .long 0x0600442c

/* Keep fixed integration entry $02304C20 when the block starts at $304C00. */
.balign 32
vr60_master_clear_overlap_always:
    sts.l   pr,@-r15

    mov.l   @(.slave_submit,pc),r0
    jsr     @r0
    mov     #8,r1

    mov.l   @(.dmac_finish,pc),r0
    jsr     @r0
    nop

    mov.l   @(.stock_transform,pc),r0
    jsr     @r0
    nop

    /* Preserve the exact transform result while joining clear $08 and doing
     * the two operations that stock performs immediately before transform. */
    mov.l   r0,@-r15
    mov.l   r1,@-r15
    mov.l   r2,@-r15
    mov.l   r3,@-r15
    mov.l   r4,@-r15
    mov.l   r5,@-r15
    mov.l   r6,@-r15
    mov.l   r7,@-r15
    mov.l   r8,@-r15
    stc.l   sr,@-r15

    mov.l   @(.slave_wait,pc),r0
    jsr     @r0
    nop

    mov.l   @(.vdp_setup,pc),r0
    jsr     @r0
    nop

    mov.l   @(.slave_submit,pc),r0
    jsr     @r0
    mov     #4,r1

    ldc.l   @r15+,sr
    mov.l   @r15+,r8
    mov.l   @r15+,r7
    mov.l   @r15+,r6
    mov.l   @r15+,r5
    mov.l   @r15+,r4
    mov.l   @r15+,r3
    mov.l   @r15+,r2
    mov.l   @r15+,r1
    mov.l   @r15+,r0

    lds.l   @r15+,pr
    rts
    nop

.align 2
.slave_submit:      .long 0x0600441c
.dmac_finish:       .long 0x06004480
.stock_transform:   .long 0x06000dc8
.slave_wait:        .long 0x06004438
.vdp_setup:         .long 0x06004274
