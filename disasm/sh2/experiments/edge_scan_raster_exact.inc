; ============================================================================
; Exact edge-scan right-boundary fast path ($023BA8-$023CB3)
; ============================================================================
; Reuses the already calculated halfword address when the right edge is even.
; The external entry at $023C3E and all generated entry points remain at their
; stock addresses.  Pixel coverage, span endpoints and geometry are unchanged.
; ============================================================================

        assert  *=$023BA8,"VR60 edge scan must start at $023BA8"

        dc.w    $851F,$940B,$C802,$8B0F,$2049,$6408,$240B,$D004
        dc.w    $4518,$4500,$350C,$DE03,$000B,$0009,$FF00,$0000
        dc.w    $2400,$4000,$C000,$0188,$2409,$6053,$C801,$8B00
        dc.w    $6448,$D005,$4518,$4500,$350C,$DE04,$C505,$C802
        dc.w    $8BFC,$000B,$0009,$0000,$2402,$4000,$C000,$01F4
        dc.w    $62C9,$622F,$63D9,$633F,$312C,$3320,$891E,$C505
        dc.w    $C802,$8FFC,$E001,$2208,$8902,$2140,$7101,$7201
        dc.w    $2308,$8F01,$6033,$0544,$3028
        ifd     VR60_EXPERIMENTAL_RASTER_ARITHMETIC
; d-1 >= 0 replaces d+1 >= 2; positive length = (d-1)>>1.
; Saves one ADD on each hardware fill, preserving R2 and T. Only no-fill R0
; differs, and the actual polygon/coordinator continuations overwrite it.
; See analysis/VR60_RASTER_ARITHMETIC_PROPOSAL_20260920.md and compiled tests.
        assert  *=$023C22,"raster arithmetic patch start"
        dc.w    $70FF,$E202,$4011,$8F0A,$4001,$C102,$6013,$4001
        dc.w    $C103,$6043,$000B,$C104,$0009
        assert  *=$023C3C,"raster arithmetic patch end"
        else
        dc.w    $7001,$E202,$3023,$8F0A,$4001,$70FF,$C102,$6013
        dc.w    $4001,$C103,$6043,$000B,$C104
        endif
        dc.w    $0009,$C104,$000B,$0009,$C505,$C802
        dc.w    $8BFC,$000B,$2140,$E202,$3023,$8BF5,$4001,$2141
        dc.w    $4010,$8FFC,$7102,$000B,$0009,$0009,$62C9,$622F
        dc.w    $63D9,$633F,$6448,$313C,$3320,$8917,$6033,$C801
        dc.w    $8F03,$6048,$2100,$71FF,$73FF,$7101,$6033,$3028
        dc.w    $7001,$E302,$3033,$8F03,$4001,$4010,$8FFD,$2145
        dc.w    $6023,$C801,$8900,$2144,$000B,$0009,$6023,$C801
        dc.w    $8B02,$6048,$000B,$2100,$000B,$2140

        assert  *=$023CB4,"VR60 edge scan must end at $023CB4"
