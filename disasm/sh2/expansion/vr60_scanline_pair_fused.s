/*
 * Exact fused replacement for the two consecutive scanline_setup calls at
 * $02023542.  Both calls walk the same four-long on-chip table, first with a
 * +4 stride and then with a -4 stride. This helper dispatches one of the 16
 * start/end combinations and loads each selected value directly into R1,
 * avoiding stack spills while emitting the same two lists and terminators.
 *
 * Runtime address: $02305800 (file $305800).
 * Entry: R6/R9 = first destination, R10 = start offset, R11 = end offset.
 * Exit matches the second stock call exactly:
 *   R0=-1, R1=table[R11], R8=$C0000740, R9=second terminator,
 *   R12=-4, T=1; R2-R7/R10/R11 and PR are preserved.
 */

.ifndef VR60_EXPERIMENTAL_SCANLINE_PAIR_FUSED
.error "scanline pair helper requires its isolated guard"
.endif

.section .text
.align 2

.global vr60_scanline_pair_fused
vr60_scanline_pair_fused:
    /* Establish the stock table base explicitly; the caller uses R8 for the
     * helper address. No assumption about interrupt timing is required. */
    mov.l   .lit_table_base,r8

    /* R10/R11 are the stock offsets 0,4,8,12.  Convert them to a word-table
     * index (8*start_index + 2*end_index), load a signed local displacement,
     * then use the engine's DRC-safe BRAF form instead of an absolute JMP. */
    mova    @(.branch_table,pc),r0
    mov     r0,r1
    mov     r10,r0
    shll    r0
    mov     r11,r12
    shlr    r12
    add     r12,r0
    mov.w   @(r0,r1),r12
.branch_origin:
    braf    r12
    mov     #-1,r0

.align 2
.branch_table:
    .word .case_00 - (.branch_origin + 4)
    .word .case_01 - (.branch_origin + 4)
    .word .case_02 - (.branch_origin + 4)
    .word .case_03 - (.branch_origin + 4)
    .word .case_10 - (.branch_origin + 4)
    .word .case_11 - (.branch_origin + 4)
    .word .case_12 - (.branch_origin + 4)
    .word .case_13 - (.branch_origin + 4)
    .word .case_20 - (.branch_origin + 4)
    .word .case_21 - (.branch_origin + 4)
    .word .case_22 - (.branch_origin + 4)
    .word .case_23 - (.branch_origin + 4)
    .word .case_30 - (.branch_origin + 4)
    .word .case_31 - (.branch_origin + 4)
    .word .case_32 - (.branch_origin + 4)
    .word .case_33 - (.branch_origin + 4)

.macro load_vertex value
    .ifc \value,r2
        mov.l   @(0,r8),r1
    .endif
    .ifc \value,r3
        mov.l   @(4,r8),r1
    .endif
    .ifc \value,r4
        mov.l   @(8,r8),r1
    .endif
    .ifc \value,r5
        mov.l   @(12,r8),r1
    .endif
.endm

.macro put value
    load_vertex \value
    mov.l   r1,@r9
    add     #4,r9
.endm

.macro split_lists gap
    mov.l   r0,@r9
    /* Rebase from the caller's original destination.  Do not derive the
     * second list from a transient terminator pointer. */
    mov     r6,r9
    add     #32,r9
.endm

.macro finish_with endpoint
    load_vertex \endpoint
    mov.l   r1,@r9
    add     #4,r9
    bra     .finish
    mov.l   r0,@r9
.endm

/* start 0 */
.case_00:
    put r2
    split_lists 28
    finish_with r2
.case_01:
    put r2
    put r3
    split_lists 24
    put r2
    put r5
    put r4
    finish_with r3
.case_02:
    put r2
    put r3
    put r4
    split_lists 20
    put r2
    put r5
    finish_with r4
.case_03:
    put r2
    put r3
    put r4
    put r5
    split_lists 16
    put r2
    finish_with r5

/* start 1 */
.case_10:
    put r3
    put r4
    put r5
    put r2
    split_lists 16
    put r3
    finish_with r2
.case_11:
    put r3
    split_lists 28
    finish_with r3
.case_12:
    put r3
    put r4
    split_lists 24
    put r3
    put r2
    put r5
    finish_with r4
.case_13:
    put r3
    put r4
    put r5
    split_lists 20
    put r3
    put r2
    finish_with r5

/* start 2 */
.case_20:
    put r4
    put r5
    put r2
    split_lists 20
    put r4
    put r3
    finish_with r2
.case_21:
    put r4
    put r5
    put r2
    put r3
    split_lists 16
    put r4
    finish_with r3
.case_22:
    put r4
    split_lists 28
    finish_with r4
.case_23:
    put r4
    put r5
    split_lists 24
    put r4
    put r3
    put r2
    finish_with r5

/* start 3 */
.case_30:
    put r5
    put r2
    split_lists 24
    put r5
    put r4
    put r3
    finish_with r2
.case_31:
    put r5
    put r2
    put r3
    split_lists 20
    put r5
    put r4
    finish_with r3
.case_32:
    put r5
    put r2
    put r3
    put r4
    split_lists 16
    put r5
    finish_with r4
.case_33:
    put r5
    split_lists 28
    finish_with r5

.finish:
    cmp/eq  r11,r11
    rts
    mov     #-4,r12

.global vr60_scanline_pair_fused_end
vr60_scanline_pair_fused_end:

.align 2
.lit_table_base:
    .long   0xC0000740
