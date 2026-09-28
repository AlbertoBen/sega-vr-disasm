; VR60 30-FPS scheduler: scene-block prefetch (placed at file $01D800).
; Scene-block prefetch (research).  The main loop (RAM at $FF0000) is patched
; to execute TRAP #15 after the scene logic, before it STOPs for the V-INT.
; If the SDRAM scene block is stale (a tick or state 0 rewrote $FF6000) and the
; SH2 side is idle (no job, or the job is finished and only waits to be
; presented), the block is streamed now with Master command $3C (DMA only),
; so the next launch can use the camera-only command.  Only started while at
; least ~40 lines remain before V-Blank, so it never delays a launch.
        dc.b    'VR3P'                          ; locator for the TRAP #15 vector
vr60_30_prefetch_trap:
        tst.b   VR60_1P_FLAG
        beq.w   .rte
        cmpi.l  #VR60_INTERP_1P_RACE_SCENE,($00FF0002).l
        bne.w   .rte
        btst    #6,(VR60_30_FLAGS).l
        beq.w   .rte
        btst    #1,(VR60_30_FLAGS).l
        bne.w   .rte
        movem.l d0/a1-a2,-(sp)
.poll:  move.w  $00C00008,d0                    ; V counter in the high byte
        lsr.w   #8,d0
        cmpi.b  #$E0,d0
        bhs.s   .time_ok                        ; still in V-Blank: a frame ahead
        cmpi.b  #$B8,d0
        bhs.s   .give_up
.time_ok:
        tst.b   COMM0_HI
        bne.s   .poll                           ; Master still busy
        btst    #0,(VR60_30_FLAGS).l
        beq.s   .idle                           ; nothing in flight
        btst    #0,COMM1_LO
        beq.s   .poll                           ; job in flight, not finished
.idle:  bclr    #1,COMM1_LO
        move.w  #VR60_INTERP_SCENE_WORDS,MARS_DREQ_LEN
        move.b  #$04,MARS_DREQ_CTRL+1
        move.b  #$3C,COMM0_LO
        move.b  #$01,COMM0_HI
.ack:   btst    #1,COMM1_LO
        beq.s   .ack
        bclr    #1,COMM1_LO
        jsr     VR60_INTERP_STOCK_FIFO_TAIL     ; 10 x 128 words from $FF6000
        bset    #1,(VR60_30_FLAGS).l
.give_up:
        movem.l (sp)+,d0/a1-a2
.rte:   rte

; Patch the RAM main loop once per race: STOP -> TRAP #15; STOP.
vr60_30_install_prefetch:
        cmpi.l  #$4E722300,($00FF000C).l
        bne.s   .done
        cmpi.l  #$4A78C87A,($00FF0010).l
        bne.s   .done
        move.w  #$60E6,($00FF0018).l
        move.l  #$C87A66F6,($00FF0014).l
        move.l  #$23004A78,($00FF0010).l
        move.l  #$4E4F4E72,($00FF000C).l
.done:  rts
