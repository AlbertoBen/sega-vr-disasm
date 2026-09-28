/*
 * vr60_fill_pump -- overlap the Master SH-2 transform pipeline with the
 * stock 32X framebuffer auto-fill.
 *
 * Expansion ROM: file $304900, SH-2 $02304900.  Experimental interpolation
 * build only.  The two fixed entry points are deliberately four bytes apart:
 *
 *   $02304900  vr60_fill_pump_always  (stock cmd $02 and interpolated pass)
 *   $02304904  vr60_fill_pump_cmd5    (stock cmd $05 visibility gate)
 *
 * Entry is the stock $060044F6 ABI:
 *   R1 = first FILLADR ($3000), R2 = FILLEN ($009F), R3 = rows (100)
 *
 * The helper owns eight bytes of live state plus a 20-byte ABI spill area
 * below its saved PR while it runs:
 *   @(0,R15) next FILLADR plus private flags in bits 31..29
 *   @(4,R15) rows remaining
 *   @(8..24,R15) deferred R0-R3/SR chain spill used only across final drain
 *
 * Geometry, object counts, transforms and LOD are unchanged.  This is the
 * exact $06000DC8 call sequence (1 + 2 + 15 + 16 + 4 + 3 = 41 units), with a
 * fill step before each unit.  Remaining rows are drained before returning,
 * and the last transform stays after the drain so its register/T result is
 * the same final result exposed by the stock pipeline.
 *
 * fill_step internally uses R0-R3/T but preserves them on return, along with
 * the loop counter R7, all pipeline bases R12-R14, MAC state, PR and R15.
 */

.section .text
.align 2

.global vr60_fill_pump_always
.global vr60_fill_pump_cmd5

vr60_fill_pump_always:
    bra     .entry
    mov     #0,r0

/* Fixed second entry at helper +$04. */
vr60_fill_pump_cmd5:
    bra     .entry
    mov     #1,r0

.entry:
    sts.l   pr,@-r15
    add     #-20,r15              /* fixed ABI-chain spill area */
    mov.l   r3,@-r15               /* rows remaining */

    tst     r0,r0
    bt      .store_next
    mov.l   @(.flag_cmd5,pc),r0
    or      r0,r1
.store_next:
    mov.l   r1,@-r15               /* next address + private flags */

    /* Stock writes FILLEN once before the first row. */
    mov.l   @(.vdp_base,pc),r1
    mov.w   @(.fill_length,pc),r0
    mov.w   r0,@(4,r1)

    /* Unit 1.  This first step also waits for DMAC0.TE and calls the exact
     * stock $06004480 finish/cache lifecycle once, before scene consumers. */
    bsr     .fill_step
    nop

    /* Cmd $05 alone duplicates its exact C0C8/C0CA visibility gate here.
     * The stock gate remains in the handler and therefore still owns control
     * flow.  If it will skip, only clear/DMAC work is required in this pump. */
    mov.l   @r15,r1
    mov.l   @(.flag_cmd5,pc),r0
    tst     r0,r1
    bt      .pipeline

    mov.l   @(.visibility_range,pc),r1
    mov.w   @r1+,r0
    cmp/eq  #-1,r0
    bt      .mark_skip
    mov.w   @r1+,r1
    cmp/eq  r0,r1
    bf      .pipeline

.mark_skip:
    mov.l   @r15,r1
    mov.l   @(.flag_skip,pc),r0
    or      r0,r1
    mov.l   r1,@r15
    bra     .drain
    nop

.pipeline:
    /* Exact stock unit 1: context setup at $06001A6C. */
    mov.l   @(.ctx_c100,pc),r14
    mov.l   @(.fn_1a6c,pc),r0
    jsr     @r0
    nop

    /* Unit 2. */
    bsr     .fill_step
    nop
    mov.l   @(.obj_ca00,pc),r13
    mov.l   @(.local_0038,pc),r12
    mov.l   @(.local_0400,pc),r4
    mov.l   @(.fn_1bd4,pc),r0
    jsr     @r0
    nop

    /* Unit 3. */
    bsr     .fill_step
    nop
    mov.l   @(.obj_ca30,pc),r13
    mov.l   @(.ctx_c114,pc),r14
    mov.l   @(.fn_1c08,pc),r0
    jsr     @r0
    nop

    /* Units 4..18: stock 15-entry batch.  Pump before the stock R7 save. */
    mov.l   @(.obj_cca0,pc),r13
    mov.l   @(.ctx_c218,pc),r14
    mov     #15,r7
.loop15:
    bsr     .fill_step
    nop
    mov.l   @(.fn_1d34,pc),r0
    jsr     @r0
    mov.l   r7,@-r15
    mov.l   @r15+,r7
    dt      r7
    bf      .loop15

    /* Units 19..34: stock 16-entry batch. */
    mov.l   @(.obj_d510,pc),r13
    mov.l   @(.ctx_c59c,pc),r14
    mov     #16,r7
.loop16:
    bsr     .fill_step
    nop
    mov.l   @(.fn_1e9c,pc),r0
    jsr     @r0
    mov.l   r7,@-r15
    mov.l   @r15+,r7
    dt      r7
    bf      .loop16

    /* Units 35..38: stock 4-entry batch. */
    mov.l   @(.obj_d810,pc),r13
    mov.l   @(.ctx_c6dc,pc),r14
    mov     #4,r7
.loop4:
    bsr     .fill_step
    nop
    mov.l   @(.fn_1da4,pc),r0
    jsr     @r0
    mov.l   r7,@-r15
    mov.l   @r15+,r7
    dt      r7
    bf      .loop4

    /* Unit 39. */
    bsr     .fill_step
    nop
    mov.l   @(.local_0400,pc),r4
    mov.l   @(.obj_d930,pc),r13
    mov.l   @(.ctx_c754,pc),r14
    mov.l   @(.fn_1e7e,pc),r0
    jsr     @r0
    nop

    /* Unit 40. */
    bsr     .fill_step
    nop
    mov.l   @(.local_0400,pc),r4
    mov.l   @(.obj_d900,pc),r13
    mov.l   @(.ctx_c740,pc),r14
    mov.l   @(.fn_1dcc,pc),r0
    jsr     @r0
    nop

    /* Start row 41 before the final stock unit.  Drain first so no helper
     * bookkeeping can alter the final unit's exposed register/T result. */
    bsr     .fill_step
    nop

    /* Preserve the output chain from fn_1dcc across the drain.  fn_1df8 is
     * then entered with the same R1-R3/T inputs as in the stock sequence. */
    mov.l   r0,@(8,r15)
    mov.l   r1,@(12,r15)
    mov.l   r2,@(16,r15)
    mov.l   r3,@(20,r15)
    stc     sr,r0
    mov.l   r0,@(24,r15)

.drain:
    mov.l   @(4,r15),r0
    tst     r0,r0
    bt      .wait_last_fill
    bsr     .fill_step
    nop
    bra     .drain
    nop

.wait_last_fill:
    mov.l   @(.vdp_base,pc),r1
.wait_fen0:
    mov.w   @(10,r1),r0
    tst     #2,r0
    bf      .wait_fen0

    /* A visibility skip returns to the stock cmd-$05 gate. */
    mov.l   @r15,r1
    mov.l   @(.flag_skip,pc),r0
    tst     r0,r1
    bf      .return

    mov.l   @(24,r15),r0
    ldc     r0,sr
    mov.l   @(20,r15),r3
    mov.l   @(16,r15),r2
    mov.l   @(12,r15),r1
    mov.l   @(8,r15),r0

    /* Unit 41: exact last stock call, intentionally after the drain. */
    mov.l   @(.local_0400,pc),r4
    mov.l   @(.obj_d8d0,pc),r13
    mov.l   @(.ctx_c72c,pc),r14
    mov.l   @(.fn_1df8,pc),r0
    jsr     @r0
    nop

.return:
    add     #28,r15
    lds.l   @r15+,pr
    rts
    nop

/*
 * Start one row after the preceding row becomes idle.  The stock 125-iteration
 * delay remains, but the later FEN wait moves to the start of the next step so
 * the intervening transform consumes otherwise-idle Master cycles.
 */
.fill_step:
    /* Preserve the complete inter-unit value chain.  R3 then points at the
     * pump's fixed eight-byte state while the five saved longs are present. */
    mov.l   r0,@-r15
    mov.l   r1,@-r15
    mov.l   r2,@-r15
    mov.l   r3,@-r15
    stc     sr,r0
    mov.l   r0,@-r15
    mov     r15,r3
    add     #20,r3

    /* Once DMAC finish is recorded, a zero-row call is a true no-op. */
    mov.l   @r3,r1
    cmp/pz  r1
    bt      .fill_next_before_te
    mov.l   @(4,r3),r0
    tst     r0,r0
    bt      .fill_return
    bra     .fill_start
    nop

.fill_next_before_te:
    mov.l   @(4,r3),r0
    tst     r0,r0
    bt      .wait_dmac_te_only

.fill_start:
    mov.l   @(.vdp_base,pc),r2
.fill_wait_fen0:
    mov.w   @(10,r2),r0
    tst     #2,r0
    bf      .fill_wait_fen0

    mov.l   @r3,r1
    mov     r1,r0
    mov.w   r0,@(6,r2)
    mov.w   @(.fill_stride,pc),r0
    add     r0,r1
    mov.l   r1,@r3
    mov     #0,r0
    mov.w   r0,@(8,r2)

    mov     #125,r0
.fill_delay:
    dt      r0
    bf      .fill_delay

    mov.l   @(4,r3),r0
    add     #-1,r0
    mov.l   r0,@(4,r3)

    /* Bit 31 in next-address state records the one completed DMAC finish. */
    mov.l   @r3,r1
    cmp/pz  r1
    bf      .fill_return

    mov.l   @(.dmac_chcr0,pc),r2
    mov.l   @r2,r0
    tst     #2,r0
    bf      .finish_dmac

    /* Preserve the stock overlap: while the FIFO DMAC is still active, keep
     * issuing complete auto-fill rows instead of blocking on TE. */
    mov.l   @(4,r3),r0
    tst     r0,r0
    bf      .fill_next_before_te

.wait_dmac_te_only:
    mov.l   @(.dmac_chcr0,pc),r2
.wait_dmac_te:
    mov.l   @r2,r0
    tst     #2,r0
    bt      .wait_dmac_te

.finish_dmac:
    mov.l   @r3,r1
    mov.l   @(.flag_dmac_done,pc),r0
    or      r0,r1
    mov.l   r1,@r3

    /* $06004480/$060045CC clobber R14; fill_step's contract does not. */
    sts.l   pr,@-r15
    mov.l   r14,@-r15
    mov.l   @(.dmac_finish,pc),r0
    jsr     @r0
    nop
    mov.l   @r15+,r14
    lds.l   @r15+,pr

.fill_return:
    mov.l   @r15+,r0
    ldc     r0,sr
    mov.l   @r15+,r3
    mov.l   @r15+,r2
    mov.l   @r15+,r1
    mov.l   @r15+,r0
    rts
    nop

.align 2
.fill_length:       .word 0x009f
.fill_stride:       .word 0x0100

.vdp_base:          .long 0x20004100
.dmac_chcr0:        .long 0xffffff8c
.dmac_finish:       .long 0x06004480
.visibility_range:  .long 0x0600c0c8
.flag_dmac_done:    .long 0x80000000
.flag_cmd5:         .long 0x40000000
.flag_skip:         .long 0x20000000

/* Exact $06000DC8 literal set. */
.ctx_c100:          .long 0x0600c100
.fn_1a6c:           .long 0x06001a6c
.obj_ca00:          .long 0x0600ca00
.local_0038:        .long 0xc0000038
.local_0400:        .long 0xc0000400
.fn_1bd4:           .long 0x06001bd4
.obj_ca30:          .long 0x0600ca30
.ctx_c114:          .long 0x0600c114
.fn_1c08:           .long 0x06001c08
.obj_cca0:          .long 0x0600cca0
.ctx_c218:          .long 0x0600c218
.fn_1d34:           .long 0x06001d34
.obj_d510:          .long 0x0600d510
.ctx_c59c:          .long 0x0600c59c
.fn_1e9c:           .long 0x06001e9c
.obj_d810:          .long 0x0600d810
.ctx_c6dc:          .long 0x0600c6dc
.fn_1da4:           .long 0x06001da4
.obj_d930:          .long 0x0600d930
.ctx_c754:          .long 0x0600c754
.fn_1e7e:           .long 0x06001e7e
.obj_d900:          .long 0x0600d900
.ctx_c740:          .long 0x0600c740
.fn_1dcc:           .long 0x06001dcc
.obj_d8d0:          .long 0x0600d8d0
.ctx_c72c:          .long 0x0600c72c
.fn_1df8:           .long 0x06001df8
