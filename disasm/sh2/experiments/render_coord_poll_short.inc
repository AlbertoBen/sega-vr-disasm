; ============================================================================
; Exact render-coordinator status-poll throttle experiment ($0239F0-$023A51)
; ============================================================================
; The stock loop waits 16 iterations before polling the same hardware status
; bit again.  These isolated variants change only that delay count: the status
; test, all inputs/outputs, control flow and renderer data remain untouched.
;
; Default experimental count: 4.  Define VR60_EXPERIMENTAL_RENDER_POLL_1 for
; the aggressive one-iteration A/B after the count-4 safety gate passes.
; ============================================================================

        assert  *=$0239F0,"VR60 render poll patch must start at $0239F0"

        dc.w    $4F22,$D00E,$400B,$0009,$B02B,$0009,$BFD8,$0009
        dc.w    $D00B,$51E9,$210B,$851E,$C804,$891D,$C802,$8B13
        dc.w    $D008,$400B,$2FE6,$6EF6,$51E9,$E008,$811E,$9004
        dc.w    $51E9,$7140,$2109,$AFEB,$1E19,$BFFF,$0600,$45CC
        dc.w    $2000,$0000,$C000,$0000,$9003,$811E,$D001,$402B
        dc.w    $4F26,$AB00,$0600,$442C

        ifd     VR60_EXPERIMENTAL_RENDER_POLL_1
        dc.w    $E701        ; MOV #1,R7 (stock: MOV #16,R7 / $E710)
        else
        dc.w    $E704        ; MOV #4,R7 (stock: MOV #16,R7 / $E710)
        endif

        dc.w    $4710,$8BFD,$AFDA,$0009

        assert  *=$023A52,"VR60 render poll patch must end at $023A52"
