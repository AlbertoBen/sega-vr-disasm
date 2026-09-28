; ============================================================================
; VR60 experimental 1P scheduler V-INT routes
; ============================================================================
;
; These private slots are routing scaffolding only. They deliberately tail-
; jump to the stock $10 V-INT handler and do not consume COMM1, swap a 32X
; framebuffer, reset $C87E, or change gameplay cadence. Keeping the routes
; private lets later render-submit/commit work be validated in normal 1P
; without changing the shared $10 handler used by menus, replay and Free Run.
;
; Slot $40 is selected after 1P state 0 ($C87E = 4).
; Slot $48 is selected after 1P state 4 ($C87E = 8).
; State 8 and the existing state-C fallback continue to use slot $54.
; ============================================================================

vr60_vint_substep_0_route:
        jmp     $00881A6E              ; exact stock V-INT $10 behavior

vr60_vint_substep_4_route:
        jmp     $00881A6E              ; exact stock V-INT $10 behavior

; The two-phase candidate keeps the stock renderer and 68000 gameplay
; authority, but runs state 0 and state 4 in one main-loop iteration. State 8
; remains on the following TV frame, giving the renderer one VBlank of slack.
        ifd     VR60_EXPERIMENTAL_30FPS_MERGE
vr60_merge_after_state_0:
        cmpi.w  #$0004,($FFFFC87E).w
        bne.s   vr60_merge_fail_closed
        jmp     $00884D00              ; normal 1P state-4 handler

; The burst child also enters state 8 immediately. State 8 still selects
; V-INT $54, whose stock COMM1 gate commits only a completed SH2 frame. If
; rendering misses the deadline, state C remains the stock fallback.
        ifd     VR60_EXPERIMENTAL_60FPS_BURST
vr60_burst_after_state_4:
        cmpi.w  #$0008,($FFFFC87E).w
        bne.s   vr60_merge_fail_closed
        jmp     $00884D1A              ; normal 1P state-8 handler
        endif

vr60_merge_fail_closed:
        move.w  #$000C,($FFFFC87E).w   ; use the stock render-wait fallback
        move.w  #$0054,$00FF0008
        rts
        endif
