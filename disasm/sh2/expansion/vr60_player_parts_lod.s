/*
 * VR60 experimental family-A player-parts wrapper.
 *
 * It recognizes only the exact family-A player-parts call made by Slave
 * cmd $02:
 *
 *   PR=$06000FF4, state=$0600CA60, descriptor=$0600C128, count=4
 *
 * That call is reduced to its first descriptor (count=1).  In the historical
 * VR60_EXPERIMENTAL_30HZ_LOD build this sheds descriptors 1..3.  In the exact
 * VR60_EXPERIMENTAL_FAMILY_A_SPLIT A/B the Master renders those three records
 * separately, so geometry and LOD remain unchanged.  The player ROOT
 * descriptor ($0600C114/$0600CA30) is not touched.  Every admission failure
 * tail-jumps to the stock $060024DC loop with the original count.
 *
 * ROM/runtime entry: file $303A10 / SH2 $02303A10.
 */

.ifndef VR60_EXPERIMENTAL_30HZ_LOD
.ifndef VR60_EXPERIMENTAL_FAMILY_A_SPLIT
.error "family-A wrapper requires VR60_EXPERIMENTAL_30HZ_LOD or VR60_EXPERIMENTAL_FAMILY_A_SPLIT"
.endif
.endif

.section .text
.align 2

.global vr60_player_parts_lod
.global vr60_family_a_split_slave
vr60_family_a_split_slave:
vr60_player_parts_lod:
    /* R1 is live at the stock call sites; R0 held the consumed call target. */
    mov.l   r1,@-r15

    sts     pr,r0
    mov.l   @(.family_a_return,pc),r1
    cmp/eq  r1,r0
    bf      .tail_stock

    mov.l   @(.parts_state,pc),r1
    cmp/eq  r1,r13
    bf      .tail_stock

    mov.l   @(.parts_descriptor,pc),r1
    cmp/eq  r1,r14
    bf      .tail_stock

    mov     #4,r0
    cmp/eq  r0,r7
    bf      .tail_stock

    /* Slave owns descriptor 0.  The exact split build assigns 1..3 to Master. */
    mov     #1,r7

.tail_stock:
    mov.l   @r15+,r1
    mov.l   @(.stock_entity_loop,pc),r0
    jmp     @r0
    nop

.align 2
.family_a_return:   .long 0x06000ff4
.parts_state:       .long 0x0600ca60
.parts_descriptor:  .long 0x0600c128
.stock_entity_loop: .long 0x060024dc

.global vr60_player_parts_lod_end
vr60_player_parts_lod_end:
