; ============================================================================
; VR60 on-ROM FPS counter
; ============================================================================
;
; Counts completed SH2 render commits in an exact 60-VBlank NTSC window and
; draws "FPS:NN" into the completed packed-pixel back buffer immediately
; before the normal FS toggle.  This measures frames delivered by the ROM,
; not the host emulator's presentation rate.
;
; Integration contracts:
;   - The V-INT vector calls vr60_fps_vint_wrapper on every VBlank.  The
;     wrapper tail-jumps to the original handler and does not use $C87A/$C964,
;     because the original handler has an idle early exit.
;   - vr60_fps_commit_overlay replaces the six-byte BCHG at unified V-INT
;     file $01C42C.  It finishes with that exact BCHG so the following BNE
;     consumes the original Z flag.
;   - The commit hook runs only after COMM1 acknowledgement, FM acquisition,
;     and the VBlank wait.  It writes only the current back buffer through
;     the normal $840000 aperture and never changes FM itself.
;
; RAM $FF7A40-$FF7A4B is reserved slack immediately after the 3,840-byte
; VR60 AI staging allocation ($FF6B40-$FF7A3F).  A magic value makes startup
; deterministic even though this slack is not part of the race-scene clear.
; ============================================================================

VR60_FPS_VBLANKS       equ     $00FF7A40
VR60_FPS_COMMITS       equ     $00FF7A42
VR60_FPS_PUBLISHED     equ     $00FF7A44
VR60_FPS_VALID         equ     $00FF7A46
VR60_FPS_MAGIC         equ     $00FF7A48
VR60_FPS_TOTAL_COMMITS equ     $00FF7A4C       ; monotonic gate/provenance counter
VR60_FPS_MAGIC_VALUE   equ     $46505331       ; ASCII "FPS1"

VR60_FPS_ORIGINAL_VINT equ     $00881684

; Existing racing-HUD palette indices: opaque black and opaque white.
VR60_FPS_BG            equ     $01
VR60_FPS_FG            equ     $20
VR60_FPS_X             equ     272
VR60_FPS_Y             equ     4

; ----------------------------------------------------------------------------
; Every-TV-VBlank timebase.  The first sample can be a partial gameplay
; second; all subsequent samples cover exactly 60 NTSC VBlanks.
; Clobbers no data/address register.  The original handler's initial TST.W
; overwrites the CCR set here.
; ----------------------------------------------------------------------------
vr60_fps_vint_wrapper:
        cmpi.l  #VR60_FPS_MAGIC_VALUE,(VR60_FPS_MAGIC).l
        beq.s   .initialized
        clr.l   (VR60_FPS_VBLANKS).l   ; clears VBlank + commit words
        clr.l   (VR60_FPS_PUBLISHED).l ; clears published + valid words
        clr.w   (VR60_FPS_TOTAL_COMMITS).l
        move.l  #VR60_FPS_MAGIC_VALUE,(VR60_FPS_MAGIC).l
.initialized:
        addq.w  #1,(VR60_FPS_VBLANKS).l
        cmpi.w  #60,(VR60_FPS_VBLANKS).l
        blo.s   .tail

        move.w  (VR60_FPS_COMMITS).l,(VR60_FPS_PUBLISHED).l
        clr.w   (VR60_FPS_COMMITS).l
        clr.w   (VR60_FPS_VBLANKS).l
        move.w  #1,(VR60_FPS_VALID).l

.tail:
        jmp     VR60_FPS_ORIGINAL_VINT

; ----------------------------------------------------------------------------
; Completed-frame hook.  This symbol is called in place of BCHG #0,$C80C.
; The original BCHG remains the final CCR-changing instruction on both paths.
; ----------------------------------------------------------------------------
vr60_fps_commit_overlay:
        bsr.w   vr60_fps_record_overlay
        bchg    #0,($FFFFC80C).w        ; preserve the stock following-BNE contract
        rts

; Shared by the stock $54 commit and the private interpolated-current commit.
; It records and draws one completed presentation but never toggles C80C/FS.
vr60_fps_record_overlay:
        addq.w  #1,(VR60_FPS_COMMITS).l
        addq.w  #1,(VR60_FPS_TOTAL_COMMITS).l
        tst.w   (VR60_FPS_VALID).l
        beq.s   .return

        movem.l d0-d6/a0-a4,-(sp)

        ; Only the racing 256-colour packed-pixel mode is compatible.
        moveq   #0,d0
        move.b  MARS_VDP_MODE+1,d0
        andi.w  #3,d0
        cmpi.w  #1,d0
        beq.s   .draw

        movem.l (sp)+,d0-d6/a0-a4
.return:
        rts

.draw:
        ; Packed-pixel mode is also used briefly by menus and black scene
        ; transitions, where the racing line table is not valid.  Count every
        ; completed commit, but draw only while the normal 1P race dispatcher
        ; owns the main-loop vector.
        cmpi.l  #$00884CBC,$00FF0002
        bne.w   .restore_and_return

        ; Clamp display to two decimal digits, then form font offsets.
        moveq   #0,d0
        move.w  (VR60_FPS_PUBLISHED).l,d0
        cmpi.w  #99,d0
        bls.s   .value_ok
        moveq   #99,d0
.value_ok:
        moveq   #10,d1
        divu    d1,d0                  ; quotient low, remainder high
        move.w  d0,d1                  ; tens
        swap    d0                     ; ones
        move.w  d0,d2
        mulu    #5,d1
        mulu    #5,d2
        addi.w  #20,d1                 ; digit 0 follows F/P/S/colon
        addi.w  #20,d2

        lea     MARS_FRAMEBUFFER,a0
        lea     vr60_fps_font(pc),a2
        lea     vr60_fps_pattern_lut(pc),a3
        moveq   #0,d4                  ; font row 0..4

.font_row:
        ; Find the first scaled scanline through the framebuffer line table.
        move.w  d4,d6
        add.w   d6,d6                  ; row * 2 (vertical scale)
        addi.w  #VR60_FPS_Y,d6         ; screen y
        add.w   d6,d6                  ; line-table byte index
        moveq   #0,d0
        move.w  0(a0,d6.w),d0          ; line offset is expressed in words
        add.l   d0,d0                  ; convert to bytes
        movea.l a0,a1
        adda.l  d0,a1
        adda.w  #VR60_FPS_X,a1
        movea.l a1,a4                  ; retain row start for vertical copy

        ; F
        moveq   #0,d0
        move.b  0(a2,d4.w),d0
        lsl.w   #3,d0
        move.l  0(a3,d0.w),(a1)+
        move.l  4(a3,d0.w),(a1)+

        ; P
        moveq   #0,d0
        move.b  5(a2,d4.w),d0
        lsl.w   #3,d0
        move.l  0(a3,d0.w),(a1)+
        move.l  4(a3,d0.w),(a1)+

        ; S
        moveq   #0,d0
        move.b  10(a2,d4.w),d0
        lsl.w   #3,d0
        move.l  0(a3,d0.w),(a1)+
        move.l  4(a3,d0.w),(a1)+

        ; Colon
        moveq   #0,d0
        move.b  15(a2,d4.w),d0
        lsl.w   #3,d0
        move.l  0(a3,d0.w),(a1)+
        move.l  4(a3,d0.w),(a1)+

        ; Tens digit
        move.w  d1,d3
        add.w   d4,d3
        moveq   #0,d0
        move.b  0(a2,d3.w),d0
        lsl.w   #3,d0
        move.l  0(a3,d0.w),(a1)+
        move.l  4(a3,d0.w),(a1)+

        ; Ones digit
        move.w  d2,d3
        add.w   d4,d3
        moveq   #0,d0
        move.b  0(a2,d3.w),d0
        lsl.w   #3,d0
        move.l  0(a3,d0.w),(a1)+
        move.l  4(a3,d0.w),(a1)+

        ; Duplicate the 48-pixel row once for 2x vertical scaling.
        addq.w  #2,d6                  ; next line-table word entry
        moveq   #0,d0
        move.w  0(a0,d6.w),d0
        add.l   d0,d0
        movea.l a0,a1
        adda.l  d0,a1
        adda.w  #VR60_FPS_X,a1
        move.l  (a4)+,(a1)+
        move.l  (a4)+,(a1)+
        move.l  (a4)+,(a1)+
        move.l  (a4)+,(a1)+
        move.l  (a4)+,(a1)+
        move.l  (a4)+,(a1)+
        move.l  (a4)+,(a1)+
        move.l  (a4)+,(a1)+
        move.l  (a4)+,(a1)+
        move.l  (a4)+,(a1)+
        move.l  (a4)+,(a1)+
        move.l  (a4)+,(a1)+

        addq.w  #1,d4
        cmpi.w  #5,d4
        blo.w   .font_row

        movem.l (sp)+,d0-d6/a0-a4
        rts

.restore_and_return:
        movem.l (sp)+,d0-d6/a0-a4
        rts

; Four fixed glyphs followed by digits 0-9.  Each byte is one 3-pixel row,
; bit 2 on the left.  The LUT expands it to 8 pixels: 3 doubled pixels plus
; a two-pixel background spacer.
vr60_fps_font:
        dc.b    7,4,6,4,4              ; F
        dc.b    6,5,6,4,4              ; P
        dc.b    7,4,7,1,7              ; S
        dc.b    0,2,0,2,0              ; :
        dc.b    7,5,5,5,7              ; 0
        dc.b    2,6,2,2,7              ; 1
        dc.b    7,1,7,4,7              ; 2
        dc.b    7,1,7,1,7              ; 3
        dc.b    5,5,7,1,1              ; 4
        dc.b    7,4,7,1,7              ; 5
        dc.b    7,4,7,5,7              ; 6
        dc.b    7,1,2,2,2              ; 7
        dc.b    7,5,7,5,7              ; 8
        dc.b    7,5,7,1,7              ; 9
        even

; 3-bit row -> 8 packed pixels (black/white HUD palette indices).
vr60_fps_pattern_lut:
        dc.l    $01010101,$01010101    ; 000
        dc.l    $01010101,$20200101    ; 001
        dc.l    $01012020,$01010101    ; 010
        dc.l    $01012020,$20200101    ; 011
        dc.l    $20200101,$01010101    ; 100
        dc.l    $20200101,$20200101    ; 101
        dc.l    $20202020,$01010101    ; 110
        dc.l    $20202020,$20200101    ; 111

        even
