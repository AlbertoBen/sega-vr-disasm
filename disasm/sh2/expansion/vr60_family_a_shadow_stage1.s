/*
 * VR60 family-A pre-transform queue, REJECTED diagnostic stage 1.
 *
 * MEMORY/SCHEDULE CORRECTION (2026-09-05): this prototype must not be run or
 * extended.  Its $2603E000-$2603F18F allocation overlaps the stock track
 * payload copied to $0603C000 by $06004664 on every known track.  Its
 * reciprocal Slave/Master polling also causes bounded timeouts and visible
 * presentation starvation.  Retain it only as historical diagnostic source;
 * a successor requires newly proven storage and a nonblocking Slave cmd-$05
 * comparison phase.
 *
 * This target is deliberately fail-closed and never consumes the Master
 * result for rendering.  The Slave executes the complete stock on-chip
 * renderer and remains the only framebuffer writer.  For each active one of
 * the four family-A descriptors it publishes the exact matrix/context input
 * into one of two ping-pong slots.  The Master duplicates only the vertex
 * transform while the stock Slave renderer is live.  On return from stock,
 * the Slave compares every field stock actually produced, bit for bit:
 *
 *   output +0, +4, +8 always; output +12/+14 when projection ran.
 *
 * Missing/stale work, an input mismatch, >96 vertices, or a bounded wait
 * expiry records a fallback and leaves the stock result untouched.
 * Geometry, LOD, descriptor order and framebuffer ownership never change.
 *
 * ROM layout (included at file $304D00):
 *   $02304D00 producer (Master, before cmd $02)
 *   $02304E00 consumer/stock wrapper (Slave jump-table hook)
 *   $02305600 worker (Master, after cmd $02 submission)
 *
 * Rejected cache-through SDRAM allocation (below the Slave stack but inside
 * the live stock track-data region):
 *   $2603E000-$2603E07F header
 *   $2603E080-$2603E87F slot 0
 *   $2603E880-$2603F07F slot 1
 *   $2603F080-$2603F18F immutable state/descriptor snapshot
 *
 * Each $800-byte slot contains $80 bytes of metadata, 96 x $10 candidate
 * records at +$80 and 96 x $04 write masks at +$680.
 */

.ifndef VR60_EXPERIMENTAL_FAMILY_A_SHADOW_STAGE1
.error "family-A shadow stage 1 requires its isolated guard"
.endif

.equ Q_SIGNATURE,       0xFA510101
.equ Q_BASE,            0x2603E000
.equ Q_SLOT0,           0x2603E080
.equ Q_SLOT1,           0x2603E880
.equ Q_SNAPSHOT,        0x2603F080
.equ Q_MAX_VERTICES,    96

/* Header offsets. */
.equ H_SIGNATURE,       0x00
.equ H_GENERATION,      0x04
.equ H_WORKER_DONE,     0x08
.equ H_PASS_COUNT,      0x0C
.equ H_MISMATCH_COUNT,  0x10
.equ H_FALLBACK_COUNT,  0x14
.equ H_OVERFLOW_COUNT,  0x18
.equ H_PRODUCED_COUNT,  0x1C
.equ H_COMPARED_COUNT,  0x20
.equ H_TIMEOUT_COUNT,   0x24
.equ H_LAST_ERROR,      0x28
.equ H_LAST_DESCRIPTOR, 0x2C
.equ H_LAST_FIELD,      0x30
.equ H_LAST_CANDIDATE,  0x34
.equ H_LAST_STOCK,      0x38
.equ H_LAST_REMAINING,  0x3C

/* Slot offsets. */
.equ S_READY,           0x00
.equ S_CANDIDATE_DONE,  0x04
.equ S_STOCK_DONE,      0x08
.equ S_COMPARE_DONE,    0x0C
.equ S_DESCRIPTOR,      0x10
.equ S_COUNT,           0x14
.equ S_SOURCE,          0x18
.equ S_DESTINATION,     0x1C
.equ S_DIVIDEND,        0x20
.equ S_CLIP,            0x24
.equ S_SCALE,           0x28
.equ S_ERROR,           0x2C
.equ S_MATRIX,          0x30
.equ S_CANDIDATE,       0x80
.equ S_MASKS,           0x680

.section .text
.align 2

.global vr60_family_a_shadow_stage1_produce
vr60_family_a_shadow_stage1_produce:
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

    mov.l   @(.p_queue,pc),r4
    mov.l   @(.p_signature,pc),r1
    mov.l   @r4,r0
    cmp/eq  r1,r0
    bt      .p_initialized
    mov     #0,r0
    mov.l   r0,@r4
    mov.l   r0,@(4,r4)
    mov.l   r0,@(8,r4)
    mov.l   r0,@(12,r4)
    mov.l   r0,@(16,r4)
    mov.l   r0,@(20,r4)
    mov.l   r0,@(24,r4)
    mov.l   r0,@(28,r4)
    mov.l   r0,@(32,r4)
    mov.l   r0,@(36,r4)
    mov.l   r0,@(40,r4)
    mov.l   r0,@(44,r4)
    mov.l   r0,@(48,r4)
    mov.l   r0,@(52,r4)
    mov.l   r0,@(56,r4)
    mov.l   r0,@(60,r4)
    mov.l   r1,@r4
    mov.l   @r4,r0
.p_initialized:
    mov.l   @(4,r4),r6
    add     #1,r6
    tst     r6,r6
    bf      .p_generation_ok
    mov     #1,r6
.p_generation_ok:
    mov     #0,r0
    mov.l   r0,@(4,r4)              /* busy until snapshot is complete */
    mov.l   r0,@(8,r4)
    mov.l   r0,@(40,r4)
    mov.l   r0,@(44,r4)

    /* Reset both slot ownership words.  Payload bytes need not be cleared. */
    mov.l   @(.p_slot0,pc),r1
    mov     #2,r7
.p_clear_slots:
    mov.l   r0,@(0,r1)
    mov.l   r0,@(4,r1)
    mov.l   r0,@(8,r1)
    mov.l   r0,@(12,r1)
    mov.l   r0,@(44,r1)
    mov.l   @(.p_slot_stride,pc),r3
    add     r3,r1
    dt      r7
    bf      .p_clear_slots

    /* Immutable snapshot: four $30 state records then four $14 records. */
    mov.l   @(.p_state_source,pc),r1
    mov.l   @(.p_snapshot,pc),r2
    mov     #48,r3
.p_copy_state:
    mov.l   @r1+,r0
    mov.l   r0,@r2
    dt      r3
    bf/s    .p_copy_state
    add     #4,r2
    mov.l   @(.p_descriptor_source,pc),r1
    mov     #20,r3
.p_copy_descriptors:
    mov.l   @r1+,r0
    mov.l   r0,@r2
    dt      r3
    bf/s    .p_copy_descriptors
    add     #4,r2

    add     #-4,r2
    mov.l   @r2,r0                   /* drain payload before publication */
    mov.l   r6,@(4,r4)
    mov.l   @(4,r4),r0

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
.p_queue:             .long Q_BASE
.p_signature:         .long Q_SIGNATURE
.p_slot0:             .long Q_SLOT0
.p_slot_stride:       .long 0x00000800
.p_snapshot:          .long Q_SNAPSHOT
.p_state_source:      .long 0x2600CA60
.p_descriptor_source: .long 0x2600C128

/* Slave hook ABI is fixed by the command-$02 literal at file $021080. */
.org 0x100,0xff

.global vr60_family_a_shadow_stage1_consume
vr60_family_a_shadow_stage1_consume:
    /* Preserve the exact stock entry state while admitting the one call. */
    mov.l   r0,@-r15
    mov.l   r1,@-r15
    mov.l   r2,@-r15
    mov.l   r3,@-r15
    mov.l   r4,@-r15
    mov.l   r5,@-r15
    mov.l   r6,@-r15
    stc     sr,r0
    mov.l   r0,@-r15

    sts     pr,r0
    mov.l   @(.c_family_return,pc),r1
    cmp/eq  r1,r0
    bf      .c_restore_tail_stock
    mov.l   @(.c_state_cached,pc),r1
    cmp/eq  r1,r13
    bf      .c_restore_tail_stock
    mov.l   @(.c_descriptor_cached,pc),r1
    cmp/eq  r1,r14
    bf      .c_restore_tail_stock
    mov     #4,r0
    cmp/eq  r0,r7
    bf      .c_restore_tail_stock

    mov.l   @(.c_queue,pc),r5
    mov.l   @r5,r0
    mov.l   @(.c_signature,pc),r1
    cmp/eq  r1,r0
    bf      .c_restore_tail_stock
    mov.l   @(4,r5),r6
    tst     r6,r6
    bt      .c_restore_tail_stock

    /* Refuse stale/racing input rather than comparing a different job. */
    mov.l   @(.c_state_through,pc),r0
    mov.l   @(.c_snapshot,pc),r1
    mov     #48,r2
.c_validate_state:
    mov.l   @r0+,r3
    mov.l   @r1+,r4
    cmp/eq  r4,r3
    bf      .c_input_mismatch
    dt      r2
    bf      .c_validate_state
    mov.l   @(.c_descriptor_through,pc),r0
    mov     #20,r2
.c_validate_descriptors:
    mov.l   @r0+,r3
    mov.l   @r1+,r4
    cmp/eq  r4,r3
    bf      .c_input_mismatch
    dt      r2
    bf      .c_validate_descriptors
    bra     .c_restore_enter_clone
    nop

.c_input_mismatch:
    mov.l   @(16,r5),r0
    add     #1,r0
    mov.l   r0,@(16,r5)
    mov.l   @(20,r5),r0
    add     #1,r0
    mov.l   r0,@(20,r5)
    mov     #2,r0
    mov.l   r0,@(40,r5)

.c_restore_tail_stock:
    mov.l   @r15+,r0
    ldc     r0,sr
    mov.l   @r15+,r6
    mov.l   @r15+,r5
    mov.l   @r15+,r4
    mov.l   @r15+,r3
    mov.l   @r15+,r2
    mov.l   @r15+,r1
    mov.l   @(.c_stock_loop,pc),r0
    jmp     @r0
    mov.l   @r15+,r0

.c_restore_enter_clone:
    mov.l   @r15+,r0
    ldc     r0,sr
    mov.l   @r15+,r6
    mov.l   @r15+,r5
    mov.l   @r15+,r4
    mov.l   @r15+,r3
    mov.l   @r15+,r2
    mov.l   @r15+,r1
    mov.l   @r15+,r0

    /* Exact $060024DC outer loop, with diagnostics around active calls. */
    sts.l   pr,@-r15
.c_entity_loop:
    mov.w   @(0,r14),r0
    cmp/eq  #0,r0
    bt      .c_entity_next
    mov.l   r14,@-r15
    mov.l   r13,@-r15
    mov.l   r7,@-r15
    bsr     .c_copy_state_exact
    nop

    /* Preserve the precise post-$2514 register/T input while publishing. */
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

    mov.l   @(.c_queue,pc),r5
    mov.l   @(4,r5),r6              /* generation */
    mov     r14,r0
    tst     #4,r0                   /* descriptor address encodes parity */
    bt      .c_use_slot0
    mov.l   @(.c_slot1,pc),r4
    bra     .c_slot_selected
    nop
.c_use_slot0:
    mov.l   @(.c_slot0,pc),r4
.c_slot_selected:
    mov     #0,r0
    mov.l   r0,@(0,r4)
    mov.l   r0,@(4,r4)
    mov.l   r0,@(8,r4)
    mov.l   r0,@(12,r4)
    mov.l   r0,@(44,r4)
    mov.l   r14,@(16,r4)
    mov.l   @(16,r14),r3
    mov.l   r3,@(24,r4)
    mov.w   @r3,r0
    extu.w  r0,r0
    mov.l   r0,@(20,r4)
    mov.l   @(.c_context,pc),r2
    mov.l   @(44,r2),r1
    mov.l   r1,@(28,r4)
    mov.l   @(8,r2),r1
    mov.l   r1,@(32,r4)
    mov.l   @(12,r2),r1
    mov.l   r1,@(36,r4)
    mov.l   @(28,r2),r1
    mov     #64,r3
    mov     r1,r0
    tst     #2,r0
    bt      .c_scale_ready
    mov.w   @(.c_scale_2048,pc),r3
.c_scale_ready:
    mov.l   r3,@(40,r4)

    mov.l   @(20,r4),r0
    tst     r0,r0
    bt      .c_job_overflow
    mov     #Q_MAX_VERTICES,r1
    cmp/hi  r1,r0
    bf      .c_job_size_ok
.c_job_overflow:
    mov     #1,r0
    mov.l   r0,@(44,r4)
    mov.l   @(24,r5),r0
    add     #1,r0
    mov.l   r0,@(24,r5)
.c_job_size_ok:
    mov.l   @(.c_matrix,pc),r1
    mov     r4,r2
    add     #48,r2
    mov     #12,r3
.c_copy_matrix:
    mov.l   @r1+,r0
    mov.l   r0,@r2
    dt      r3
    bf/s    .c_copy_matrix
    add     #4,r2
    mov.l   r6,@(0,r4)              /* publish job last */
    mov.l   @r4,r0

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

    /* Exact stock call input and renderer. */
    mov.l   @(16,r14),r13
    mov.l   @(.c_context,pc),r14
    mov.l   @(.c_onchip,pc),r0
    jsr     @r0
    nop

    /* Preserve all stock-observable volatile results around comparison. */
    mov.l   r0,@-r15
    mov.l   r1,@-r15
    mov.l   r2,@-r15
    mov.l   r3,@-r15
    mov.l   r4,@-r15
    mov.l   r5,@-r15
    mov.l   r6,@-r15
    mov.l   r8,@-r15
    mov.l   r9,@-r15
    mov.l   r10,@-r15
    mov.l   r11,@-r15
    mov.l   r12,@-r15
    stc     sr,r0
    mov.l   r0,@-r15

    mov.l   @(.c_queue,pc),r5
    mov.l   @(4,r5),r6
    /* Recover descriptor parity from the saved outer descriptor on stack.
     * 13 diagnostic saves ($34) + saved loop R7/R13/R14: R14 is at +$40. */
    mov     r15,r0
    add     #60,r0
    mov.l   @r0,r0
    tst     #4,r0
    bt      .c_compare_slot0
    mov.l   @(.c_slot1,pc),r4
    bra     .c_compare_slot_selected
    nop
.c_compare_slot0:
    mov.l   @(.c_slot0,pc),r4
.c_compare_slot_selected:
    mov.l   r6,@(8,r4)
    mov.l   @(8,r4),r0
    mov     #64,r3
.c_wait_candidate_outer:
    mov.w   @(.c_poll_limit,pc),r2
.c_wait_candidate:
    mov.l   @(4,r4),r0
    cmp/eq  r6,r0
    bt      .c_candidate_ready
    dt      r2
    bf      .c_wait_candidate
    dt      r3
    bf      .c_wait_candidate_outer
    mov.l   @(20,r5),r0
    add     #1,r0
    mov.l   r0,@(20,r5)
    mov.l   @(36,r5),r0
    add     #1,r0
    mov.l   r0,@(36,r5)
    mov     #4,r0
    mov.l   r0,@(40,r5)
    bra     .c_compare_complete
    nop

.c_candidate_ready:
    mov.l   @(44,r4),r0
    tst     r0,r0
    bf      .c_overflow_fallback
    mov.l   @(20,r4),r7
    tst     r7,r7
    bt      .c_overflow_fallback
    mov.l   @(28,r4),r1             /* live stock destination */
    mov     r4,r2
    add     #0x7f,r2
    add     #1,r2                    /* candidate +$80 */
    mov.l   @(.c_mask_delta,pc),r3
    add     r4,r3                    /* masks +$680 */
.c_compare_vertex:
    mov     #0,r9
    mov.l   @r2+,r0
    mov.l   @r1+,r8
    cmp/eq  r8,r0
    bf      .c_record_mismatch
    mov     #4,r9
    mov.l   @r2+,r0
    mov.l   @r1+,r8
    cmp/eq  r8,r0
    bf      .c_record_mismatch
    mov     #8,r9
    mov.l   @r2+,r0
    mov.l   @r1+,r8
    cmp/eq  r8,r0
    bf      .c_record_mismatch
    mov.l   @r3+,r0
    cmp/eq  #15,r0
    bf      .c_skip_projection_compare
    mov     #12,r9
    mov.l   @r2,r0
    mov.l   @r1,r8
    cmp/eq  r8,r0
    bf      .c_record_mismatch
.c_skip_projection_compare:
    add     #4,r2
    add     #4,r1
    dt      r7
    bf      .c_compare_vertex

    mov.l   @(12,r5),r0
    add     #1,r0
    mov.l   r0,@(12,r5)
    mov.l   @(20,r4),r1
    mov.l   @(28,r5),r0
    add     r1,r0
    mov.l   r0,@(28,r5)
    mov.l   @(32,r5),r0
    add     r1,r0
    mov.l   r0,@(32,r5)
    mov     #0,r0
    mov.l   r0,@(40,r5)
    bra     .c_compare_complete
    nop

.c_record_mismatch:
    mov.l   r9,@(48,r5)
    mov.l   r0,@(52,r5)
    mov.l   r8,@(56,r5)
    mov.l   r7,@(60,r5)
    mov.l   @(16,r5),r0
    add     #1,r0
    mov.l   r0,@(16,r5)
    mov     #2,r0
    mov.l   r0,@(40,r5)
    mov.l   @(16,r4),r0
    mov.l   r0,@(44,r5)
    bra     .c_compare_complete
    nop

.c_overflow_fallback:
    mov.l   @(20,r5),r0
    add     #1,r0
    mov.l   r0,@(20,r5)
    mov     #3,r0
    mov.l   r0,@(40,r5)

.c_compare_complete:
    mov.l   r6,@(12,r4)
    mov.l   @(12,r4),r0

    mov.l   @r15+,r0
    ldc     r0,sr
    mov.l   @r15+,r12
    mov.l   @r15+,r11
    mov.l   @r15+,r10
    mov.l   @r15+,r9
    mov.l   @r15+,r8
    mov.l   @r15+,r6
    mov.l   @r15+,r5
    mov.l   @r15+,r4
    mov.l   @r15+,r3
    mov.l   @r15+,r2
    mov.l   @r15+,r1
    mov.l   @r15+,r0

    /* Exact stock epilogue for this descriptor. */
    mov.l   @r15+,r7
    mov.l   @r15+,r13
    mov.l   @r15+,r14
.c_entity_next:
    add     #48,r13
    dt      r7
    bf/s    .c_entity_loop
    add     #20,r14
    lds.l   @r15+,pr
    rts
    nop

/* Exact stock state-copy leaf ($06002514), kept local so PR is controlled. */
.c_copy_state_exact:
    mov.l   @(.c_matrix,pc),r12
    mov     #12,r7
.c_copy_state_loop:
    mov.l   @r13+,r0
    mov.l   r0,@r12
    dt      r7
    bf/s    .c_copy_state_loop
    add     #4,r12
    rts
    nop

.align 2
.c_scale_2048:       .word 0x0800
.c_poll_limit:       .word 0x4000
.c_family_return:    .long 0x06000FF4
.c_state_cached:     .long 0x0600CA60
.c_descriptor_cached:.long 0x0600C128
.c_queue:            .long Q_BASE
.c_signature:        .long Q_SIGNATURE
.c_snapshot:         .long Q_SNAPSHOT
.c_state_through:    .long 0x2600CA60
.c_descriptor_through:.long 0x2600C128
.c_stock_loop:       .long 0x060024DC
.c_slot0:            .long Q_SLOT0
.c_slot1:            .long Q_SLOT1
.c_context:          .long 0xC0000700
.c_matrix:           .long 0xC0000740
.c_onchip:           .long 0xC0000000
.c_mask_delta:       .long S_MASKS

/* Keep the Master worker entry independent of consumer growth. */
.org 0x900,0xff

.global vr60_family_a_shadow_stage1_worker
vr60_family_a_shadow_stage1_worker:
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

    mov.l   @(.w_queue,pc),r5
    mov.l   @r5,r0
    mov.l   @(.w_signature,pc),r1
    cmp/eq  r1,r0
    bf      .w_done
    mov.l   @(4,r5),r6
    tst     r6,r6
    bt      .w_done
    mov.l   @(.w_snapshot_descriptors,pc),r14
    mov     #4,r7
.w_descriptor_loop:
    mov.w   @(0,r14),r0
    tst     r0,r0
    bt      .w_descriptor_next
    mov     r14,r0
    tst     #4,r0
    bt      .w_choose_slot0
    mov.l   @(.w_slot1_ptr,pc),r4
    bra     .w_slot_selected
    nop
.w_choose_slot0:
    mov.l   @(.w_slot0_ptr,pc),r4
.w_slot_selected:
    mov     #64,r3
.w_wait_job_outer:
    mov.w   @(.w_poll_limit,pc),r2
.w_wait_job:
    mov.l   @(0,r4),r0
    cmp/eq  r6,r0
    bt      .w_job_ready
    dt      r2
    bf      .w_wait_job
    mov.l   @(40,r5),r0
    tst     r0,r0
    bf      .w_abort_generation
    dt      r3
    bf      .w_wait_job_outer
    mov.l   @(20,r5),r0
    add     #1,r0
    mov.l   r0,@(20,r5)
    mov.l   @(36,r5),r0
    add     #1,r0
    mov.l   r0,@(36,r5)
    mov     #5,r0
    mov.l   r0,@(40,r5)
    bra     .w_descriptor_next
    nop
.w_abort_generation:
    mov.l   r6,@(8,r5)
    bra     .w_done
    mov.l   @(8,r5),r0
.w_job_ready:
    mov.l   @(16,r4),r0
    mov.l   @(.w_descriptor_alias_delta,pc),r1
    add     r14,r1
    cmp/eq  r1,r0
    bf      .w_worker_fallback
    mov.l   @(44,r4),r0
    tst     r0,r0
    bf      .w_mark_candidate_done

    mov.l   r4,@-r15
    mov.l   r5,@-r15
    mov.l   r6,@-r15
    mov.l   r7,@-r15
    mov.l   r14,@-r15
    bsr     .w_transform_job
    nop
    mov.l   @r15+,r14
    mov.l   @r15+,r7
    mov.l   @r15+,r6
    mov.l   @r15+,r5
    mov.l   @r15+,r4
    bra     .w_mark_candidate_done
    nop

.w_worker_fallback:
    mov.l   @(20,r5),r0
    add     #1,r0
    mov.l   r0,@(20,r5)
    mov     #6,r0
    mov.l   r0,@(40,r5)
.w_mark_candidate_done:
    mov.l   r6,@(4,r4)
    mov.l   @(4,r4),r0
.w_descriptor_next:
    dt      r7
    bf/s    .w_descriptor_loop
    add     #20,r14
    mov.l   r6,@(8,r5)
    mov.l   @(8,r5),r0

.w_done:
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

.balign 4
.w_poll_limit:             .word 0x4000
.balign 4
.w_queue:                  .long Q_BASE
.w_signature:              .long Q_SIGNATURE
.w_snapshot_descriptors:   .long (Q_SNAPSHOT + 0xC0)
.w_slot0_ptr:              .long Q_SLOT0
.w_slot1_ptr:              .long Q_SLOT1
/* The consumer records the canonical descriptor pointer from R14.  Only the
 * queue payload itself uses the cache-through alias. */
.w_descriptor_alias_delta: .long (0x0600C128 - (Q_SNAPSHOT + 0xC0))

/* Master-side bit-exact duplicate of the stock vertex transform only. */
.w_transform_job:
    add     #-12,r15                 /* signed vector scratch */
    mov.l   @(24,r4),r13
    mov.w   @r13+,r11
    add     #2,r13
    mov     r4,r10
    add     #0x7f,r10
    add     #1,r10                   /* candidate +$80 */
    mov.l   @(.w_mask_delta,pc),r12
    add     r4,r12
.w_vertex_loop:
    mov.w   @r13+,r0
    mov.w   @r13+,r1
    mov.w   @r13+,r2
    mov.l   @(40,r4),r3
    mov     r15,r5
    add     #12,r5
    muls.w  r3,r2
    sts.l   macl,@-r5
    muls.w  r3,r1
    sts.l   macl,@-r5
    muls.w  r3,r0
    sts.l   macl,@-r5

    /* Depth/X row: state +$20, exactly stock matrix order. */
    mov     r4,r8
    add     #48,r8
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
    mov.l   @(.w_div_base,pc),r8
    mov.l   r3,@(0,r8)
    mov.l   @(32,r4),r7
    mov.l   r7,@(16,r8)
    mov     #0,r0
    mov.l   r0,@(20,r8)

    /* Y row: state +$00. */
    mov     r4,r8
    add     #48,r8
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

    /* Z row: state +$10. */
    mov     r4,r8
    add     #48,r8
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

    mov.l   @(36,r4),r9
    cmp/gt  r3,r9
    bt      .w_vertex_clipped
    mov.l   @(.w_div_base,pc),r8
    mov.l   @(28,r8),r3             /* divider quotient at $FFFFFF1C */
    dmuls.l r3,r1
    sts     mach,r0
    dmuls.l r3,r2
    mov.w   r0,@(12,r10)
    sts     mach,r0
    mov.w   r0,@(14,r10)
    mov     #15,r0
    bra     .w_store_mask
    nop
.w_vertex_clipped:
    mov     #7,r0
.w_store_mask:
    mov.l   r0,@r12
    add     #4,r12
    dt      r11
    bf/s    .w_vertex_loop
    add     #16,r10
    add     #12,r15
    rts
    nop

.balign 4
.w_mask_delta:             .long S_MASKS
.w_div_base:               .long 0xFFFFFF00

.global vr60_family_a_shadow_stage1_end
vr60_family_a_shadow_stage1_end:
