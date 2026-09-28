; ============================================================================
; VR60 direct RLE fast-path trampolines ($023FC4-$02400D)
; ============================================================================
; These bytes are copied to shared SDRAM $06003FC4 during normal boot.  Each
; live dispatcher entry tail-jumps to $02305C00 and supplies its exact type
; in R0.  R1 is stock-clobbered, JMP preserves the caller PR, and the
; shared delay-slot NOP at $023FC4 remains intact.
; ============================================================================

        assert  *=$023FC4,"VR60 direct RLE trampolines must start at $023FC4"

; Shared delay slot from unrolled_data_copy, then type 9 at $023FC6.
        dc.w    $0009
        dc.w    $D101,$412B,$84E0          ; mov.l helper,r1 / jmp @r1 / type
        dc.w    $0230,$5C00
        dcb.w   18,$0009

; Type 11 at $023FF4 (negative stride).
        dc.w    $D101,$412B,$E00B,$0009
        dc.w    $0230,$5C00,$0009

; Type 12 at $024002 (positive stride).
        dc.w    $D101,$412B,$E00C
        dc.w    $0230,$5C00,$0009

        assert  *=$02400E,"VR60 direct RLE trampolines must end at $02400E"
