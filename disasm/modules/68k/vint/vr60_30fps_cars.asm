; ============================================================================
; VR60 30-FPS scheduler: interpolate the other cars (placed at file $01D800).
;
; The 30-FPS renders mix the camera between the previous and the current
; logic tick (factor 0, 1/3 or 2/3).  The object records in the scene block
; still held the current tick, so every car stood up to a tick ahead of the
; camera and jumped back at each tick: visible judder.  Their position and
; angle words are now mixed with the same factor.
;
; Object records: $FF61CC + n*$3C, n = 0..16.  Mixed words: +$12,+$14,+$16
; (position), +$18,+$1A (angles), signed 16-bit deltas.  A delta beyond
; +-$1000 (slot reuse, respawn) keeps the live value.
;
; At each tick (state-8 tail) a list of the moving words is built with
; prev and third = (next - prev) * 85 / 256; a render then only adds
; 0, 1 or 2 thirds, and the live words are restored after the send.
; RAM ($FF7600-$FF79FF; $FF7600-$FF7A3F stayed zero through boot, menus and
; two races in the fuzz runs):
;   $FF7600 current-tick words (17 x 5), $FF76B0 list count,
;   $FF7700 list (offset from $FF6100, prev, third; <= 85 x 6 bytes),
;   $FF7900 live words saved while a mixed block is being sent.
; ============================================================================

VR60_30_CAR_FIRST       equ     $00FF61CC+$12
VR60_30_CAR_STRIDE      equ     $3C
VR60_30_CAR_COUNT       equ     17
VR60_30_CAR_NEXT        equ     $00FF7600
VR60_30_CAR_LISTN       equ     $00FF76B0
VR60_30_CAR_LIST        equ     $00FF7700
VR60_30_CAR_SAVE        equ     $00FF7900

; State-8 tail.  d0.b <> 0: first tick of a race (no motion yet).
vr60_30_cars_tail:
        movem.l d0-d6/a0-a2,-(sp)
        move.b  d0,d5
        lea     (VR60_30_CAR_FIRST).l,a0
        lea     (VR60_30_CAR_NEXT).l,a1
        lea     (VR60_30_CAR_LIST).l,a2
        moveq   #0,d4                           ; list count
        moveq   #VR60_30_CAR_COUNT-1,d3
.rec:
        moveq   #4,d2
.fld:
        move.w  (a1),d0                         ; prev (last tick)
        move.w  (a0),d1                         ; next (this tick)
        move.w  d1,(a1)+
        tst.b   d5
        bne.s   .skip
        sub.w   d0,d1
        beq.s   .skip
        cmpi.w  #$1000,d1
        bgt.s   .skip
        cmpi.w  #-$1000,d1
        blt.s   .skip
        muls.w  #85,d1
        asr.l   #8,d1
        move.l  a0,d6
        ; offset from $FF6100 fits a word
        subi.w  #$6100,d6
        move.w  d6,(a2)+
        move.w  d0,(a2)+
        move.w  d1,(a2)+
        addq.w  #1,d4
.skip:
        addq.l  #2,a0
        dbra    d2,.fld
        lea     VR60_30_CAR_STRIDE-10(a0),a0
        dbra    d3,.rec
        move.w  d4,(VR60_30_CAR_LISTN).l
        movem.l (sp)+,d0-d6/a0-a2
        rts

; Launch: d2 = 0, 85 or 171.  Save the live words, write prev + k * third.
vr60_30_cars_mix:
        movem.l d0-d4/a0-a3,-(sp)
        lea     $00FF6100,a3
        lea     (VR60_30_CAR_LIST).l,a1
        lea     (VR60_30_CAR_SAVE).l,a2
        move.w  (VR60_30_CAR_LISTN).l,d3
        beq.s   .done
        subq.w  #1,d3
        moveq   #0,d4                           ; k = 0
        tst.w   d2
        beq.s   .loop
        moveq   #1,d4
        cmpi.w  #128,d2
        blo.s   .loop
        moveq   #2,d4
.loop:
        move.w  (a1)+,d0                        ; offset
        move.w  0(a3,d0.w),(a2)+                ; save live
        move.w  (a1)+,d1                        ; prev
        move.w  (a1)+,d2                        ; third
        cmpi.b  #1,d4
        blo.s   .put
        add.w   d2,d1
        cmpi.b  #2,d4
        bne.s   .put
        add.w   d2,d1
.put:
        move.w  d1,0(a3,d0.w)
        dbra    d3,.loop
.done:
        movem.l (sp)+,d0-d4/a0-a3
        rts

; After the block was sent: put the live words back.
vr60_30_cars_restore:
        movem.l d0-d1/a1-a3,-(sp)
        lea     $00FF6100,a3
        lea     (VR60_30_CAR_LIST).l,a1
        lea     (VR60_30_CAR_SAVE).l,a2
        move.w  (VR60_30_CAR_LISTN).l,d1
        beq.s   .done
        subq.w  #1,d1
.loop:
        move.w  (a1)+,d0
        addq.l  #4,a1
        move.w  (a2)+,0(a3,d0.w)
        dbra    d1,.loop
.done:
        movem.l (sp)+,d0-d1/a1-a3
        rts

; Camera-only EXTRA: stream the 17 x 5 (mixed) car words and 3 pad words to
; the FIFO after the camera block (a2 = FIFO).  Clobbers d0-d1/a1.
vr60_30_cars_fifo:
        lea     (VR60_30_CAR_FIRST).l,a1
        moveq   #VR60_30_CAR_COUNT-1,d1
.rec:
        move.w  (a1)+,(a2)
        move.w  (a1)+,(a2)
        move.w  (a1)+,(a2)
        move.w  (a1)+,(a2)
        move.w  (a1)+,(a2)
        lea     VR60_30_CAR_STRIDE-10(a1),a1
        dbra    d1,.rec
        moveq   #0,d0
        move.w  d0,(a2)
        move.w  d0,(a2)
        move.w  d0,(a2)
        rts

        ifd     VR60_30_HEADING_WRAP
; Mix one camera word for a 1/3 or 2/3 render.
; In: d0 = offset, d1 = next - prev (16-bit), d2 = factor/256, a0 = prev
; snapshot.  Out: d1 = mixed word.
; +$30/+$44/+$58 (wheel angles) and +$0A (heading), +$1C, +$1E wrap with
; period $2000.  A linear mix across +-$1000 turned one render the long way
; (the heading crosses it at a fixed spot each lap, e.g. the Big Forest
; bridge: one frame with the view and minimap rotated ~120 degrees).
; Deltas beyond +-$3000 (scene changes) stay linear.  All but +$1E are
; re-wrapped into [-$1000,$0FFF]; +$1E naturally runs a little beyond it.
vr60_30_mix_word:
        ifd     VR60_30_DBG_NOLAG
        move.w  #256,d2                         ; test: camera = latest tick
        endif
        cmpi.b  #$30,d0
        beq.s   .ang
        cmpi.b  #$44,d0
        beq.s   .ang
        cmpi.b  #$58,d0
        beq.s   .ang
        cmpi.b  #$0A,d0
        beq.s   .ang
        cmpi.b  #$1C,d0
        beq.s   .ang
        cmpi.b  #$1E,d0
        bne.s   .lin
.ang:
        cmpi.w  #$3000,d1
        bgt.s   .lin
        cmpi.w  #-$3000,d1
        blt.s   .lin
        cmpi.w  #$1000,d1
        blt.s   .lo
        subi.w  #$2000,d1
        bra.s   .mix
.lo:
        cmpi.w  #-$1000,d1
        bge.s   .mix
        addi.w  #$2000,d1
.mix:
        muls.w  d2,d1
        asr.l   #8,d1
        add.w   0(a0,d0.w),d1
        cmpi.b  #$1E,d0
        beq.s   .out
        addi.w  #$1000,d1
        andi.w  #$1FFF,d1
        subi.w  #$1000,d1
.out:
        rts
.lin:
        muls.w  d2,d1
        asr.l   #8,d1
        add.w   0(a0,d0.w),d1
        rts
        endif

        ifd     VR60_30_DEMO
; ============================================================================
; Attract demo at 30 FPS.  The demo scene ($885586) has the race's 0/4/8/C
; layout and camera block, so it reuses the race scheduler: state 0 launches
; the AUTH render, the $40/$48/$50 V-INTs present and launch the 1/3 and 2/3
; renders, and state 8 (below) shifts the camera snapshots.
; ============================================================================
VR60_30_DEMO_SCENE      equ     $00885586

; Z=1 when the current scene is the 1P race or the attract demo.
vr60_30_scene_ok:
        cmpi.l  #VR60_INTERP_1P_RACE_SCENE,($00FF0002).l
        beq.s   .out
        cmpi.l  #VR60_30_DEMO_SCENE,($00FF0002).l
.out:
        rts

; Demo state-8 tail (replaces addq #4 / $54 / rts at $0055F0).
vr60_30_demo_state8:
        movem.l d0-d2/a0-a1,-(sp)
        move.b  #$01,VR60_1P_FLAG               ; scheduler armed (as in a race)
        bclr    #1,(VR60_30_FLAGS).l            ; tick logic rewrote the scene block
        ifd     VR60_30_DEMO_NOCARS
        clr.w   (VR60_30_CAR_LISTN).l           ; test: no car mixing in the demo
        else
        ifd     VR60_30_CARS
        btst    #6,(VR60_30_FLAGS).l
        seq     d0
        jsr     vr60_30_cars_tail
        endif
        endif
        btst    #6,(VR60_30_FLAGS).l
        bne.s   .shift
        lea     $00FF6100,a0                    ; first tick: seed both
        lea     (VR60_INTERP_CURRENT_SNAPSHOT).l,a1
        moveq   #(VR60_INTERP_CAMERA_BYTES/4)-1,d0
.seed:
        move.l  (a0)+,(a1)+
        dbra    d0,.seed
        bset    #6,(VR60_30_FLAGS).l
.shift:
        lea     (VR60_INTERP_NEXT_SNAPSHOT).l,a0
        lea     (VR60_INTERP_CURRENT_SNAPSHOT).l,a1
        moveq   #(VR60_INTERP_CAMERA_BYTES/4)-1,d0
.c2p:
        move.l  (a0)+,(a1)+
        dbra    d0,.c2p
        lea     $00FF6100,a0
        lea     (VR60_INTERP_NEXT_SNAPSHOT).l,a1
        moveq   #(VR60_INTERP_CAMERA_BYTES/4)-1,d0
.l2c:
        move.l  (a0)+,(a1)+
        dbra    d0,.l2c
        ; Replay camera cut: a jump in the view words +$02..+$08 or a heading
        ; turn over $400 (short way).  Mixing two shots would give one render
        ; from nowhere, so the previous snapshot takes the new shot as well.
        lea     (VR60_INTERP_CURRENT_SNAPSHOT).l,a0
        lea     (VR60_INTERP_NEXT_SNAPSHOT).l,a1
        moveq   #3,d2                           ; +$02,+$04,+$06,+$08
        moveq   #2,d1
.cut:
        move.w  0(a1,d1.w),d0
        sub.w   0(a0,d1.w),d0
        bpl.s   .abs
        neg.w   d0
.abs:
        cmpi.w  #$0180,d0
        bhi.s   .is_cut
        addq.w  #2,d1
        dbra    d2,.cut
        move.w  $0A(a1),d0
        sub.w   $0A(a0),d0
        addi.w  #$1000,d0
        andi.w  #$1FFF,d0
        subi.w  #$1000,d0
        bpl.s   .habs
        neg.w   d0
.habs:
        cmpi.w  #$0400,d0
        bls.s   .done
.is_cut:
        moveq   #(VR60_INTERP_CAMERA_BYTES/4)-1,d0
.cp:
        move.l  (a1)+,(a0)+
        dbra    d0,.cp
.done:
        movem.l (sp)+,d0-d2/a0-a1
        addq.w  #4,($FFFFC87E).w
        move.w  #$0050,$00FF0008                ; 30-FPS V-INT after state 8
        rts
        endif
