/*
 * Direct, ABI-preserving fast path for the three live RLE renderer entries.
 *
 * Runtime address: $02305C00 (file $305C00).
 * Entry from the tiny SDRAM trampolines:
 *   R0=7  -> stock type 7 shared entry, with R8/R9 already prepared
 *   R0=9  -> stock type 9 entry ($06003FC6)
 *   R0=11 -> stock type 11 entry ($06003FF4), including R13 negation
 *   R0=12 -> stock type 12 entry ($06004002)
 *
 * The stock byte loop is retained for short runs.  Runs of ten or more use
 * aligned word stores containing the same repeated byte; an odd leading byte
 * and odd tail are handled explicitly.  Transparent (value-zero) runs keep
 * the stock no-write cursor adjustment.  R2/R3 are saved because the stock
 * leaf does not clobber them.
 */

.ifndef VR60_EXPERIMENTAL_RLE_DIRECT_FAST
.error "direct RLE helper requires its isolated guard"
.endif

.section .text
.align 2

.global vr60_rle_direct_fast
vr60_rle_direct_fast:
    mov.l   r2,@-r15
    mov.l   r3,@-r15

    cmp/eq  #7,r0
    bt      .entry_type7
    cmp/eq  #9,r0
    bt      .entry_type9
    cmp/eq  #11,r0
    bt      .entry_type11

    /* Type 12: context count, positive stride. */
    mov.l   @(8,r14),r8
    mov.l   @(4,r14),r9
    add     #2,r8
    mov.w   @(2,r14),r0
    bra     .decode
    mov     r0,r7

.entry_type11:
    mov.l   @(8,r14),r8
    mov.l   @(4,r14),r9
    add     #2,r8
    mov.w   @(2,r14),r0
    mov     r0,r7
    bra     .decode
    neg     r13,r13

.entry_type9:
    mov.l   @(8,r14),r8
    mov.l   @(4,r14),r9

.entry_type7:
    mov.w   @r8+,r7

.decode:
.outer_loop:
    mov     r9,r1

.inner_load:
    mov.w   @r8+,r0
    tst     r0,r0
    bt      .outer_end

    extu.b  r0,r6
    shlr8   r0
    extu.b  r0,r0
    tst     r0,r0
    bt      .skip_fill

    mov     #10,r3
    cmp/hs  r3,r6
    bf      .byte_fill

    /* Duplicate the value into both bytes of R2. */
    mov     r0,r2
    shll8   r2
    or      r0,r2

    /* Predecrement byte stores need an even R1 before word stores. */
    mov     #1,r3
    tst     r3,r1
    bt      .word_count
    mov.b   r0,@-r1
    dt      r6
    bt      .inner_load

.word_count:
    shlr    r6
    movt    r3
    tst     r6,r6
    bt      .word_tail

.word_fill:
    dt      r6
    bf/s    .word_fill
    mov.w   r2,@-r1

.word_tail:
    tst     r3,r3
    bt      .inner_load
    mov.b   r0,@-r1
    bra     .inner_load
    nop

.byte_fill:
    dt      r6
    bf/s    .byte_fill
    mov.b   r0,@-r1
    bra     .inner_load
    nop

.skip_fill:
    bra     .inner_load
    sub     r6,r1

.outer_end:
    dt      r7
    bf/s    .outer_loop
    add     r13,r9

    mov.l   @r15+,r3
    mov.l   @r15+,r2
    rts
    nop

.global vr60_rle_direct_fast_end
vr60_rle_direct_fast_end:
