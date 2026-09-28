; Experimental, geometry-preserving schedule for the active S-6
; vertex_transform_optimized copy at $3011E0-$30123F.
;
; It is byte-identical to generated/vertex_transform_optimized.inc except at
; $301202-$30120A:
;
;   push R7; push R8; load target; JSR; save PR
;     -> load target; push R7; push R8; JSR; save PR
;
; Loading the ROM target before the two independent stack stores separates
; the load from its JSR consumer. Stack layout, call delay slot, arithmetic,
; loop count, descriptors and geometry are unchanged.

        dc.w    $4F22
        dc.w    $51E7
        dc.w    $52E8
        dc.w    $4128
        dc.w    $4228
        dc.w    $50E5
        dc.w    $6313
        dc.w    $6423
        dc.w    $210B
        dc.w    $220B
        dc.w    $1E1A
        dc.w    $1E2B
        dc.w    $50E6
        dc.w    $230B
        dc.w    $240B
        dc.w    $1E3C
        dc.w    $1E4D
        dc.w    $D00B       ; MOV.L $02301230,R0 (moved before stack stores)
        dc.w    $2F76
        dc.w    $2F86
        dc.w    $400B
        dc.w    $4F22
        dc.w    $68F6
        dc.w    $67F6
        dc.w    $8581
        dc.w    $C801
        dc.w    $8F01
        dc.w    $7810
        dc.w    $7804
        dc.w    $4710
        dc.w    $8BF1
        dc.w    $4F26
        dc.w    $000B
        dc.w    $0009
        dc.w    $0009
        dc.w    $0009
        dc.w    $0009
        dc.w    $0009
        dc.w    $0009
        dc.w    $0009
        ifd     VR60_EXPERIMENTAL_VERTEX_SDRAM_TARGET
        ; The same renderer block also exists in the game's executable SDRAM
        ; image at $0600350A.  Keep this as an isolated timing A/B because the
        ; SDRAM copy is dynamically patched independently of the ROM copy.
        dc.w    $0600
        else
        dc.w    $0202
        endif
        dc.w    $350A
        dc.w    $0009
        dc.w    $0009
        dc.w    $0009
        dc.w    $0009
        dc.w    $0009
        dc.w    $0009
