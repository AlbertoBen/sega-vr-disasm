; ============================================================================
; Exact scanline table-load schedule ($0236DA-$0236F9)
; ============================================================================
; CMP/EQ depends only on R0/R11, so execute it between the indexed load and
; its store.  The store does not modify T and remains before the conditional
; branch; addresses, values, write order, loop exits and final ABI are exact.
; ============================================================================

        assert  *=$0236DA,"VR60 scanline schedule must start at $0236DA"

        dc.w    $D805,$60A3
        dc.w    $018E        ; mov.l @(r0,r8),r1
        dc.w    $30B0        ; cmp/eq r11,r0 (independent load-use slot)
        dc.w    $2912        ; mov.l r1,@r9
        dc.w    $8D06,$7904,$30CC,$AFF8,$C90C
        dc.w    $0000,$C000,$0740,$E0FF,$000B,$2902

        assert  *=$0236FA,"VR60 scanline schedule must end at $0236FA"
