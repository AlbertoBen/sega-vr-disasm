/*
 * VR60 family-A shared-queue shadow probe (REJECTED diagnostic only).
 *
 * MEMORY-SAFETY CORRECTION (2026-09-05): the $2603E000-$2603E12F
 * allocation overlaps the stock track payload copied to $0603C000 by
 * $06004664.  Every known track reaches into this range.  Do not run or
 * extend this prototype until storage has been reclaimed and audited across
 * the complete relevant lifecycle.  The historical run below the stack only
 * established a narrow observation; the queue write itself is not fail-closed
 * with respect to stock SDRAM contents.
 *
 * This is deliberately a transport/ownership probe, not a promoted render
 * path.  The Master publishes the exact four family-A state records and four
 * descriptors through cache-through SDRAM.  The Slave validates that snapshot
 * immediately before the stock family-A entity loop and then ALWAYS tail-jumps
 * to the stock renderer with the original register/SR state.  Consequently:
 *
 *   - Slave remains the only framebuffer writer/rasterizer.
 *   - descriptor count, order, geometry and LOD are unchanged.
 *   - missing/stale/mismatching queue data fails closed to the stock path.
 *   - no COMM lane is borrowed and no on-chip context byte is repurposed.
 *
 * The probe was intended to establish the producer/consumer scheduling and
 * byte-exact input contract needed before a future queue could carry
 * pre-transformed vertices.  It does NOT compute or consume pre-transformed
 * vertices, and the allocation audit invalidates it as decision-grade proof.
 *
 * ROM layout when included at file $304D00:
 *   $02304D00  vr60_family_a_shadow_produce (Master)
 *   $02304E00  vr60_family_a_shadow_consume (Slave call wrapper)
 *
 * Shared cache-through SDRAM block ($130 bytes used):
 *   $2603E000 +00 signature      ($FA510001)
 *             +04 ready_gen     (0 while producer is writing)
 *             +08 consumed_gen
 *             +0C pass_count
 *             +10 mismatch_count
 *             +14 fallback_count (stock calls with no fresh snapshot, plus overrun)
 *             +18 last_error    (0 pass/normal fallback, 2 mismatch, 3 overrun)
 *             +1C eligible      (1 only after exact Slave validation)
 *             +20 state[4][$30]
 *             +E0 descriptor[4][$14]
 *
 * $C0000738/$C000073C are NOT free scratch: stock $060022BC initializes
 * them to $0600DB00/$0600DE00 and on-chip code reads context +$38/+3C.
 */

.ifndef VR60_EXPERIMENTAL_FAMILY_A_SHADOW_QUEUE
.error "family-A shadow queue requires VR60_EXPERIMENTAL_FAMILY_A_SHADOW_QUEUE"
.endif

.section .text
.align 2

.global vr60_family_a_shadow_produce
vr60_family_a_shadow_produce:
    sts.l   pr,@-r15
    mov.l   r0,@-r15
    mov.l   r1,@-r15
    mov.l   r2,@-r15
    mov.l   r3,@-r15
    mov.l   r4,@-r15
    stc     sr,r0
    mov.l   r0,@-r15

    mov.l   @(.queue_base,pc),r4
    mov.l   @(.signature,pc),r1
    mov.l   @r4,r0
    cmp/eq  r1,r0
    bt      .producer_initialized

    /* First publication owns and deterministically initializes the header. */
    mov     #0,r0
    mov.l   r0,@r4
    mov.l   r0,@(4,r4)
    mov.l   r0,@(8,r4)
    mov.l   r0,@(12,r4)
    mov.l   r0,@(16,r4)
    mov.l   r0,@(20,r4)
    mov.l   r0,@(24,r4)
    mov.l   r0,@(28,r4)
    mov.l   r1,@r4
    mov.l   @r4,r0                 /* same-address write-buffer drain */

.producer_initialized:
    /* Detect a producer overrun, then invalidate ready/eligible while copying. */
    mov.l   @(4,r4),r0
    tst     r0,r0
    bt      .producer_not_pending
    mov.l   @(8,r4),r1
    cmp/eq  r1,r0
    bt      .producer_not_pending
    mov.l   @(20,r4),r1
    add     #1,r1
    mov.l   r1,@(20,r4)
    mov     #3,r1
    mov.l   r1,@(24,r4)
.producer_not_pending:
    mov     #0,r0
    mov.l   r0,@(4,r4)
    mov.l   r0,@(28,r4)

    /* Snapshot four $30-byte state records. */
    mov.l   @(.state_source,pc),r1
    mov     r4,r2
    add     #0x20,r2
    mov     #48,r3                   /* $C0 bytes / 4 */
.copy_state:
    mov.l   @r1+,r0
    mov.l   r0,@r2
    dt      r3
    bf/s    .copy_state
    add     #4,r2

    /* Snapshot four $14-byte descriptors immediately after the state block. */
    mov.l   @(.descriptor_source,pc),r1
    mov     #20,r3                   /* $50 bytes / 4 */
.copy_descriptors:
    mov.l   @r1+,r0
    mov.l   r0,@r2
    dt      r3
    bf/s    .copy_descriptors
    add     #4,r2

    add     #-4,r2
    mov.l   @r2,r0                   /* drain payload writes before publish */
    mov.l   @(8,r4),r0
    add     #1,r0
    tst     r0,r0
    bf      .publish_generation
    mov     #1,r0                    /* generation zero is reserved for busy */
.publish_generation:
    mov.l   r0,@(4,r4)               /* publish last */
    mov.l   @(4,r4),r0               /* same-address write-buffer drain */

    mov.l   @r15+,r0
    ldc     r0,sr
    mov.l   @r15+,r4
    mov.l   @r15+,r3
    mov.l   @r15+,r2
    mov.l   @r15+,r1
    mov.l   @r15+,r0
    lds.l   @r15+,pr
    rts
    nop

.align 2
.queue_base:        .long 0x2603e000
.signature:         .long 0xfa510001
.state_source:      .long 0x2600ca60
.descriptor_source: .long 0x2600c128

/* Keep the consumer ABI entry fixed at $02304E00. */
.org 0x100,0xff

.global vr60_family_a_shadow_consume
vr60_family_a_shadow_consume:
    /* Preserve every scratch register and T exactly before the stock tail. */
    mov.l   r0,@-r15
    mov.l   r1,@-r15
    mov.l   r2,@-r15
    mov.l   r3,@-r15
    mov.l   r4,@-r15
    mov.l   r5,@-r15
    mov.l   r6,@-r15
    stc     sr,r0
    mov.l   r0,@-r15

    /* Admit only the exact Slave cmd-$02 family-A call. */
    sts     pr,r0
    mov.l   @(.family_a_return,pc),r1
    cmp/eq  r1,r0
    bf      .consumer_tail_stock
    mov.l   @(.state_cached,pc),r1
    cmp/eq  r1,r13
    bf      .consumer_tail_stock
    mov.l   @(.descriptor_cached,pc),r1
    cmp/eq  r1,r14
    bf      .consumer_tail_stock
    mov     #4,r0
    cmp/eq  r0,r7
    bf      .consumer_tail_stock

    mov.l   @(.consumer_queue,pc),r5
    mov.l   @r5,r0
    mov.l   @(.consumer_signature,pc),r1
    cmp/eq  r1,r0
    bf      .consumer_tail_stock      /* producer never owned this block */

    mov.l   @(4,r5),r6                /* published generation */
    tst     r6,r6
    bt      .consumer_missing
    mov.l   @(8,r5),r0
    cmp/eq  r0,r6
    bt      .consumer_missing          /* stale/already consumed */

    /* Compare the exact cache-through state snapshot. */
    mov.l   @(.state_through,pc),r0
    mov     r5,r1
    add     #0x20,r1
    mov     #48,r2
.compare_state:
    mov.l   @r0+,r3
    mov.l   @r1+,r4
    cmp/eq  r4,r3
    bf      .consumer_mismatch
    dt      r2
    bf      .compare_state

    /* Compare the exact cache-through descriptor snapshot. */
    mov.l   @(.descriptor_through,pc),r0
    mov     #20,r2
.compare_descriptors:
    mov.l   @r0+,r3
    mov.l   @r1+,r4
    cmp/eq  r4,r3
    bf      .consumer_mismatch
    dt      r2
    bf      .compare_descriptors

    mov.l   r6,@(8,r5)
    mov.l   @(12,r5),r0
    add     #1,r0
    mov.l   r0,@(12,r5)
    mov     #0,r0
    mov.l   r0,@(24,r5)
    mov     #1,r0
    mov.l   r0,@(28,r5)
    bra     .consumer_sync
    nop

.consumer_mismatch:
    mov.l   r6,@(8,r5)
    mov.l   @(16,r5),r0
    add     #1,r0
    mov.l   r0,@(16,r5)
    mov     #2,r0
    mov.l   r0,@(24,r5)
    mov     #0,r0
    mov.l   r0,@(28,r5)
    bra     .consumer_sync
    nop

.consumer_missing:
    mov.l   @(20,r5),r0
    add     #1,r0
    mov.l   r0,@(20,r5)
    mov     #0,r0                    /* expected stock call: not a data error */
    mov.l   r0,@(24,r5)
    mov     #0,r0
    mov.l   r0,@(28,r5)

.consumer_sync:
    mov.l   @(28,r5),r0               /* drain status writes before stock */

.consumer_tail_stock:
    mov.l   @r15+,r0
    ldc     r0,sr
    mov.l   @r15+,r6
    mov.l   @r15+,r5
    mov.l   @r15+,r4
    mov.l   @r15+,r3
    mov.l   @r15+,r2
    mov.l   @r15+,r1
    mov.l   @(.stock_entity_loop,pc),r0
    jmp     @r0
    mov.l   @r15+,r0

.align 2
.family_a_return:    .long 0x06000ff4
.state_cached:       .long 0x0600ca60
.descriptor_cached:  .long 0x0600c128
.consumer_queue:     .long 0x2603e000
.consumer_signature: .long 0xfa510001
.state_through:      .long 0x2600ca60
.descriptor_through: .long 0x2600c128
.stock_entity_loop:  .long 0x060024dc

.global vr60_family_a_shadow_queue_end
vr60_family_a_shadow_queue_end:
