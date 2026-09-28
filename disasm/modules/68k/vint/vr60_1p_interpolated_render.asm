; ============================================================================
; VR60 experimental 1P interpolated-render scheduler (measured ~20 FPS)
; ============================================================================
;
; This is an isolated display-cadence experiment.  The normal 1P state
; machine still executes state 0, state 4, and state 8 on separate main-loop
; iterations, so physics, input, audio, timers, replay, and AI remain at the
; stock ~20-Hz game cadence.
;
; Display sequence for a successful cycle:
;   state 0: submit the authoritative "current" camera to cmd $02
;   state 4 V-INT ($48): commit it only when COMM1_LO bit 0 says done
;   state 8: run normal game logic and prepare the current/current+1 midpoint
;   state 8 V-INT ($50): commit the authoritative render, immediately submit
;                        the prepared midpoint, then restore current+1
;
; Render completion and game cadence are deliberately independent.  State
; 0/4/8 always advances once per VBlank; an unfinished extra render can make
; the following authoritative visual submit be skipped, but it can never
; stall physics, input, AI or timers.  No stale framebuffer is presented.
;
; RAM contract (all within the audited slack before VR60_1P_FLAG $FF7B40):
;   $FF7A4E-$FF7AC5  current camera snapshot (120 bytes)
;   $FF7AC6-$FF7B3D  next camera snapshot    (120 bytes)
;   $FF7B3E-$FF7B3F  render FSM (idle/auth-credit/auth-pending/extra-pending)
; $FF7A40-$FF7A4D belongs to the optional FPS overlay.  In particular,
; $FF7A4C is its monotonic total-commit counter.
;
; The copied camera object is six 20-byte descriptor records ($78 bytes).
; Only documented continuous camera fields are interpolated.  Control words,
; visible-object counts, and descriptor metadata are kept from current+1 so
; they can never become invalid averaged commands or pointers.
; ============================================================================

VR60_INTERP_CAMERA_BYTES       equ     $0078
VR60_INTERP_CAMERA_WORDS       equ     VR60_INTERP_CAMERA_BYTES/2
VR60_INTERP_SCENE_WORDS        equ     $0500
VR60_INTERP_CURRENT_SNAPSHOT   equ     $00FF7A4E
VR60_INTERP_NEXT_SNAPSHOT      equ     $00FF7AC6
VR60_INTERP_RENDER_STATE       equ     $00FF7B3E
VR60_INTERP_IDLE               equ     0
VR60_INTERP_AUTH_CREDIT        equ     1
VR60_INTERP_AUTH_PENDING       equ     2
VR60_INTERP_EXTRA_PENDING      equ     3

VR60_INTERP_STOCK_VINT_10      equ     $00881A6E
VR60_INTERP_UNIFIED_VINT       equ     $0089C392
VR60_INTERP_STATE8_TAIL        equ     $00884D6A
VR60_INTERP_MARS_DMA           equ     $008828C2
VR60_INTERP_STOCK_FIFO_TAIL    equ     $008828F4
VR60_INTERP_1P_RACE_SCENE      equ     $00884CBC

        ifd     VR60_EXPERIMENTAL_30FPS_SCHED
; ============================================================================
; 30-FPS presentation scheduler (research).  Game logic keeps the stock
; 0/4/8 20-Hz cycle.  A render is launched whenever the lane is idle at one of
; three points, each with a fixed display time tau = (VBlank index)/3 - 1 tick,
; i.e. a one-tick camera lag with exact 1/3-tick spacing:
;   state 0 (AUTH, stock cmd $02 + audio): camera = previous tick
;   V-INT after state 0 (cmd $3F):          camera = prev + 1/3 (cur - prev)
;   V-INT after state 4 (cmd $3F):          camera = prev + 2/3 (cur - prev)
; Completed frames are presented at the next V-INT.  At most one job is in
; flight and launches are at least two VBlanks apart.  Scene data other than
; the continuous camera fields is always the latest tick.
; RAM: $FF7A4E prev camera, $FF7AC6 current camera (120 bytes each),
;      $FF7B3E pending/seed flags, $FF7B3F VBlanks since last launch.
; ============================================================================
VR60_30_FLAGS                  equ     $00FF7B3E       ; bit0 pending, bit6 seeded
VR60_30_VBC                    equ     $00FF7B3F

; Present a completed job (if any) during this V-INT and count the VBlank.
vr60_30_vint_common:
        cmpi.b  #$7F,(VR60_30_VBC).l
        bhs.s   .count_done
        addq.b  #1,(VR60_30_VBC).l
.count_done:
        ifd     VR60_30_PRESENT_WAIT
        ; A job that is due (launched >= 2 VBlanks ago) but not finished yet
        ; usually finishes within the first part of this VBlank: wait a
        ; bounded time for it instead of losing a whole frame.
        btst    #0,(VR60_30_FLAGS).l
        beq.s   .nowait
        cmpi.b  #2,(VR60_30_VBC).l
        blo.s   .nowait
        move.w  #VR60_30_PRESENT_WAIT,-(sp)
.pw:    btst    #0,COMM1_LO
        bne.s   .pw_done
        bsr.w   vr60_30_vblank_margin           ; only while V-Blank has margin
        beq.s   .pw_done
        subq.w  #1,(sp)
        bne.s   .pw
.pw_done:
        addq.l  #2,sp
.nowait:
        endif
        btst    #0,COMM1_LO
        beq.s   .none
        ifd     VR60_30_VBLANK_GUARD
        bsr.w   vr60_30_vblank_margin           ; Z=1: too close to the end of
        beq.s   .none                           ; V-Blank, present next V-INT
        endif
        bclr    #0,COMM1_LO
        bclr    #7,MARS_SYS_INTCTL
.wait_fm:
        btst    #7,MARS_VDP_FBCTL
        beq.s   .wait_fm
        ifd     VR60_FPS_COUNTER
        jsr     $00880000+vr60_fps_record_overlay
        endif
        bchg    #0,($FFFFC80C).w
        bne.s   .buf1
        bset    #0,MARS_VDP_FBCTL+1
        bra.s   .rel
.buf1:
        bclr    #0,MARS_VDP_FBCTL+1
.rel:
        bset    #7,MARS_SYS_INTCTL
        bclr    #0,(VR60_30_FLAGS).l
.none:
        rts

        ifd     VR60_30_VBLANK_GUARD
; Z=0 while the MD V counter is inside V-Blank (V >= $E0; NTSC V-Blank runs
; $E0-$EA, $E5-$FF).  An FS write issued outside V-Blank would only take effect
; at the next one, so the frame is then presented at the next V-INT instead.
; (A tighter end-of-V-Blank margin was tried: it can starve presentation when
; a handler always runs late in V-Blank, so it is not used.)
vr60_30_vblank_margin:
        move.w  d0,-(sp)
        move.w  $00C00008,d0
        lsr.w   #8,d0
        cmpi.b  #$E0,d0
        blo.s   .no
        move.w  (sp)+,d0
        andi.b  #$FB,ccr                        ; Z=0: ok
        rts
.no:    move.w  (sp)+,d0
        ori.b   #$04,ccr                        ; Z=1: too late
        rts
        endif

vr60_30_launch_auth:                            ; state 0: no spacing/terminal test
        movem.l d0-d4/a0-a4,-(sp)
        moveq   #0,d2
        moveq   #3,d4
        bra.s   vr60_30_launch
vr60_30_launch_auth_vint:                       ; V-INT after state 8
        movem.l d0-d4/a0-a4,-(sp)
        moveq   #0,d2
        moveq   #1,d4
        bra.s   vr60_30_launch
vr60_30_launch_third:
        movem.l d0-d4/a0-a4,-(sp)
        moveq   #85,d2
        moveq   #0,d4
        bra.s   vr60_30_launch
vr60_30_launch_two_thirds:
        movem.l d0-d4/a0-a4,-(sp)
        move.w  #171,d2
        moveq   #0,d4
vr60_30_launch:
        tst.b   VR60_1P_FLAG
        beq.w   .out
        btst    #6,(VR60_30_FLAGS).l
        beq.w   .out
        tst.b   COMM0_HI
        bne.w   .out
        btst    #0,COMM1_LO
        bne.w   .out
        ifd     VR60_30_VBLANK_GUARD
        btst    #0,(VR60_30_FLAGS).l            ; previous frame not presented yet
        bne.w   .out
        endif
        btst    #1,d4                           ; state-0 AUTH ignores spacing/terminal
        bne.s   .spaced
        cmpi.w  #$0030,($FFFFC07C).w
        bhs.w   .out
        cmpi.b  #2,(VR60_30_VBC).l
        blo.w   .out
.spaced:
        ; camera fields := prev + (cur - prev) * d2 / 256, saving the live ones
        lea     -32(sp),sp
        movea.l sp,a4
        lea     vr60_interp_continuous_offsets(pc),a2
        lea     $00FF6100,a3
        lea     (VR60_INTERP_CURRENT_SNAPSHOT).l,a0
        lea     (VR60_INTERP_NEXT_SNAPSHOT).l,a1
        moveq   #VR60_INTERP_CONTINUOUS_COUNT-1,d3
.mix:
        moveq   #0,d0
        move.b  (a2)+,d0
        move.w  0(a3,d0.w),(a4)+
        move.w  0(a1,d0.w),d1
        sub.w   0(a0,d0.w),d1
        ifd     VR60_30_ANGLE_WRAP
        ; +$30/+$44/+$58 are angles kept in [-$1000,$0FFF] (period $2000):
        ; take the short way round and re-wrap the result, otherwise a tick
        ; that crosses +-$1000 gives one render rotated the long way.
        ifd     VR60_30_HOLD_SHAKE
        ; +$08/+$0C/+$1C/+$20 carry the per-tick body shake/roll jitter:
        ; hold the tick value (like the stock 20-Hz game) instead of
        ; resampling the jitter at 1/3 and 2/3.
        cmpi.b  #$08,d0
        beq.s   .hold
        cmpi.b  #$0C,d0
        beq.s   .hold
        cmpi.b  #$1C,d0
        beq.s   .hold
        cmpi.b  #$20,d0
        bne.s   .nohold
.hold:
        move.w  0(a0,d0.w),d1
        bra.s   .store
.nohold:
        endif
        ifd     VR60_30_HEADING_WRAP
        jsr     vr60_30_mix_word                ; angles + heading (cars module)
        bra.s   .store
        else
        cmpi.b  #$30,d0
        beq.s   .wrap
        cmpi.b  #$44,d0
        beq.s   .wrap
        cmpi.b  #$58,d0
        bne.s   .lin
.wrap:
        addi.w  #$1000,d1
        andi.w  #$1FFF,d1
        subi.w  #$1000,d1
        muls.w  d2,d1
        asr.l   #8,d1
        add.w   0(a0,d0.w),d1
        addi.w  #$1000,d1
        andi.w  #$1FFF,d1
        subi.w  #$1000,d1
        bra.s   .store
.lin:
        endif
        endif
        muls.w  d2,d1
        asr.l   #8,d1
        add.w   0(a0,d0.w),d1
.store:
        move.w  d1,0(a3,d0.w)
        dbra    d3,.mix
        ifd     VR60_30_CARS
        jsr     vr60_30_cars_mix
        endif
        bset    #0,(VR60_30_FLAGS).l
        clr.b   (VR60_30_VBC).l
        ifd     VR60_30_AUTH3F
        cmpi.b  #3,d4                           ; only the state-0 AUTH stays stock $02
        bne.s   .extra
        else
        btst    #0,d4
        beq.s   .extra
        endif
        jsr     VR60_INTERP_MARS_DMA
        bra.s   .sent
.extra:
        ifd     VR60_30_DEMO
        ; The attract demo renders with its own scene command ($05: viewport
        ; window + ranking panel list), which the $3F/$3D clones of cmd $02
        ; do not reproduce: send every demo render through the stock path.
        cmpi.l  #VR60_30_DEMO_SCENE,($00FF0002).l
        bne.s   .notdemo
        jsr     VR60_INTERP_MARS_DMA
        bra.s   .sent
.notdemo:
        endif
        ifd     VR60_30_CAMONLY
        btst    #1,(VR60_30_FLAGS).l            ; SDRAM scene block current?
        beq.s   .full_extra
        bsr.w   vr60_30_camera_submit           ; send only the camera block
        bra.s   .restore
.full_extra:
        endif
        jsr     vr60_interp_camera_render_submit
.sent:
        bset    #1,(VR60_30_FLAGS).l            ; full block sent after the last tick
.restore:
        movea.l sp,a4
        lea     vr60_interp_continuous_offsets(pc),a2
        moveq   #VR60_INTERP_CONTINUOUS_COUNT-1,d3
.back:
        moveq   #0,d0
        move.b  (a2)+,d0
        move.w  (a4)+,0(a3,d0.w)
        dbra    d3,.back
        lea     32(sp),sp
        ifd     VR60_30_CARS
        jsr     vr60_30_cars_restore
        endif
.out:
        movem.l (sp)+,d0-d4/a0-a4
        rts

        ifd     VR60_30_CARS
VR60_30_CAMONLY_WORDS          equ     148     ; camera + 17 x 5 car words + 3 pad
        else
VR60_30_CAMONLY_WORDS          equ     VR60_INTERP_CAMERA_WORDS
        endif

        ifd     VR60_30_CAMONLY
; Camera-only EXTRA (Master cmd $3D): the scene block in SDRAM is unchanged
; since the last full transfer (no state 8 ran since), so only the 120-byte
; camera block $FF6100 is streamed; the SH2 stub DMAs it to 0600C100.
vr60_30_camera_submit:
        move.w  ($00FF674C).l,$00A15128         ; COMM4: state-0 speed scale
        bclr    #1,COMM1_LO
        move.w  #VR60_30_CAMONLY_WORDS,MARS_DREQ_LEN
        move.b  #$04,MARS_DREQ_CTRL+1
        move.b  #$3D,COMM0_LO
        move.b  #$01,COMM0_HI
.wait_ack:
        btst    #1,COMM1_LO
        beq.s   .wait_ack
        bclr    #1,COMM1_LO
        lea     $00FF6100,a1
        lea     MARS_FIFO,a2
        ifd     VR60_30_CARS
        moveq   #VR60_INTERP_CAMERA_WORDS-1,d0
.copy:
        move.w  (a1)+,(a2)
        dbra    d0,.copy
        jmp     vr60_30_cars_fifo               ; packed car words + pad
        else
        move.w  #VR60_30_CAMONLY_WORDS-1,d0
.copy:
        move.w  (a1)+,(a2)
        dbra    d0,.copy
        rts
        endif
        endif

; V-INT after state 0: present, then launch at 1/3.
vr60_interp_vint_after_state0:
        ifd     VR60_30_DEMO
        jsr     vr60_30_scene_ok                ; race or attract demo
        else
        cmpi.l  #VR60_INTERP_1P_RACE_SCENE,($00FF0002).l
        endif
        bne.w   vr60_interp_vint_outside_race
        cmpi.w  #$0030,($FFFFC07C).w
        bhs.s   .stock
        bsr.w   vr60_30_vint_common
        bsr.w   vr60_30_launch_third
.stock:
        jmp     VR60_INTERP_STOCK_VINT_10

; V-INT after state 4: present, then launch at 2/3.
vr60_interp_vint_commit_current:
        ifd     VR60_30_DEMO
        jsr     vr60_30_scene_ok                ; race or attract demo
        else
        cmpi.l  #VR60_INTERP_1P_RACE_SCENE,($00FF0002).l
        endif
        bne.w   vr60_interp_vint_outside_race
        cmpi.w  #$0030,($FFFFC07C).w
        bhs.s   .exit
        bsr.w   vr60_30_vint_common
        bsr.w   vr60_30_launch_two_thirds
.exit:
        rts

; V-INT after state 8: present, then the stock unified work (no launch: the
; lane is left to the next state-0 AUTH, which also carries the audio feed).
vr60_interp_vint_after_state8:
        ifd     VR60_30_DEMO
        jsr     vr60_30_scene_ok                ; race or attract demo
        else
        cmpi.l  #VR60_INTERP_1P_RACE_SCENE,($00FF0002).l
        endif
        bne.w   vr60_interp_vint_outside_race
        bsr.w   vr60_30_vint_common
        ifd     VR60_30_EARLY_AUTH
        bsr.w   vr60_30_launch_auth_vint        ; launch first, like the $40/$48 slots
        clr.w   ($FFFFC87E).w
        jsr     VR60_INTERP_UNIFIED_VINT
        else
        clr.w   ($FFFFC87E).w
        jsr     VR60_INTERP_UNIFIED_VINT
        bsr.w   vr60_30_launch_auth_vint        ; AUTH at the V-INT: full 2-VB slot
        endif
        rts

; State 0: authoritative submit with the previous tick's camera.  Preserves A0.
vr60_interp_state0_submit:
        ifd     VR60_30_PREFETCH
        bclr    #1,(VR60_30_FLAGS).l            ; state 0 writes $FF674C
        endif
        bra.w   vr60_30_launch_auth

; State-8 tail: advance the camera history after the tick's logic.
vr60_interp_state8_submit:
        tst.b   VR60_1P_FLAG
        beq.s   .tail
        movem.l d0/a0-a1,-(sp)
        bclr    #1,(VR60_30_FLAGS).l            ; tick logic rewrote the scene block
        ifd     VR60_30_PREFETCH
        bsr.w   vr60_30_install_prefetch
        endif
        ifd     VR60_30_CARS
        btst    #6,(VR60_30_FLAGS).l
        seq     d0                              ; first tick of a race: seed
        jsr     vr60_30_cars_tail
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
        movem.l (sp)+,d0/a0-a1
.tail:
        jmp     VR60_INTERP_STATE8_TAIL

        else
; ----------------------------------------------------------------------------
; Observe (but do not consume) a completed SH2 job and advance the render FSM.
; COMM1 remains owned by the presentation handler: V-INT $48 or the stock
; unified handler consumes it only when it actually swaps the framebuffer.
; Uses no data/address register and preserves the caller's CCR after return is
; irrelevant: every caller immediately executes its own flag-setting test.
; ----------------------------------------------------------------------------
vr60_interp_poll_completion:
        btst    #0,COMM1_LO
        beq.s   .return

        cmpi.w  #VR60_INTERP_AUTH_PENDING,(VR60_INTERP_RENDER_STATE).l
        bne.s   .check_extra
        tst.b   VR60_1P_FLAG
        beq.s   .auth_without_credit
        move.w  #VR60_INTERP_AUTH_CREDIT,(VR60_INTERP_RENDER_STATE).l
        rts
.auth_without_credit:
        clr.w   (VR60_INTERP_RENDER_STATE).l
        rts

.check_extra:
        cmpi.w  #VR60_INTERP_EXTRA_PENDING,(VR60_INTERP_RENDER_STATE).l
        bne.s   .return
        clr.w   (VR60_INTERP_RENDER_STATE).l
.return:
        rts

; ----------------------------------------------------------------------------
; Private V-INT $40, selected after state 0.  It intentionally performs the
; exact stock $10 work and cannot commit a framebuffer.
; ----------------------------------------------------------------------------
vr60_interp_vint_after_state0:
        cmpi.l  #VR60_INTERP_1P_RACE_SCENE,($00FF0002).l
        bne.w   vr60_interp_vint_outside_race
        ifd     VR60_EXPERIMENTAL_60FPS_VISUAL_PIPELINE
        ; An extra render launched by state-8 has had a complete TV frame to
        ; finish here.  Present it immediately, then use the now-free COMM/FIFO
        ; lane to launch the already restored authoritative scene.  This keeps
        ; gameplay at the stock 20-Hz state cadence while eliminating the idle
        ; render slot between state 0 and state 4.  Every submit remains
        ; fail-closed on the ordinary completion and hardware ownership bits.
        cmpi.w  #$0030,($FFFFC07C).w
        bhs.s   .stock_vint_10
        cmpi.w  #VR60_INTERP_EXTRA_PENDING,(VR60_INTERP_RENDER_STATE).l
        bne.s   .stock_vint_10
        bsr.w   vr60_interp_vint_commit_current
        tst.w   (VR60_INTERP_RENDER_STATE).l
        bne.s   .stock_vint_10
        tst.b   COMM0_HI
        bne.s   .stock_vint_10
        btst    #0,COMM1_LO
        bne.s   .stock_vint_10
        move.w  #VR60_INTERP_AUTH_PENDING,(VR60_INTERP_RENDER_STATE).l
        jsr     vr60_interp_camera_render_submit
.stock_vint_10:
        jmp     VR60_INTERP_STOCK_VINT_10
        else
        bsr.w   vr60_interp_poll_completion
        jmp     VR60_INTERP_STOCK_VINT_10
        endif

; ----------------------------------------------------------------------------
; Private V-INT $48, selected after state 4.  This is the only new current-
; frame presentation point.  It consumes COMM1 done, obtains FM using the
; stock state-$54 sequence, toggles FS during VBlank, and deliberately does
; not reset $C87E.  FIRST_COMMIT_OK is set only after the toggle completes.
; ----------------------------------------------------------------------------
vr60_interp_vint_commit_current:
        cmpi.l  #VR60_INTERP_1P_RACE_SCENE,($00FF0002).l
        bne.w   vr60_interp_vint_outside_race
        ; Once the terminal state reaches $30, state 8 still has one required
        ; lifecycle pass.  Let its $50 route consume the final completion;
        ; presenting it here lets the scene change one substate too early and
        ; strands the results transition before that cleanup can run.
        cmpi.w  #$0030,($FFFFC07C).w
        bhs.s   .exit
        ; The lifecycle fixture enters at state 4 and this word was formerly
        ; uninitialised slack.  Before the one-time 1P seed, force a known FSM
        ; state even if no render completion is present yet.
        tst.b   VR60_1P_FLAG
        bne.s   .state_initialized
        clr.w   (VR60_INTERP_RENDER_STATE).l
.state_initialized:
        btst    #0,COMM1_LO
        beq.s   .exit                           ; renderer missed deadline

        bsr.w   vr60_interp_poll_completion
        bclr    #0,COMM1_LO                     ; consume this completion once
        bclr    #7,MARS_SYS_INTCTL              ; stock FM acquisition sequence
.wait_fm:
        btst    #7,MARS_VDP_FBCTL
        beq.s   .wait_fm

        ifd     VR60_FPS_COUNTER
        jsr     $00880000+vr60_fps_record_overlay
        endif
        bchg    #0,($FFFFC80C).w
        bne.s   .select_buffer_1
        bset    #0,MARS_VDP_FBCTL+1
        bra.s   .release_fm
.select_buffer_1:
        bclr    #0,MARS_VDP_FBCTL+1
.release_fm:
        bset    #7,MARS_SYS_INTCTL

.exit:
        rts

; ----------------------------------------------------------------------------
; Private state-8 V-INT ($50).  It never lets renderer latency hold the game
; in stock fallback state $0C.  Completion remains fail-closed: the unified
; handler below swaps only when COMM1 says a full framebuffer is ready.
; ----------------------------------------------------------------------------
vr60_interp_vint_after_state8:
        ; The selector written by the final race state-8 survives into the
        ; first results VBlank.  Do not let this race-private route reset the
        ; new scene's shared $C87E dispatcher state.  Keep the unified VDP/
        ; sprite work for this inherited selector; the next scene publishes
        ; its own selector once its transition has advanced.
        cmpi.l  #VR60_INTERP_1P_RACE_SCENE,($00FF0002).l
        bne.w   vr60_interp_vint_outside_race
        bsr.w   vr60_interp_poll_completion
        clr.w   ($FFFFC87E).w
        jsr     VR60_INTERP_UNIFIED_VINT

        ; No midpoint is useful once the terminal lifecycle state is active.
        ; More importantly, results must inherit an idle renderer/COMM lane.
        cmpi.w  #$0030,($FFFFC07C).w
        bhs.s   .drop_credit

        ; State 8 prepared the midpoint before this interrupt.  Completion
        ; may have arrived during the same TV frame, so launch the extra only
        ; after the unified handler has consumed COMM1 and swapped AUTH.
        cmpi.w  #VR60_INTERP_AUTH_CREDIT,(VR60_INTERP_RENDER_STATE).l
        beq.s   .submit_extra
        cmpi.w  #VR60_INTERP_AUTH_PENDING,(VR60_INTERP_RENDER_STATE).l
        beq.s   .restore_prepared               ; deadline missed, no submit
        rts

.submit_extra:
        tst.b   COMM0_HI
        bne.s   .drop_credit
        btst    #0,COMM1_LO
        bne.s   .drop_credit
        move.w  #VR60_INTERP_EXTRA_PENDING,(VR60_INTERP_RENDER_STATE).l
        jsr     vr60_interp_camera_render_submit
        bra.s   .restore_prepared
.drop_credit:
        clr.w   (VR60_INTERP_RENDER_STATE).l

.restore_prepared:
        lea     (VR60_INTERP_NEXT_SNAPSHOT).l,a0
        lea     $00FF6100,a1
        moveq   #(VR60_INTERP_CAMERA_BYTES/4)-1,d0
.restore_next:
        move.l  (a0)+,(a1)+
        dbra    d0,.restore_next
        rts

; ----------------------------------------------------------------------------
; State-0 wrapper body.  camera_snapshot_wrapper in code_2200 tail-jumps here
; so its original PC-relative call site remains four bytes.  Preserve A0,
; which the original mars_dma_xfer_vdp_fill does not document as clobbered.
; ----------------------------------------------------------------------------
vr60_interp_state0_submit:
        ; A credit that survived until the next state-0 is too late for a
        ; midpoint.  Drop it and prioritize the new authoritative scene.
        cmpi.w  #VR60_INTERP_AUTH_CREDIT,(VR60_INTERP_RENDER_STATE).l
        bne.s   .check_renderer
        clr.w   (VR60_INTERP_RENDER_STATE).l

.check_renderer:
        cmpi.w  #VR60_INTERP_AUTH_PENDING,(VR60_INTERP_RENDER_STATE).l
        beq.s   .validate_pending
        cmpi.w  #VR60_INTERP_EXTRA_PENDING,(VR60_INTERP_RENDER_STATE).l
        bne.s   .check_hardware
.validate_pending:
        ; A live job owns COMM0, while a completed job publishes COMM1.done
        ; before going idle.  Neither bit with a pending FSM is an orphaned
        ; command; recover instead of suppressing AUTH forever.
        tst.b   COMM0_HI
        bne.s   .skip_submit
        btst    #0,COMM1_LO
        bne.s   .skip_submit
        clr.w   (VR60_INTERP_RENDER_STATE).l

.check_hardware:
        tst.b   COMM0_HI
        bne.s   .skip_submit
        btst    #0,COMM1_LO
        bne.s   .skip_submit

        move.w  #VR60_INTERP_AUTH_PENDING,(VR60_INTERP_RENDER_STATE).l
        move.l  a0,-(sp)
        lea     $00FF6100,a0
        lea     (VR60_INTERP_CURRENT_SNAPSHOT).l,a1
        moveq   #(VR60_INTERP_CAMERA_BYTES/4)-1,d0
.snapshot_current:
        move.l  (a0)+,(a1)+
        dbra    d0,.snapshot_current
        jsr     VR60_INTERP_MARS_DMA
        movea.l (sp)+,a0
.skip_submit:
        rts

; ----------------------------------------------------------------------------
; State-8 tail.  Entered by JMP after the two original calls in the existing
; 1P staging hook.  Prepare the midpoint while the authoritative renderer is
; pending (or already credited).  Submission happens in V-INT only after AUTH
; is safely presented.  All registers are restored before the stock tail.
; ----------------------------------------------------------------------------
vr60_interp_state8_submit:
        tst.b   VR60_1P_FLAG
        beq.w   .stock_tail
        cmpi.w  #VR60_INTERP_AUTH_CREDIT,(VR60_INTERP_RENDER_STATE).l
        beq.s   .prepare_midpoint
        cmpi.w  #VR60_INTERP_AUTH_PENDING,(VR60_INTERP_RENDER_STATE).l
        bne.w   .stock_tail

.prepare_midpoint:
        movem.l d0-d7/a0-a6,-(sp)

        ; Preserve the complete current+1 camera descriptor before replacing
        ; its documented continuous fields with midpoint values.
        lea     $00FF6100,a0
        lea     (VR60_INTERP_NEXT_SNAPSHOT).l,a1
        moveq   #(VR60_INTERP_CAMERA_BYTES/4)-1,d0
.snapshot_next:
        move.l  (a0)+,(a1)+
        dbra    d0,.snapshot_next

        ; midpoint = current + signed16((next-current)/2).  Subtraction before
        ; ASR also gives shortest-path behavior across 16-bit angle wrapping.
        lea     (VR60_INTERP_CURRENT_SNAPSHOT).l,a0
        lea     (VR60_INTERP_NEXT_SNAPSHOT).l,a1
        lea     vr60_interp_continuous_offsets(pc),a2
        lea     $00FF6100,a3
        moveq   #VR60_INTERP_CONTINUOUS_COUNT-1,d2
.interpolate:
        moveq   #0,d0
        move.b  (a2)+,d0
        move.w  0(a1,d0.w),d1
        sub.w   0(a0,d0.w),d1
        asr.w   #1,d1
        add.w   0(a0,d0.w),d1
        move.w  d1,0(a3,d0.w)
        dbra    d2,.interpolate

        movem.l (sp)+,d0-d7/a0-a6
.stock_tail:
        jmp     VR60_INTERP_STATE8_TAIL


        endif   ; VR60_EXPERIMENTAL_30FPS_SCHED

; ----------------------------------------------------------------------------
; Submit the complete stock $A00-byte scene block to the experimental Master
; cmd $3F.  Only its camera fields differ, but the renderer mutates working
; data elsewhere in this block, so a camera-only refresh is not safe for a
; second pass.  The private handler receives it at $0600C000 and follows the
; paired stock cmd-$02 render path without a duplicate PWM/audio fill.
; The caller already preserves every register, so this leaf may use D0/A1/A2.
; ----------------------------------------------------------------------------
vr60_interp_camera_render_submit:
        tst.b   COMM0_HI
        bne.s   .submit_failed
        btst    #0,COMM1_LO
        bne.s   .submit_failed
.master_idle:
        bclr    #1,COMM1_LO
        move.w  #VR60_INTERP_SCENE_WORDS,MARS_DREQ_LEN
        move.b  #$04,MARS_DREQ_CTRL+1
        move.b  #$3F,COMM0_LO
        move.b  #$01,COMM0_HI
.wait_ack:
        btst    #1,COMM1_LO
        beq.s   .wait_ack
        bclr    #1,COMM1_LO
        ; Exact stock $500-word tail: loads A1/A2 and executes ten unrolled
        ; 128-word blocks.  Its final RTS returns to this helper's caller.
        jmp     VR60_INTERP_STOCK_FIFO_TAIL

.submit_failed:
        clr.w   (VR60_INTERP_RENDER_STATE).l
        rts

; camera_param_calc's documented continuous outputs:
;   primary position/view       +$04,+$06,+$08,+$0A,+$0C
;   speed/derivatives           +$16,+$18,+$1A,+$1C,+$1E,+$20
;   repeated rotation fields    +$30,+$32,+$44,+$46,+$58
VR60_INTERP_CONTINUOUS_COUNT    equ     16
vr60_interp_continuous_offsets:
        dc.b    $04,$06,$08,$0A,$0C
        dc.b    $16,$18,$1A,$1C,$1E,$20
        dc.b    $30,$32,$44,$46,$58
        even

; A race-private selector may be the last value published when the scene
; changes.  Keep its inherited VBlank useful without touching the new scene's
; shared dispatcher state; the new scene will replace the selector itself.
vr60_interp_vint_outside_race:
        clr.w   (VR60_INTERP_RENDER_STATE).l
        jmp     VR60_INTERP_UNIFIED_VINT
