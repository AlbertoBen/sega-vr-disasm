; ============================================================================
; VR60 type-7 bounds handler with direct RLE continuation ($023D3E-$023D53)
; ============================================================================
; Type 7 normally joins the decoder at $023FCA after preparing R8/R9.  The
; direct fast-path owns that old inner-loop area, so branch two words earlier
; to the common trampoline at $023FC6.  Its delay slot and every other opcode
; remain stock; the trampoline reads type 7 from the unchanged context.
; ============================================================================

        assert  *=$023D3E,"VR60 type-7 RLE handler must start at $023D3E"
        dc.w    $85E1,$9105,$3013,$8904
        dc.w    $58E2,$59E1
        dc.w    $A13C        ; $023D4A: BRA $023FC6 (was $023FCA)
        dc.w    $390C        ; delay: ADD R0,R9
        dc.w    $0200,$000B,$0009
        assert  *=$023D54,"VR60 type-7 RLE handler must end at $023D54"
