; ============================================================================
; VR60 ABI-safe split on-chip vertex leaf ($022674-$0226FB)
; ============================================================================
; With CCR=$09 only C0000000-C00007FF is data-array RAM; C0000800+ is live
; cache and cannot hold code.  The 160-byte exact leaf is therefore split:
;
;   C0000128-C00001AF  entry + hot loop (this block, 136 bytes)
;   C00006D4-C00006F7  setup + literals (installed by the restore helper)
;
; The entry branches to the setup tail and returns to C000012C for the hot
; loop.  Callbacks/templates at C00001B0+ remain byte-exact for later stages.
; ============================================================================

        assert  *=$022674,"VR60 split vertex leaf start"

        dc.w    $A2D4        ; bra C00006D4
        dc.w    $5AEB        ; delay: mov.l @(44,r14),r10

; Exact loop/epilogue words 12..73 from vr60_vertex_fast.bin, relocated
; rigidly from C000012C.  The internal BF/S displacement remains unchanged.
        ifd     VR60_EXPERIMENTAL_ONCHIP_VERTEX_MUL_SCHEDULE
        ; Fetch Z by displacement, then use the X load and the R13 advance as
        ; independent work between MULS.W and STS.L.  This preserves the
        ; source cursor, vector layout (Z,Y,X at 0778/0774/0770), arithmetic
        ; and final live registers while hiding two MACL dependencies.
        dc.w    $85D2,$20CF,$62D5,$4512
        dc.w    $61D5,$21CF,$7D02,$4512
        dc.w    $22CF,$4512
        else
        dc.w    $60D5,$61D5,$62D5
        ifd     VR60_EXPERIMENTAL_ONCHIP_VERTEX_SHIFT
        ; The only admitted scales are 64 and 2048.  MOV.W has already
        ; sign-extended each coordinate, so SHAD by 6/11 is bit-exact to the
        ; stock signed-word multiply while avoiding the MACL dependency.
        dc.w    $42CC,$2526        ; shad r12,r2 / mov.l r2,@-r5
        dc.w    $41CC,$2516        ; shad r12,r1 / mov.l r1,@-r5
        dc.w    $40CC,$2506        ; shad r12,r0 / mov.l r0,@-r5
        else
        dc.w    $22CF,$4512,$21CF ; muls.w/sts.l, stock arithmetic path
        dc.w    $4512,$20CF,$4512
        endif
        endif
        dc.w    $0028,$054F,$054F
        dc.w    $054F,$75F4,$6246,$000A
        dc.w    $031A,$230D,$332C,$1630
        dc.w    $1674,$E000,$1605,$0028
        dc.w    $74D0,$054F,$1A32,$054F
        dc.w    $054F,$75F4,$6246,$000A
        dc.w    $011A,$0028,$210D,$312C
        dc.w    $1A10,$054F,$054F,$054F
        ifd     VR60_EXPERIMENTAL_ONCHIP_VERTEX_MUL_SCHEDULE
        ; The scheduled coordinate block contributes one word.  Drop the
        ; stock MAC-pipeline NOP here: CMP/GT plus the independent matrix load
        ; still separate the third MAC.L from its first STS consumer.
        dc.w    $3937,$6846,$000A
        else
        ifd     VR60_EXPERIMENTAL_ONCHIP_VERTEX_NOP_REMOVE
        ; CMP/GT and the following matrix load provide two independent issue
        ; slots before STS MACH; the SH2 interlock covers any residual MAC.L
        ; latency without changing arithmetic or observable state.
        dc.w    $3937,$6846,$000A
        else
        dc.w    $0009,$3937,$6846,$000A
        endif
        endif
        dc.w    $021A,$220D,$328C,$1A21
        ifd     VR60_EXPERIMENTAL_ONCHIP_VERTEX_BT_SCHEDULE
        ; Evaluate the clip predicate before DT as stock does, then decrement
        ; R11 in the delayed branch slot.  The optional projection path does
        ; not read R11 or T, so BF/S observes the exact stock DT result.
        dc.w    $8D07,$4B10,$5367,$313D ; bt/s clip_done / dt r11
        dc.w    $000A,$323D,$81A6,$000A
        dc.w    $81A7
        else
        dc.w    $8906,$5367,$313D,$000A
        dc.w    $323D,$81A6,$000A,$81A7
        dc.w    $4B10
        endif
        ifd     VR60_EXPERIMENTAL_ONCHIP_VERTEX_NOP_REMOVE
        dc.w    $8FC6,$7A10,$5CE7 ; shortened loop still targets 012C
        else
        dc.w    $8FC5,$7A10,$5CE7
        endif
        dc.w    $000B,$75F4

        ifd     VR60_EXPERIMENTAL_ONCHIP_VERTEX_NOP_REMOVE
        dcb.w   5,$0009      ; preserve callbacks after the shortened loop
        else
        dcb.w   4,$0009      ; preserve callbacks at C00001B0
        endif

        assert  *=$0226FC,"VR60 split vertex leaf end"
