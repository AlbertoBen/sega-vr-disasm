/*
 * vr60_interp_camera_render -- midpoint pass through the stock cmd $02 path
 * Expansion ROM address: $301500 (SH2 $02301500), experimental build only.
 *
 * The stock per-frame command $02 receives a $500-word scene block, clears
 * its half of the draw framebuffer, then runs a paired Master/Slave render.
 * The midpoint pass needs
 * the paired render -- calling Slave command $02 directly is not equivalent
 * and eventually corrupts the on-chip renderer.  It does not need to feed
 * audio a second time.  The renderer mutates working records inside the input
 * block, so retransmitting only the changed camera prefix is unsafe.  This
 * handler therefore follows the stock command $02 call graph exactly after a
 * complete scene-block transfer:
 *
 *   1. Receive the stock $A00-byte scene block into $0600C000.
 *   2. Submit the same 320x100-pixel clear to the Slave through command $08.
 *   3. Finish DMAC and run the stock transform dispatcher while it clears,
 *      then join the Slave before any later framebuffer command is submitted.
 *   4. Run the stock VDP setup and submit Slave command $04.
 *   5. Execute every stock Master-side transform/render stage while the Slave
 *      works, then join it at the original barrier.
 *   6. Publish completion through the original extended completion routine.
 *
 * The 68K remains authoritative for physics, AI, collision, timers, input,
 * audio, and descriptor construction.  No polygon or object-count field is
 * modified here.
 *
 * Entry: R8 = $20004020 (Master dispatch-loop COMM base)
 * Uses:  stock command $02 clobber set
 */

.section .text
.align 2

vr60_interp_camera_render:
    sts.l   pr,@-r15

    /* The command byte has been sampled by the dispatch loop.  Clear only
     * COMM0_LO now; COMM0_HI remains owned by this handler until completion. */
    mov     #0,r0
    mov.b   r0,@(1,r8)
    mov.b   @(1,r8),r0              /* same-address write-buffer sync */

    /* Reuse the game's proven FIFO-DMAC setup.  It reads DREQ_LEN, arms
     * CHCR0=$44E1/DMAOR=1, and publishes the bit-1 FIFO ACK. */
    mov.l   @(.camera_dst,pc),r1
    mov.l   @(.dmac_fifo_setup,pc),r0
    jsr     @r0
    nop

    /* The dual-SH2 overlap helper delegates the exact stock 100-row fill to
     * Slave command $08 while the Master waits for DMAC0.TE, performs the
     * stock finish/cache lifecycle once, and runs the stock transform. */
    mov.w   @(.clear_start,pc),r1
    mov.w   @(.clear_length,pc),r2
    mov.l   @(.clear_overlap,pc),r0
    jsr     @r0
    mov     #100,r3

    /* The helper returns the exact transform register result with paired
     * Slave command $04 already live.  Continue at stock render stage A. */

    mov.l   @(.render_stage_a,pc),r0
    jsr     @r0
    nop

    /* Keep Slave cmd $04 live while the Master restores its private on-chip
     * renderer and prepares the next context.  The subsequent stock
     * slave_submit call waits for cmd $04 before publishing cmd $02, so the
     * command order is unchanged and neither preamble writes the framebuffer.
     * The stock stage joins Slave cmd $02 at its very end.  Its Master work is
     * independent of render_stage_c, so the private clone below returns just
     * before that join and lets both SH-2s overlap for longer. */
    bsr     vr60_render_stage_b_deferred
    nop

    mov.l   @(.render_stage_c,pc),r0
    jsr     @r0
    nop

    /* Join at the last proven-safe point, before cache/finalization work.
     * Stock slave_wait clobbers R0/R1 and T; preserve the state produced by
     * render_stage_c so downstream code sees the original ABI. */
    mov.l   r0,@-r15
    mov.l   r1,@-r15
    stc     sr,r0
    mov.l   r0,@-r15
    mov.l   @(.slave_wait,pc),r0
    jsr     @r0
    nop
    mov.l   @r15+,r0
    ldc     r0,sr
    mov.l   @r15+,r1
    mov.l   @r15+,r0

    mov.l   @(.cache_purge,pc),r0
    jsr     @r0
    nop

    mov.l   @(.render_stage_d,pc),r0
    jsr     @r0
    nop

    mov.l   @(.visibility_table,pc),r14
    mov.l   @(.entity_dispatch,pc),r0
    jsr     @r0
    mov     #32,r7

    /* Tail-call the same completion routine as stock cmd $02. */
    mov.l   @(.completion,pc),r0
    jmp     @r0
    lds.l   @r15+,pr

.align 2
.clear_start:       .word 0x3000
.clear_length:      .word 0x009F
.camera_dst:        .long 0x2600C000
.dmac_fifo_setup:   .long 0x06004448
.clear_overlap:     .long 0x02304C20
.slave_submit:      .long 0x0600441C
.render_stage_a:    .long 0x0600115C
.slave_wait:        .long 0x06004438
.render_stage_c:    .long 0x060010AC
.cache_purge:       .long 0x060045CC
.render_stage_d:    .long 0x060011B4
.visibility_table:  .long 0x0600C800
.entity_dispatch:   .long 0x06003CB4
.completion:        .long 0x060043F0

/*
 * Private, geometry-identical clone of stock $06000EB4.  The only omitted
 * operation is its final call to $06004438; the caller performs that join
 * after $060010AC.  Descriptor counts, object lists, matrices and draw calls
 * are byte-for-byte the stock sequence.
 */
.align 2
vr60_render_stage_b_deferred:
    sts.l   pr,@-r15

    mov.l   @(.b_252c,pc),r0
    jsr     @r0
    nop
    mov.l   @(.b_22bc,pc),r0
    jsr     @r0
    nop
.ifdef VR60_EXPERIMENTAL_FAMILY_A_SHADOW_STAGE1
    /* Stage-1 diagnostic producer snapshots the exact family-A inputs before
     * cmd $02.  Rendering still always follows the stock Slave path. */
    mov.l   @(.b_family_a_shadow_stage1_producer,pc),r0
    jsr     @r0
    nop
.else
.ifdef VR60_EXPERIMENTAL_FAMILY_A_SHADOW_QUEUE
    /* Diagnostic-only producer: publish an exact family-A input snapshot
     * before Slave cmd $02 can consume it.  The Slave still executes the
     * complete stock renderer and remains the sole framebuffer writer. */
    mov.l   @(.b_family_a_shadow_producer,pc),r0
    jsr     @r0
    nop
.endif
.endif
.ifdef VR60_EXPERIMENTAL_FAMILY_A_PRETRANSFORM
    /* Reserve the phase-local lease before cmd $02 starts.  The immutable
     * family-A snapshot is taken after submission joins the prior command. */
    mov.l   @(.b_family_a_pretransform_arm,pc),r0
    jsr     @r0
    nop
.else
.ifdef VR60_EXPERIMENTAL_FAMILY_A_HANDOFF
    /* Arm the phase-local request before cmd $02 can reach family A. */
    mov.l   @(.b_family_a_handoff_arm,pc),r0
    jsr     @r0
    nop
.endif
.endif
    mov.l   @(.b_441c,pc),r0
    jsr     @r0
    mov     #2,r1
.ifdef VR60_EXPERIMENTAL_FAMILY_A_PRETRANSFORM
    /* Snapshot and produce the split candidates immediately so the work
     * overlaps the Slave's stock descriptors 0/1 and later builders. */
    mov.l   @(.b_family_a_pretransform_master,pc),r0
    jsr     @r0
    nop
.else
.ifdef VR60_EXPERIMENTAL_FAMILY_A_HANDOFF
    /* Service the request at the Slave's canonical family-A position.  The
     * worker restores this CPU's private renderer context before returning. */
    mov.l   @(.b_family_a_handoff_master,pc),r0
    jsr     @r0
    nop
.endif
.endif
    mov.l   @(.b_2384,pc),r0
    jsr     @r0
    nop

    mov.l   @(.b_c0cc,pc),r0
    mov.w   @r0,r0
    mov.l   @(.b_2394,pc),r1
    jsr     @r1
    shll8   r0

    mov.l   @(.b_ca00,pc),r13
    mov.l   @(.b_c100,pc),r14
    mov.l   @(.b_244c,pc),r0
    jsr     @r0
    nop

    mov.l   @(.b_local_0700,pc),r14
    mov.l   @(.b_local_01b0,pc),r0
    mov.l   r0,@(28,r14)
    mov.l   @(.b_1000,pc),r0
    mov.l   @(.b_2394,pc),r1
    jsr     @r1
    nop

    mov.l   @(.b_ca30,pc),r13
    mov.l   @(.b_c114,pc),r14
    mov.l   @(.b_24dc,pc),r0
    jsr     @r0
    mov     #1,r7

.ifdef VR60_EXPERIMENTAL_FAMILY_A_SPLIT
    /* Exact family-A split A/B: Slave cmd $02 keeps descriptor 0 while this
     * Master renders descriptors 1..3.  Descriptor order and the stock
     * $060024DC callback are unchanged inside each disjoint range. */
    mov.l   @(.b_ca90,pc),r13
    mov.l   @(.b_c13c,pc),r14
    mov.l   @(.b_24dc,pc),r0
    jsr     @r0
    mov     #3,r7
.endif

    mov.l   @(.b_local_0700,pc),r14
    mov.l   @(.b_8000,pc),r0
    mov.l   @(.b_2394,pc),r1
    jsr     @r1
    nop

    mov.l   @(.b_cca0,pc),r13
    mov.l   @(.b_c218,pc),r14
    mov     #8,r7
.b_loop8:
    mov.l   r7,@-r15
    mov.l   @(.b_24dc,pc),r0
    jsr     @r0
    mov     #3,r7
    mov.l   @r15+,r7
    add     #0x60,r13
    add     #0x30,r13
    dt      r7
    bf/s    .b_loop8
    add     #0x3c,r14

    mov.l   @(.b_c0cc,pc),r0
    mov.w   @r0,r0
    mov.l   @(.b_2394,pc),r1
    jsr     @r1
    shll8   r0

    mov.l   @(.b_d510,pc),r13
    mov.l   @(.b_c59c,pc),r14
    mov.l   @(.b_24dc,pc),r0
    jsr     @r0
    mov     #16,r7

    mov.l   @(.b_d870,pc),r13
    mov.l   @(.b_c704,pc),r14
    mov.l   @(.b_23b4,pc),r0
    jsr     @r0
    mov     #2,r7

.ifdef VR60_EXPERIMENTAL_FAMILY_A_SHADOW_STAGE1
    /* Use the end of the Master's independent stage-B work, immediately
     * before it would otherwise reach the final Slave join.  By this point
     * the Slave has had the whole stock Master render slice in which to
     * publish family-A jobs; the duplicated transforms therefore replace
     * prospective wait time instead of stalling both CPUs just after submit. */
    mov.l   @(.b_family_a_shadow_stage1_worker,pc),r0
    jsr     @r0
    nop
.endif

.ifdef VR60_EXPERIMENTAL_FAMILY_A_PRETRANSFORM
    /* Do not let stock stage C reclaim $06016000 until the Slave has consumed
     * or bypassed the two produced candidate slots. */
    mov.l   @(.b_family_a_pretransform_release,pc),r0
    jsr     @r0
    nop
.endif

    lds.l   @r15+,pr
    rts
    nop

.align 2
.b_252c:       .long 0x02304800
.b_22bc:       .long 0x060022BC
.ifdef VR60_EXPERIMENTAL_FAMILY_A_PRETRANSFORM
.b_family_a_pretransform_arm:   .long 0x02306300
.b_family_a_pretransform_master:.long 0x02306500
.b_family_a_pretransform_release:.long 0x02306900
.else
.ifdef VR60_EXPERIMENTAL_FAMILY_A_HANDOFF
.b_family_a_handoff_arm:   .long 0x02306200
.b_family_a_handoff_master:.long 0x02306300
.endif
.endif
.ifdef VR60_EXPERIMENTAL_FAMILY_A_SHADOW_STAGE1
.b_family_a_shadow_stage1_producer: .long 0x02304D00
.b_family_a_shadow_stage1_worker:   .long 0x02305600
.else
.ifdef VR60_EXPERIMENTAL_FAMILY_A_SHADOW_QUEUE
.b_family_a_shadow_producer: .long 0x02304D00
.endif
.endif
.b_441c:       .long 0x0600441C
.b_2384:       .long 0x06002384
.b_c0cc:       .long 0x0600C0CC
.b_2394:       .long 0x06002394
.b_ca00:       .long 0x0600CA00
.b_c100:       .long 0x0600C100
.b_244c:       .long 0x0600244C
.b_local_0700: .long 0xC0000700
.b_local_01b0: .long 0xC00001B0
.b_1000:       .long 0x00001000
.b_ca30:       .long 0x0600CA30
.b_c114:       .long 0x0600C114
.ifdef VR60_EXPERIMENTAL_FAMILY_A_SPLIT
.b_ca90:       .long 0x0600CA90
.b_c13c:       .long 0x0600C13C
.endif
.b_24dc:       .long 0x060024DC
.b_8000:       .long 0x00008000
.b_cca0:       .long 0x0600CCA0
.b_c218:       .long 0x0600C218
.b_d510:       .long 0x0600D510
.b_c59c:       .long 0x0600C59C
.b_d870:       .long 0x0600D870
.b_c704:       .long 0x0600C704
.b_23b4:       .long 0x060023B4

.global vr60_interp_camera_render
