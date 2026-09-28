; Experimental, geometry-preserving register reuse for $023644-$0236D9.
;
; Byte-identical to the stock bounds_compare_short.inc followed by
; visibility_short.inc except for their first instructions:
;
;   $023644  MOV.L @(4,PC),R8  -> MOV R9,R8
;   $023688  MOV.L @(5,PC),R8  -> ADD #2,R8
;
; The only callers are inside frustum_cull_short.  screen_coords_short leaves
; R9 at $C0000740, and bounds_compare_short leaves R8 at that same address.
; Both visibility call paths therefore enter with R8=$C0000740.  Literal data
; remains in place so every subsequent ROM address is unchanged.

        ; bounds_compare_short ($023644-$023687)
        dc.w    $6893       ; MOV R9,R8 (stock: PC-relative literal load)
        dc.w    $8580
        dc.w    $6103
        dc.w    $6203
        dc.w    $8582
        dc.w    $3013
        dc.w    $8904
        dc.w    $A006
        dc.w    $6103
        dc.w    $0000
        dc.w    $C000
        dc.w    $0740
        dc.w    $3203
        dc.w    $8900
        dc.w    $6203
        dc.w    $8584
        dc.w    $3013
        dc.w    $8901
        dc.w    $A003
        dc.w    $6103
        dc.w    $3203
        dc.w    $8900
        dc.w    $6203
        dc.w    $8586
        dc.w    $3013
        dc.w    $8901
        dc.w    $000B
        dc.w    $6103
        dc.w    $3203
        dc.w    $8901
        dc.w    $000B
        dc.w    $6203
        dc.w    $000B
        dc.w    $0009

        ; visibility_short ($023688-$0236D9)
        dc.w    $7802       ; ADD #2,R8 (stock: PC-relative literal load)
        dc.w    $8580
        dc.w    $EA00
        dc.w    $EB00
        dc.w    $6103
        dc.w    $6203
        dc.w    $8582
        dc.w    $3013
        dc.w    $8904
        dc.w    $EA04
        dc.w    $A006
        dc.w    $6103
        dc.w    $C000
        dc.w    $0742
        dc.w    $3203
        dc.w    $8901
        dc.w    $EB04
        dc.w    $6203
        dc.w    $8584
        dc.w    $3013
        dc.w    $8902
        dc.w    $EA08
        dc.w    $A004
        dc.w    $6103
        dc.w    $3203
        dc.w    $8901
        dc.w    $EB08
        dc.w    $6203
        dc.w    $8586
        dc.w    $3013
        dc.w    $8902
        dc.w    $EA0C
        dc.w    $000B
        dc.w    $6103
        dc.w    $3203
        dc.w    $8902
        dc.w    $EB0C
        dc.w    $000B
        dc.w    $6203
        dc.w    $000B
        dc.w    $0009
