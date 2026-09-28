; ============================================================================
; VR60 exact frustum caller adaptation ($023508-$0235F5)
; ============================================================================
; Six former BSR/delay-slot pairs now materialise the min/max registers
; produced by screen_bounds_visibility_fused.inc.  Every other opcode and
; address in the stock dispatcher is retained exactly.
; ============================================================================

        assert  *=$023508,"VR60 fused frustum callers must start at $023508"

        dc.w    $4F22,$DE12,$D912,$B072,$7802,$6153,$6263,$53E7
        dc.w    $54E8,$3317,$893C,$3247,$893A,$6173,$62C3,$53E5
        dc.w    $54E6,$3317,$8918,$3247,$8916,$3210,$895C,$56E9
        dc.w    $D308,$236B,$853E,$C808,$89FC
        ifd     VR60_EXPERIMENTAL_SCANLINE_PAIR_FUSED
        dc.w    $D802        ; $023542 mov.l $02305800 literal,r8
        dc.w    $480B        ; $023544 jsr @r8
        dc.w    $6963        ; $023546 delay: mov r6,r9
        dc.w    $A002        ; $023548 skip embedded literal after return
        dc.w    $0009        ; $02354A delay: nop
        dc.w    $0230,$5800  ; $02354C helper address
        else
        dc.w    $6963,$B0C9,$EC04,$6963,$7920,$B0C5,$ECFC
        endif
        dc.w    $A223,$4F26,$C000,$0700
        dc.w    $C000,$0740,$2000,$0000,$3237,$8B45,$3147,$8943
        dc.w    $3210,$8941,$56E9,$D309,$236B,$853E,$C808,$89FC
        dc.w    $2F66,$6963,$B0BD,$EC04,$66F6,$2F66,$6963,$7920
        dc.w    $B0B7,$ECFC,$66F6,$A204,$4F26,$0000,$2000,$0000
        dc.w    $6173,$62C3,$53E5,$54E6,$3237,$8B25,$3147,$8923
        dc.w    $3210,$8921,$D90C,$B0A4,$EC04,$D90C,$B0A1,$ECFC
        dc.w    $D809,$D90B,$B10C,$4F22,$4A28,$4A08,$4B08,$2BAB
        dc.w    $1EB1,$D806,$D907,$B103,$4F22,$4A28,$2BAB,$5AE1
        dc.w    $2BAB,$1EB1,$A13F,$4F26,$C000,$0780,$C000,$07A0
        dc.w    $C000,$07C0,$C000,$07E0,$4F26,$000B,$0009

        assert  *=$0235F6,"VR60 fused frustum callers must end at $0235F6"
