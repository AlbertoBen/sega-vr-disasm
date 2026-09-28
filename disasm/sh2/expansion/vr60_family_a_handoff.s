/*
 * vr60_family_a_handoff -- exact-position dual-SH2 authority probe
 *
 * Expansion ROM layout (included at file $306000 / SH2 $02306000):
 *   +$000  Slave wrapper for the family-A $060024DC call
 *   +$200  Master arm routine
 *   +$300  Master worker
 *
 * This is deliberately a correctness rung, not yet a performance candidate.
 * The Slave stops at the exact family-A call site after flushing its root
 * output.  The Master renders all four descriptors directly into the current
 * Slave record cursor and Slave bucket lanes, then the Slave resumes at the
 * canonical next batch.  Therefore painter ordering is not changed merely by
 * moving the work to the other SH2.
 *
 * $06016000-$06017FFF is phase-idle from cmd $02 submit until Master stage C
 * ($060010AC).  The DONE/ACK barrier releases the lease before that call.  All
 * mailbox and cross-CPU output accesses use the cache-through $26 alias.
 */

.ifndef VR60_EXPERIMENTAL_FAMILY_A_HANDOFF
.error "family-A handoff requires VR60_EXPERIMENTAL_FAMILY_A_HANDOFF"
.endif

.section .text
.align 2

.equ HANDOFF_MAGIC,       0x48414E44  /* "HAND" */
.equ STATUS_ARMED,        1
.equ STATUS_REQUEST,      2
.equ STATUS_CLAIMED,      3
.equ STATUS_DONE,         4
.equ STATUS_ACK,          5

/* Cache-through mailbox at $26016000. */
.equ M_MAGIC,             0x00
.equ M_STATUS,            0x04
.equ M_ERROR,             0x08
.equ M_CURSOR,            0x0C
.equ M_SLAVE_CONTEXT,     0x20  /* 40 longs: $C0000700-$C000079F */
.equ M_MASTER_CONTEXT,    0xC0  /* 40 longs: private save/restore */

.global vr60_family_a_handoff_slave
vr60_family_a_handoff_slave:
    /* Admit only the one exact Slave cmd-$02 family-A invocation. */
    mov.l   r1,@-r15
    sts     pr,r0
    mov.l   @(.slave_return,pc),r1
    cmp/eq  r1,r0
    bf      .slave_tail_stock
    mov.l   @(.family_state,pc),r1
    cmp/eq  r1,r13
    bf      .slave_tail_stock
    mov.l   @(.family_descriptor,pc),r1
    cmp/eq  r1,r14
    bf      .slave_tail_stock
    mov     #4,r0
    cmp/eq  r0,r7
    bf      .slave_tail_stock
    mov.l   @(.mailbox,pc),r1
    mov.l   @(M_MAGIC,r1),r0
    mov.l   @(.magic,pc),r2
    cmp/eq  r2,r0
    bf      .slave_tail_stock
    mov.l   @(M_STATUS,r1),r0
    cmp/eq  #STATUS_ARMED,r0
    bf      .slave_tail_stock

    mov.l   @r15+,r1

    /* Preserve the caller-visible register file while this CPU waits. */
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

    /* Flush the root descriptor's cached record/bucket writes before handing
     * the same logical output stream to the other CPU. */
    mov.l   @(.cache_purge,pc),r0
    jsr     @r0
    nop

    /* Publish the complete live Slave renderer workspace $0700-$079F,
     * including matrix residue and the per-CPU completion callback. */
    mov.l   @(.local_context,pc),r2
    mov.l   @(.mailbox_context,pc),r1
    mov     #40,r3
.slave_publish_context:
    mov.l   @r2+,r0
    mov.l   r0,@r1
    add     #4,r1
    dt      r3
    bf      .slave_publish_context

    mov.l   @(.mailbox,pc),r1
    mov     #STATUS_REQUEST,r0
    mov.l   r0,@(M_STATUS,r1)
    mov.l   @(M_STATUS,r1),r0       /* same-address write-buffer sync */

.slave_wait_done:
    mov.l   @(M_STATUS,r1),r0
    cmp/eq  #STATUS_DONE,r0
    bf      .slave_wait_done

    mov.l   @(M_ERROR,r1),r0
    cmp/eq  #0,r0
    bf      .slave_declined

    /* Continue all later Slave producers through cache-through pointers so
     * they cannot observe stale lines after the Master's writes. */
    mov.l   @(.local_context,pc),r2
    mov.l   @(M_CURSOR,r1),r0
    mov.l   r0,@(36,r2)
    mov.l   @(.slave_record_end,pc),r0
    mov.l   r0,@(40,r2)
    mov.l   @(.slave_vertex_scratch,pc),r0
    mov.l   r0,@(44,r2)
    mov.l   @(.slave_bucket_a,pc),r0
    mov.l   r0,@(48,r2)
    mov.l   @(.slave_bucket_b,pc),r0
    mov.l   r0,@(52,r2)
    mov.l   @(.slave_counter_a,pc),r0
    mov.l   r0,@(56,r2)
    mov.l   @(.slave_counter_b,pc),r0
    mov.l   r0,@(60,r2)

    mov     #STATUS_ACK,r0
    mov.l   r0,@(M_STATUS,r1)
    mov.l   @(M_STATUS,r1),r0

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

    /* Match the stock four-item loop's externally visible iterator state. */
    mov.l   @(.family_next_state,pc),r13
    mov.l   @(.family_next_descriptor,pc),r14
    mov     #0,r7
    cmp/eq  r7,r7                    /* stock final DT leaves T=1 */
    rts
    nop

.slave_declined:
    /* No live output was touched: ACK and execute the complete stock call. */
    mov     #STATUS_ACK,r0
    mov.l   r0,@(M_STATUS,r1)
    mov.l   @(M_STATUS,r1),r0
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
    mov.l   @(.stock_entity_loop,pc),r0
    jmp     @r0
    nop

.slave_tail_stock:
    mov.l   @r15+,r1
    mov.l   @(.stock_entity_loop,pc),r0
    jmp     @r0
    nop

.align 2
.slave_return:          .long 0x06000FF4
.family_state:          .long 0x0600CA60
.family_descriptor:     .long 0x0600C128
.family_next_state:     .long 0x0600CB20
.family_next_descriptor:.long 0x0600C178
.stock_entity_loop:     .long 0x060024DC
.cache_purge:           .long 0x060045CC
.local_context:         .long 0xC0000700
.mailbox:               .long 0x26016000
.mailbox_context:       .long 0x26016020
.magic:                 .long HANDOFF_MAGIC
.slave_record_end:      .long 0x26015FEC
.slave_vertex_scratch:  .long 0x2601C000
.slave_bucket_a:        .long 0x26020010
.slave_bucket_b:        .long 0x26023010
.slave_counter_a:       .long 0x2600DB01
.slave_counter_b:       .long 0x2600DE01

/* Fixed entry used by vr60_interp_camera_render.s. */
.org 0x200
.global vr60_family_a_handoff_arm
vr60_family_a_handoff_arm:
    mov.l   r0,@-r15
    mov.l   r1,@-r15
    mov.l   @(.arm_mailbox,pc),r1
    mov.l   @(.arm_magic,pc),r0
    mov.l   r0,@(M_MAGIC,r1)
    mov     #0,r0
    mov.l   r0,@(M_ERROR,r1)
    mov.l   r0,@(M_CURSOR,r1)
    mov     #STATUS_ARMED,r0
    mov.l   r0,@(M_STATUS,r1)
    mov.l   @(M_STATUS,r1),r0
    mov.l   @r15+,r1
    mov.l   @r15+,r0
    rts
    nop

.align 2
.arm_mailbox: .long 0x26016000
.arm_magic:   .long HANDOFF_MAGIC

/* Fixed entry used immediately after Master submits Slave cmd $02. */
.org 0x300
.global vr60_family_a_handoff_master
vr60_family_a_handoff_master:
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

    mov.l   @(.master_mailbox,pc),r1
.master_wait_request:
    mov.l   @(M_STATUS,r1),r0
    cmp/eq  #STATUS_REQUEST,r0
    bf      .master_wait_request

    /* Invalidate this CPU's view of the shared descriptors/models before
     * admission.  The Slave's purge cannot invalidate the Master cache. */
    mov.l   @(.master_cache_purge,pc),r0
    jsr     @r0
    nop

    mov.l   @(.master_mailbox,pc),r1
    mov     #STATUS_CLAIMED,r0
    mov.l   r0,@(M_STATUS,r1)
    mov.l   @(M_STATUS,r1),r0

    /* Preserve the Master's complete live renderer workspace exactly. */
    mov.l   @(.master_local_context,pc),r2
    mov.l   @(.master_context_save,pc),r1
    mov     #40,r3
.master_save_context:
    mov.l   @r2+,r0
    mov.l   r0,@r1
    add     #4,r1
    dt      r3
    bf      .master_save_context

    /* Install the published Slave workspace into this CPU's private OCM. */
    mov.l   @(.master_context_source,pc),r1
    mov.l   @(.master_local_context,pc),r2
    mov     #40,r3
.master_load_context:
    mov.l   @r1,r0
    add     #4,r1
    mov.l   r0,@r2
    add     #4,r2
    dt      r3
    bf      .master_load_context

    /* Redirect every mutable output to the Slave half through the $26 alias.
     * The current record pointer came from the Slave and needs only +$20000000
     * to become cache-through. */
    mov.l   @(.master_local_context,pc),r2
    mov.l   @(36,r2),r0
    mov.l   @(.cache_alias_delta,pc),r1
    add     r1,r0
    mov.l   r0,@(36,r2)
    mov.l   @(.master_record_end,pc),r0
    mov.l   r0,@(40,r2)
    mov.l   @(.master_vertex_scratch,pc),r0
    mov.l   r0,@(44,r2)
    mov.l   @(.master_bucket_a,pc),r0
    mov.l   r0,@(48,r2)
    mov.l   @(.master_bucket_b,pc),r0
    mov.l   r0,@(52,r2)
    mov.l   @(.master_counter_a,pc),r0
    mov.l   r0,@(56,r2)
    mov.l   @(.master_counter_b,pc),r0
    mov.l   r0,@(60,r2)

    mov.l   @(.master_family_state,pc),r13
    mov.l   @(.master_family_descriptor,pc),r14
    mov.l   @(.master_stock_loop,pc),r0
    jsr     @r0
    mov     #4,r7

    /* Publish the resulting cursor before DONE. */
    mov.l   @(.master_local_context,pc),r2
    mov.l   @(36,r2),r0
    mov.l   @(.master_mailbox,pc),r1
    mov.l   r0,@(M_CURSOR,r1)
    mov.l   @(M_CURSOR,r1),r0

    /* Restore the Master context byte-for-byte for its canonical own work. */
    mov.l   @(.master_context_save,pc),r1
    mov.l   @(.master_local_context,pc),r2
    mov     #40,r3
.master_restore_context:
    mov.l   @r1,r0
    add     #4,r1
    mov.l   r0,@r2
    add     #4,r2
    dt      r3
    bf      .master_restore_context

    mov.l   @(.master_mailbox,pc),r1
    mov     #STATUS_DONE,r0
    mov.l   r0,@(M_STATUS,r1)
    mov.l   @(M_STATUS,r1),r0

.master_wait_ack:
    mov.l   @(M_STATUS,r1),r0
    cmp/eq  #STATUS_ACK,r0
    bf      .master_wait_ack

    bra     .master_restore_registers
    nop

.master_decline:
    mov.l   @(.master_mailbox,pc),r1
    mov     #1,r0
    mov.l   r0,@(M_ERROR,r1)
    mov     #STATUS_DONE,r0
    mov.l   r0,@(M_STATUS,r1)
    mov.l   @(M_STATUS,r1),r0
.master_wait_decline_ack:
    mov.l   @(M_STATUS,r1),r0
    cmp/eq  #STATUS_ACK,r0
    bf      .master_wait_decline_ack

.master_restore_registers:
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

.align 2
.master_mailbox:          .long 0x26016000
.master_local_context:    .long 0xC0000700
.master_context_source:   .long 0x26016020
.master_context_save:     .long 0x260160C0
.cache_alias_delta:       .long 0x20000000
.master_record_end:       .long 0x26015FEC
.master_vertex_scratch:   .long 0x2601C000
.master_bucket_a:         .long 0x26020010
.master_bucket_b:         .long 0x26023010
.master_counter_a:        .long 0x2600DB01
.master_counter_b:        .long 0x2600DE01
.master_family_state:     .long 0x0600CA60
.master_family_descriptor:.long 0x0600C128
.master_stock_loop:       .long 0x060024DC
.master_cache_purge:      .long 0x060045CC
.align 2

.global vr60_family_a_handoff_end
vr60_family_a_handoff_end:
