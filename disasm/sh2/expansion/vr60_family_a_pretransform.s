/*
 * vr60_family_a_pretransform -- concurrent family-A vertex pre-transform
 *
 * Expansion ROM layout (included at file $306000 / SH2 $02306000):
 *   +$000  Slave wrapper / exact-order candidate consumer
 *   +$300  Master arm + immutable input snapshot
 *   +$500  Master candidate producer
 *   +$900  Master release barrier
 *
 * Unlike the serialized authority handoff, this experiment can overlap useful
 * work.  Before cmd $02 the Master only arms the phase-local
 * $26016000-$26017FFF lease.  Immediately after submission (and therefore after
 * the prior Slave command has joined), it snapshots the four family-A records,
 * pre-transforms the tail of descriptor 2 and all of descriptor 3, and publishes
 * each candidate independently.  At the canonical call site the Slave renders
 * descriptors 0/1 through the stock path, completes descriptor 2's disjoint
 * head, and remains the sole owner of builders, buckets and painter order.
 *
 * The Master does not release the lease until the Slave has consumed family A;
 * the release barrier is at the end of independent Master stage B, before
 * stock stage C reuses $06016000.  Shared publication and merge accesses use
 * the cache-through $26 alias; the stock builder temporarily receives the P0
 * alias after cmd $02's cache purge.  This remains an isolated cold-boot
 * experiment, not a real-hardware cache-coherency proof.
 */

.ifndef VR60_EXPERIMENTAL_FAMILY_A_PRETRANSFORM
.error "family-A pretransform requires VR60_EXPERIMENTAL_FAMILY_A_PRETRANSFORM"
.endif

.section .text
.align 2

.equ PRETRANSFORM_MAGIC, 0x50545841  /* "PTXA" */
.equ STATUS_ARMED,       1
.equ STATUS_PREFLIGHT,   2
.equ STATUS_WORKING,     3
.equ STATUS_DONE,        4

/* Phase-local cache-through workspace at $26016000. */
.equ Q_BASE,             0x26016000
.equ H_MAGIC,            0x00
.equ H_STATUS,           0x04
.equ H_ERROR,            0x08
.equ H_ACTIVE_MASK,      0x0C
.equ H_VERTEX_TOTAL,     0x10
.equ H_DIVISOR,          0x14
.equ H_CLIP,             0x18
.equ H_SCALE,            0x1C
.equ H_RELEASE,          0x20
.equ H_USED,             0x24

/* Four $620-byte slots: $20 metadata + 96 x $10 vertex records. */
.equ Q_SLOT0,            (Q_BASE + 0x080)
.equ Q_SLOT_STRIDE,      0x620
.equ S_READY,            0x00
.equ S_COUNT,            0x04
.equ S_SOURCE,           0x08
.equ S_MATRIX,           0x0C
.equ S_DESCRIPTOR,       0x10
.equ S_VALID,            0x14
.equ S_CANDIDATE,        0x20
.equ Q_MAX_VERTICES,     96
.equ Q_SPLIT_HEAD,       1

.if Q_SPLIT_HEAD < 1
.error "Q_SPLIT_HEAD must leave at least one descriptor-2 vertex on the Slave"
.endif
.if Q_SPLIT_HEAD >= Q_MAX_VERTICES
.error "Q_SPLIT_HEAD must be smaller than Q_MAX_VERTICES"
.endif

/* Four $30 state records followed by four $14 descriptor records. */
.equ Q_STATE_SNAPSHOT,   (Q_BASE + 0x1900)
.equ Q_DESC_SNAPSHOT,    (Q_BASE + 0x19C0)

/* Four 96-byte projection-valid maps, one per candidate slot. */
.equ Q_VALID0,            (Q_BASE + 0x1A20)
.equ Q_VALID_STRIDE,      0x60

.global vr60_family_a_pretransform_slave
vr60_family_a_pretransform_slave:
    /* Admit only the exact Slave cmd-$02 family-A invocation. */
    mov.l   r1,@-r15
    sts     pr,r0
    mov.l   @(.s_family_return,pc),r1
    cmp/eq  r1,r0
    bf      .s_tail_stock_short
    mov.l   @(.s_family_state,pc),r1
    cmp/eq  r1,r13
    bf      .s_tail_stock_short
    mov.l   @(.s_family_descriptor,pc),r1
    cmp/eq  r1,r14
    bf      .s_tail_stock_short
    mov     #4,r0
    cmp/eq  r0,r7
    bf      .s_tail_stock_short
    mov.l   @(.s_queue,pc),r1
    mov.l   @(H_MAGIC,r1),r0
    mov.l   @(.s_magic,pc),r2
    cmp/eq  r2,r0
    bf      .s_tail_stock_short
    mov.l   @(H_STATUS,r1),r0
    cmp/eq  #STATUS_ARMED,r0
    bt      .s_gate_ok
    cmp/eq  #STATUS_PREFLIGHT,r0
    bt      .s_gate_ok
    cmp/eq  #STATUS_WORKING,r0
    bt      .s_gate_ok
    cmp/eq  #STATUS_DONE,r0
    bf      .s_tail_stock_short
.s_gate_ok:
    mov.l   @r15+,r1

    /* Preserve exact stock entry state during validation/wait. */
    mov.l   r0,@-r15
    mov.l   r1,@-r15
    mov.l   r2,@-r15
    mov.l   r3,@-r15
    mov.l   r4,@-r15
    mov.l   r5,@-r15
    mov.l   r6,@-r15
    stc     sr,r0
    mov.l   r0,@-r15

    /* The arm precedes the stock submit's join with the prior Slave command.
     * Wait until the post-submit Master has refreshed the immutable snapshot
     * and completed admission before validating it.  Individual candidate
     * slots then stream independently after STATUS_WORKING is published. */
    mov.l   @(.s_queue,pc),r1
.s_wait_preflight:
    mov.l   @(H_STATUS,r1),r0
    cmp/eq  #STATUS_WORKING,r0
    bt      .s_preflight_ready
    cmp/eq  #STATUS_DONE,r0
    bt      .s_preflight_ready
    mov     #32,r2
.s_wait_backoff:
    dt      r2
    bf      .s_wait_backoff
    bra     .s_wait_preflight
    nop
.s_preflight_ready:
    mov.l   @(H_ERROR,r1),r0
    tst     r0,r0
    bf      .s_fallback_saved

    mov.l   @(.s_state_live,pc),r0
    mov.l   @(.s_state_snapshot,pc),r1
    mov     #48,r2
.s_validate_state:
    mov.l   @r0+,r3
    mov.l   @r1+,r4
    cmp/eq  r4,r3
    bf      .s_fail_state
    dt      r2
    bf      .s_validate_state

    mov.l   @(.s_desc_live,pc),r0
    mov.l   @(.s_desc_snapshot,pc),r1
    mov     #20,r2
.s_validate_descriptors:
    mov.l   @r0+,r3
    mov.l   @r1+,r4
    cmp/eq  r4,r3
    bf      .s_fail_descriptors
    dt      r2
    bf      .s_validate_descriptors

    /* The candidate math is valid only for the exact live Slave viewport
     * inputs captured from the Master before submission. */
    mov.l   @(.s_queue,pc),r1
    mov.l   @(.s_context,pc),r2
    mov.l   @(8,r2),r3
    mov.l   @(H_DIVISOR,r1),r4
    cmp/eq  r4,r3
    bf      .s_fail_divisor
    mov.l   @(12,r2),r3
    mov.l   @(H_CLIP,r1),r4
    cmp/eq  r4,r3
    bf      .s_fail_clip
    mov.l   @(28,r2),r0
    tst     #2,r0
    mov     #64,r3
    bt      .s_scale_ready
    mov.w   @(.s_scale_2048,pc),r3
.s_scale_ready:
    mov.l   @(H_SCALE,r1),r4
    cmp/eq  r4,r3
    bf      .s_fail_scale
    mov.l   @(44,r2),r3
    mov.l   @(.s_physical_scratch,pc),r4
    cmp/eq  r4,r3
    bf      .s_fail_scratch

    mov.l   @r15+,r0
    ldc     r0,sr
    mov.l   @r15+,r6
    mov.l   @r15+,r5
    mov.l   @r15+,r4
    mov.l   @r15+,r3
    mov.l   @r15+,r2
    mov.l   @r15+,r1
    mov.l   @r15+,r0
    bra     .s_consume_candidates
    nop

.s_fail_state:
    mov     #2,r0
    bra     .s_record_fallback
    nop
.s_fail_descriptors:
    mov     #3,r0
    bra     .s_record_fallback
    nop
.s_fail_divisor:
.ifdef VR60_PRETRANSFORM_TRAP
    /* Debugger-only stop before the phase lease is released.  R3 is the live
     * Slave divisor and R4 is the value published by the Master. */
    bra     .s_fail_divisor
    nop
.endif
    mov     #5,r0
    bra     .s_record_fallback
    nop
.s_fail_clip:
    mov     #6,r0
    bra     .s_record_fallback
    nop
.s_fail_scale:
    mov     #7,r0
    bra     .s_record_fallback
    nop
.s_fail_scratch:
    mov     #9,r0
.s_record_fallback:
    mov.l   @(.s_queue,pc),r1
    mov.l   r0,@(H_ERROR,r1)

.s_fallback_saved:
    mov.l   @(.s_queue,pc),r1
    mov.l   @(H_ERROR,r1),r0
    tst     r0,r0
    bf      .s_fallback_has_error
    mov     #8,r0
    mov.l   r0,@(H_ERROR,r1)
.s_fallback_has_error:
    mov     #1,r0
    mov.l   r0,@(H_RELEASE,r1)
    mov.l   @(H_RELEASE,r1),r0
    mov.l   @r15+,r0
    ldc     r0,sr
    mov.l   @r15+,r6
    mov.l   @r15+,r5
    mov.l   @r15+,r4
    mov.l   @r15+,r3
    mov.l   @r15+,r2
    mov.l   @r15+,r1
    mov.l   @r15+,r0
    mov.l   @(.s_stock_loop,pc),r0
    jmp     @r0
    nop

.s_tail_stock_short:
    mov.l   @r15+,r1
    /* If this invocation was armed but failed an exact ABI gate, release the
    * Master barrier before executing the untouched stock call. */
    mov.l   r0,@-r15
    mov.l   r1,@-r15
    mov.l   r2,@-r15
    mov.l   @(.s_queue,pc),r1
    mov.l   @(H_MAGIC,r1),r0
    mov.l   @(.s_magic,pc),r2
    cmp/eq  r2,r0
    bf      .s_tail_no_release
    /* The literal at $021080 is shared by later cmd-$02 batches.  Once the
     * exact family-A call has released the lease, those expected rejects must
     * not overwrite its success/error result. */
    mov.l   @(H_RELEASE,r1),r0
    tst     r0,r0
    bf      .s_tail_no_release
    mov     #1,r0
    mov.l   r0,@(H_ERROR,r1)
    mov.l   r0,@(H_RELEASE,r1)
    mov.l   @(H_RELEASE,r1),r0
.s_tail_no_release:
    mov.l   @r15+,r2
    mov.l   @r15+,r1
    mov.l   @r15+,r0
    mov.l   @(.s_stock_loop,pc),r0
    jmp     @r0
    nop

    /* Exact stock $060024DC outer loop.  Only the active-call body changes:
     * state copy and painter-order iteration remain on the Slave, while the
     * builder starts at on-chip +$08 with a pre-transformed scratch pointer. */
.s_consume_candidates:
    sts.l   pr,@-r15
    mov.l   r6,@-r15
    mov.l   @(.s_slot0,pc),r6
.s_entity_loop:
    mov.w   @(0,r14),r0
    cmp/eq  #0,r0
    bt      .s_entity_next

    /* Descriptors 0/1 stay stock and give the producer a lead.  Descriptors
     * 2/3 consume a candidate only if it is already complete: the Slave's
     * critical path never waits behind speculative Master work. */
    mov.l   @(.s_slot2,pc),r0
    cmp/eq  r0,r6
    bt      .s_candidate_if_ready
    mov.l   @(.s_slot3,pc),r0
    cmp/eq  r0,r6
    bf      .s_build_stock
.s_candidate_if_ready:
    mov.l   @(S_READY,r6),r0
    tst     r0,r0
    bt      .s_build_stock

    /* READY describes the exact immutable source count admitted by the Master.
     * Revalidate it at consumption so a changed model cannot make the split
     * head/tail cover a different range.  A mismatch stays entirely stock. */
    mov.l   @(S_SOURCE,r6),r1
    mov.w   @r1,r0
    extu.w  r0,r0
    mov.l   @(S_COUNT,r6),r1
    cmp/eq  r1,r0
    bf      .s_build_stock
.ifdef VR60_PRETRANSFORM_DIAGNOSTIC
    mov.l   @(.s_queue,pc),r1
    mov.l   @(H_USED,r1),r0
    mov     #1,r2
    mov.l   @(.s_slot2,pc),r3
    cmp/eq  r3,r6
    bt      .s_record_used
    mov     #2,r2
.s_record_used:
    or      r2,r0
    mov.l   r0,@(H_USED,r1)
.endif

    mov.l   r14,@-r15
    mov.l   r13,@-r15
    mov.l   r7,@-r15
    bsr     .s_copy_state_exact
    nop

    /* Slot 2 is split head+tail: by reaching READY the Master has completed
     * indices Q_SPLIT_HEAD..N-1, so this CPU fills the disjoint head.  Slot 3 is
     * already complete and skips this call. */
    mov.l   @(.s_slot2,pc),r0
    cmp/eq  r0,r6
    bf      .s_candidate_complete
    mov     r6,r4
    mov.l   @(.s_queue,pc),r5
    bsr     .s_transform_head
    nop
.s_candidate_complete:
    mov.l   @(S_SOURCE,r6),r13
    mov.l   @(.s_context,pc),r14
    mov.l   r6,@-r15
    mov     r6,r4
    bsr     .s_build_candidate
    nop
    mov.l   @r15+,r6

    mov.l   @r15+,r7
    mov.l   @r15+,r13
    mov.l   @r15+,r14
    bra     .s_entity_next
    nop

.s_build_stock:
    mov.l   r14,@-r15
    mov.l   r13,@-r15
    mov.l   r7,@-r15
    mov.l   r6,@-r15
    mov.l   @(.s_stock_loop,pc),r0
    jsr     @r0
    mov     #1,r7
    mov.l   @r15+,r6
    mov.l   @r15+,r7
    mov.l   @r15+,r13
    mov.l   @r15+,r14
.s_entity_next:
    mov.l   @(.s_slot_stride,pc),r0
    add     r0,r6
    add     #48,r13
    dt      r7
    bf/s    .s_entity_loop
    add     #20,r14

    mov.l   @(.s_queue,pc),r1
    mov     #1,r0
    mov.l   r0,@(H_RELEASE,r1)
    mov.l   @(H_RELEASE,r1),r0
    mov.l   @r15+,r6
    lds.l   @r15+,pr
    rts
    nop

/* Exact stock state-copy leaf $06002514. */
.s_copy_state_exact:
    mov.l   @(.s_matrix,pc),r12
    mov     #12,r7
.s_copy_state_loop:
    mov.l   @r13+,r0
    mov.l   r0,@r12
    dt      r7
    bf/s    .s_copy_state_loop
    add     #4,r12
    rts
    nop

/* Point the stock builder directly at the cacheable alias of the Master's
 * builder-native candidate.  Advance the model stream exactly as the skipped
 * transform did.  The on-chip entry at +$08 assumes its caller return was
 * pushed by the skipped prologue, so a tiny BSR trampoline supplies the exact
 * stack/PR shape. */
.s_build_candidate:
    sts.l   pr,@-r15
    mov.l   @(44,r14),r2
    mov.l   r2,@-r15
    mov.w   @r13+,r0
    extu.w  r0,r0
    add     #2,r13
    mov     r0,r3

    /* Match the skipped transform's final model-stream position. */
    mov     r0,r1
    shll    r0
    shll2   r1
    add     r1,r0                    /* six bytes per source vertex */
    add     r0,r13

    /* Reconcile only the projection pair.  A projected candidate updates
     * stock scratch; a clipped one inherits the scratch's current stale
     * value.  This preserves both builder input and the history observed by
     * later stock batches without copying the other three longs. */
    mov     r4,r1
    add     #(S_CANDIDATE + 12),r1
    add     #12,r2
    mov.l   @(S_VALID,r4),r5
.s_merge_projection:
    mov.b   @r5+,r0
    tst     r0,r0
    bt      .s_inherit_projection
    mov.l   @r1,r0
    mov.l   r0,@r2
    bra     .s_projection_next
    nop
.s_inherit_projection:
    mov.l   @r2,r0
    mov.l   r0,@r1
.s_projection_next:
    add     #16,r1
    add     #16,r2
    dt      r3
    bf      .s_merge_projection

    add     #S_CANDIDATE,r4
    mov.l   @(.s_p0_mask,pc),r1
    and     r1,r4
    mov.l   r4,@(44,r14)

    bsr     .s_enter_stock_builder
    nop
.s_after_stock_builder:
    mov.l   @r15+,r2
    mov.l   r2,@(44,r14)
    lds.l   @r15+,pr
    rts
    nop

.s_enter_stock_builder:
    /* R12 is the only skipped-transform live-out consumed before the +$08
     * builder path overwrites the other registers. */
    mov.l   @(28,r14),r12
    sts.l   pr,@-r15                 /* popped by stock on-chip epilogue */
    mov.l   @(.s_stock_builder,pc),r0
    jmp     @r0
    nop

/* Slave half of the 80-vertex slot-2 transform.  The common transform loop
 * lives in the Master block but uses only CPU-local on-chip registers and the
 * explicitly supplied shared job pointers, so it is safe on either SH-2. */
.s_transform_head:
    add     #-12,r15
    mov.l   @(S_SOURCE,r4),r13
    mov.w   @r13+,r11
    add     #2,r13
    mov     #Q_SPLIT_HEAD,r11
    mov     r4,r10
    add     #S_CANDIDATE,r10
    mov.l   @(S_VALID,r4),r12
    bra     .m_vertex_loop
    nop

.align 2
.s_scale_2048:         .word 0x0800
.align 2
.s_family_return:      .long 0x06000FF4
.s_family_state:       .long 0x0600CA60
.s_family_descriptor:  .long 0x0600C128
.s_stock_loop:         .long 0x060024DC
.s_stock_builder:      .long 0xC0000008
.s_context:            .long 0xC0000700
.s_matrix:             .long 0xC0000740
.s_queue:              .long Q_BASE
.s_magic:              .long PRETRANSFORM_MAGIC
.s_slot0:              .long Q_SLOT0
.s_slot_stride:        .long Q_SLOT_STRIDE
.s_slot2:              .long (Q_SLOT0 + (2 * Q_SLOT_STRIDE))
.s_slot3:              .long (Q_SLOT0 + (3 * Q_SLOT_STRIDE))
.s_state_live:         .long 0x2600CA60
.s_desc_live:          .long 0x2600C128
.s_state_snapshot:     .long Q_STATE_SNAPSHOT
.s_desc_snapshot:      .long Q_DESC_SNAPSHOT
.s_p0_mask:            .long 0x0fffffff
.s_physical_scratch:   .long 0x0601C000

/* Fixed entry used before Master submits Slave cmd $02. */
.org 0x300,0xff
.global vr60_family_a_pretransform_arm
vr60_family_a_pretransform_arm:
    sts.l   pr,@-r15
    mov.l   r0,@-r15
    mov.l   r1,@-r15
    mov.l   r2,@-r15
    mov.l   r3,@-r15
    mov.l   r4,@-r15
    mov.l   r5,@-r15
    mov.l   r6,@-r15
    mov.l   r7,@-r15
    stc     sr,r0
    mov.l   r0,@-r15

    mov.l   @(.a_queue,pc),r4
    mov     #0,r0
    mov.l   r0,@(H_STATUS,r4)
    mov.l   r0,@(H_ERROR,r4)
    mov.l   r0,@(H_ACTIVE_MASK,r4)
    mov.l   r0,@(H_VERTEX_TOTAL,r4)
    mov.l   r0,@(H_DIVISOR,r4)
    mov.l   r0,@(H_CLIP,r4)
    mov.l   r0,@(H_SCALE,r4)
    mov.l   r0,@(H_RELEASE,r4)
    mov.l   r0,@(H_USED,r4)

    mov.l   @(.a_slot0,pc),r1
    mov.l   @(.a_slot_stride,pc),r3
    mov     #4,r2
    mov     #0,r0
.a_clear_slots:
    mov.l   r0,@(S_READY,r1)
    mov.l   r0,@(S_COUNT,r1)
    add     r3,r1
    dt      r2
    bf      .a_clear_slots

    mov.l   @(.a_magic,pc),r0
    mov.l   r0,@(H_MAGIC,r4)
    mov     #STATUS_ARMED,r0
    mov.l   r0,@(H_STATUS,r4)
    mov.l   @(H_STATUS,r4),r0

    mov.l   @r15+,r0
    ldc     r0,sr
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
.a_queue:            .long Q_BASE
.a_magic:            .long PRETRANSFORM_MAGIC
.a_slot0:            .long Q_SLOT0
.a_slot_stride:      .long Q_SLOT_STRIDE

/* Fixed entry used immediately after cmd $02 submission. */
.org 0x500,0xff
.global vr60_family_a_pretransform_master
vr60_family_a_pretransform_master:
    sts.l   pr,@-r15
    mov.l   r0,@-r15
    mov.l   r1,@-r15
    mov.l   r2,@-r15
    mov.l   r3,@-r15
    mov.l   r4,@-r15
    mov.l   r5,@-r15
    mov.l   r6,@-r15
    mov.l   r7,@-r15
    mov.l   r8,@-r15
    mov.l   r9,@-r15
    mov.l   r10,@-r15
    mov.l   r11,@-r15
    mov.l   r12,@-r15
    mov.l   r13,@-r15
    mov.l   r14,@-r15
    stc     sr,r0
    mov.l   r0,@-r15

    mov.l   @(.m_queue,pc),r5
    mov.l   @(H_MAGIC,r5),r0
    mov.l   @(.m_magic,pc),r1
    cmp/eq  r1,r0
    bf      .m_restore
    mov.l   @(H_STATUS,r5),r0
    cmp/eq  #STATUS_ARMED,r0
    bf      .m_restore
    mov     #STATUS_PREFLIGHT,r0
    mov.l   r0,@(H_STATUS,r5)
    mov.l   @(H_STATUS,r5),r0

    /* $0600441C has now joined the previous Slave command and published cmd
     * $02.  Refresh the shared inputs here: taking them in the pre-submit arm
     * raced the previous cmd $04, which legitimately updates family A. */
    mov.l   @(.m_divisor_source,pc),r1
    mov.w   @r1,r0
    exts.w  r0,r0
    mov.l   r0,@(H_DIVISOR,r5)
    mov.l   @(.m_clip_1000,pc),r0
    mov.l   r0,@(H_CLIP,r5)
    mov     #64,r0
    mov.l   r0,@(H_SCALE,r5)

    mov.l   @(.m_state_source,pc),r1
    mov.l   @(.m_state_snapshot,pc),r2
    mov     #48,r3
.m_copy_state:
    mov.l   @r1+,r0
    mov.l   r0,@r2
    add     #4,r2
    dt      r3
    bf      .m_copy_state

    mov.l   @(.m_desc_source,pc),r1
    mov.l   @(.m_desc_snapshot,pc),r2
    mov     #20,r3
.m_copy_descriptors:
    mov.l   @r1+,r0
    mov.l   r0,@r2
    add     #4,r2
    dt      r3
    bf      .m_copy_descriptors

    /* Complete all bounds checks before making any candidate consumable. */
    mov.l   @(.m_desc_snapshot,pc),r14
    mov.l   @(.m_state_snapshot,pc),r13
    mov.l   @(.m_slot0,pc),r4
    mov.l   @(.m_valid0,pc),r8
    mov     #1,r6                     /* active-bit cursor */
    mov     #4,r7
.m_descriptor_loop:
    mov.l   r8,@(S_VALID,r4)
    mov.w   @(0,r14),r0
    tst     r0,r0
    bt      .m_inactive

    mov.l   @(16,r14),r0
    mov.l   r0,@(S_SOURCE,r4)
    mov.l   r13,@(S_MATRIX,r4)
    mov.l   r14,@(S_DESCRIPTOR,r4)
    mov.w   @r0,r1
    extu.w  r1,r1
    tst     r1,r1
    bt      .m_overflow
    mov     #Q_MAX_VERTICES,r2
    cmp/hi  r2,r1
    bt      .m_overflow
    /* Slot 2 reserves the first Q_SPLIT_HEAD vertices for the Slave. */
    mov     #4,r0
    cmp/eq  r0,r6
    bf      .m_count_valid
    mov     #Q_SPLIT_HEAD,r0
    cmp/hi  r0,r1
    bf      .m_overflow
.m_count_valid:
    mov.l   r1,@(S_COUNT,r4)
    mov.l   @(H_ACTIVE_MASK,r5),r0
    or      r6,r0
    mov.l   r0,@(H_ACTIVE_MASK,r5)
    mov.l   @(H_VERTEX_TOTAL,r5),r0
    add     r1,r0
    mov.l   r0,@(H_VERTEX_TOTAL,r5)

.m_inactive:
    mov.l   @(.m_slot_stride,pc),r0
    add     r0,r4
    add     #Q_VALID_STRIDE,r8
    add     #48,r13
    add     #20,r14
    shll    r6
    dt      r7
    bf      .m_descriptor_loop

    /* Admission is complete.  Slave may now stream each slot while this CPU
     * continues producing the later descriptors. */
    mov     #STATUS_WORKING,r0
    mov.l   r0,@(H_STATUS,r5)
    mov.l   @(H_STATUS,r5),r0

    /* Produce the dominant 80-vertex descriptor 2 first, then descriptor 3,
     * while the Slave renders descriptors 0/1 through the untouched stock
     * transform+builder path. */
    mov.l   @(.m_desc_snapshot,pc),r14
    add     #40,r14
    mov.l   @(.m_state_snapshot,pc),r13
    add     #96,r13
    mov.l   @(.m_slot0,pc),r4
    mov.l   @(.m_slot_stride,pc),r0
    add     r0,r4
    add     r0,r4
    mov     #2,r7
.m_transform_loop:
    mov.w   @(0,r14),r0
    tst     r0,r0
    bt      .m_mark_ready

    mov.l   r4,@-r15
    mov.l   r5,@-r15
    mov.l   r7,@-r15
    mov.l   r13,@-r15
    mov.l   r14,@-r15
    mov     #2,r0
    cmp/eq  r0,r7
    bf      .m_transform_full
    bsr     .m_transform_tail
    nop
    bra     .m_transform_return
    nop
.m_transform_full:
    bsr     .m_transform_job
    nop
.m_transform_return:
    mov.l   @r15+,r14
    mov.l   @r15+,r13
    mov.l   @r15+,r7
    mov.l   @r15+,r5
    mov.l   @r15+,r4

.m_mark_ready:
    mov     #1,r0
    mov.l   r0,@(S_READY,r4)
    mov.l   @(S_READY,r4),r0
    mov.l   @(.m_slot_stride,pc),r0
    add     r0,r4
    add     #48,r13
    add     #20,r14
    dt      r7
    bf      .m_transform_loop
    bra     .m_publish_done
    nop

.m_overflow:
    mov     #4,r0
    mov.l   r0,@(H_ERROR,r5)

.m_publish_done:
    mov     #STATUS_DONE,r0
    mov.l   r0,@(H_STATUS,r5)
    mov.l   @(H_STATUS,r5),r0

.m_restore:
    mov.l   @r15+,r0
    ldc     r0,sr
    mov.l   @r15+,r14
    mov.l   @r15+,r13
    mov.l   @r15+,r12
    mov.l   @r15+,r11
    mov.l   @r15+,r10
    mov.l   @r15+,r9
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

/* Master-side bit-exact duplicate of the stock on-chip vertex transform. */
.m_transform_job:
    add     #-12,r15                 /* signed vector scratch */
    mov.l   @(S_SOURCE,r4),r13
    mov.w   @r13+,r11
    add     #2,r13
    mov     r4,r10
    add     #S_CANDIDATE,r10
    mov.l   @(S_VALID,r4),r12
    bra     .m_vertex_loop
    nop

/* Master half of descriptor 2: indices Q_SPLIT_HEAD..N-1. */
.m_transform_tail:
    add     #-12,r15
    mov.l   @(S_SOURCE,r4),r13
    mov.w   @r13+,r11
    add     #2,r13
    mov     #Q_SPLIT_HEAD,r0
    sub     r0,r11
    mov.l   @(.m_split_source_offset,pc),r0
    add     r0,r13
    mov     r4,r10
    add     #S_CANDIDATE,r10
    mov.l   @(.m_split_candidate_offset,pc),r0
    add     r0,r10
    mov.l   @(S_VALID,r4),r12
    add     #Q_SPLIT_HEAD,r12
.m_vertex_loop:
    mov.w   @r13+,r0
    mov.w   @r13+,r1
    mov.w   @r13+,r2
    mov.l   @(H_SCALE,r5),r3
    mov     r15,r8
    add     #12,r8
    muls.w  r3,r2
    sts.l   macl,@-r8
    muls.w  r3,r1
    sts.l   macl,@-r8
    muls.w  r3,r0
    sts.l   macl,@-r8

    /* Depth row: matrix +$20. */
    mov.l   @(S_MATRIX,r4),r8
    add     #32,r8
    mov     r15,r9
    clrmac
    mac.l   @r8+,@r9+
    mac.l   @r8+,@r9+
    mac.l   @r8+,@r9+
    mov.l   @r8+,r2
    sts     mach,r0
    sts     macl,r3
    xtrct   r0,r3
    add     r2,r3
    mov.l   r3,@(8,r10)
    mov.l   @(.m_div_base,pc),r8
    mov.l   r3,@(0,r8)
    mov.l   @(H_DIVISOR,r5),r7
    mov.l   r7,@(16,r8)
    mov     #0,r0
    mov.l   r0,@(20,r8)

    /* Y row: matrix +$00. */
    mov.l   @(S_MATRIX,r4),r8
    mov     r15,r9
    clrmac
    mac.l   @r8+,@r9+
    mac.l   @r8+,@r9+
    mac.l   @r8+,@r9+
    mov.l   @r8+,r2
    sts     mach,r0
    sts     macl,r1
    xtrct   r0,r1
    add     r2,r1
    mov.l   r1,@(0,r10)

    /* Z row: matrix +$10. */
    mov.l   @(S_MATRIX,r4),r8
    add     #16,r8
    mov     r15,r9
    clrmac
    mac.l   @r8+,@r9+
    mac.l   @r8+,@r9+
    mac.l   @r8+,@r9+
    mov.l   @r8+,r0
    sts     mach,r7
    sts     macl,r2
    xtrct   r7,r2
    add     r0,r2
    mov.l   r2,@(4,r10)

    mov.l   @(H_CLIP,r5),r9
    cmp/gt  r3,r9
    bt      .m_vertex_clipped
    mov.l   @(.m_div_base,pc),r8
    mov.l   @(28,r8),r3
    dmuls.l r3,r1
    sts     mach,r0
    dmuls.l r3,r2
    mov.w   r0,@(12,r10)
    sts     mach,r0
    mov.w   r0,@(14,r10)
    mov     #1,r0
    mov.b   r0,@r12
    bra     .m_vertex_next
    nop
.m_vertex_clipped:
    mov     #0,r0
    mov.b   r0,@r12
.m_vertex_next:
    add     #1,r12
    dt      r11
    bf/s    .m_vertex_loop
    add     #16,r10
    add     #12,r15
    rts
    nop

.align 2
.m_queue:          .long Q_BASE
.m_magic:          .long PRETRANSFORM_MAGIC
.m_desc_snapshot:  .long Q_DESC_SNAPSHOT
.m_state_snapshot: .long Q_STATE_SNAPSHOT
.m_slot0:          .long Q_SLOT0
.m_slot_stride:    .long Q_SLOT_STRIDE
.m_div_base:       .long 0xFFFFFF00
.m_divisor_source: .long 0x2600C0CE
.m_clip_1000:      .long 0x00001000
.m_state_source:   .long 0x2600CA60
.m_desc_source:    .long 0x2600C128
.m_valid0:         .long Q_VALID0
.m_split_source_offset:    .long (Q_SPLIT_HEAD * 6)
.m_split_candidate_offset: .long (Q_SPLIT_HEAD * 16)

/* Fixed entry at the end of independent Master stage B. */
.org 0x900,0xff
.global vr60_family_a_pretransform_release
vr60_family_a_pretransform_release:
    mov.l   r0,@-r15
    mov.l   r1,@-r15
    mov.l   r2,@-r15
    stc     sr,r0
    mov.l   r0,@-r15
    mov.l   @(.r_queue,pc),r1
.r_wait_ack:
    mov.l   @(H_RELEASE,r1),r0
    tst     r0,r0
    bf      .r_released
    mov     #64,r2
.r_backoff:
    dt      r2
    bf      .r_backoff
    bra     .r_wait_ack
    nop
.r_released:
.ifdef VR60_PRETRANSFORM_DIAGNOSTIC
    /* Isolated diagnostic signature: each fallback code burns a distinct,
     * small number of Master cycles before stage C destroys this lease. */
    mov.l   @(H_ERROR,r1),r2
    tst     r2,r2
    bt      .r_diagnostic_done
    shll8   r2
.r_diagnostic_loop:
    dt      r2
    bf      .r_diagnostic_loop
.r_diagnostic_done:
    /* Encode candidate use separately: bit 0 is split slot 2, bit 1 slot 3. */
    mov.l   @(H_USED,r1),r2
    tst     r2,r2
    bt      .r_used_done
    shll8   r2
    shll2   r2
.r_used_loop:
    dt      r2
    bf      .r_used_loop
.r_used_done:
.endif
    mov     #0,r0
    mov.l   r0,@(H_MAGIC,r1)
    mov.l   @(H_MAGIC,r1),r0
    mov.l   @r15+,r0
    ldc     r0,sr
    mov.l   @r15+,r2
    mov.l   @r15+,r1
    mov.l   @r15+,r0
    rts
    nop

.align 2
.r_queue: .long Q_BASE

.global vr60_family_a_pretransform_end
vr60_family_a_pretransform_end:
