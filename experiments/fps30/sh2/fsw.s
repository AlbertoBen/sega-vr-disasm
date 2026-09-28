/* Render-job start guard (hooked on the first Slave command send, r1 = 8, in
   2304C20): if the frame-buffer swap requested for the previous frame is still
   pending (FS unchanged since the previous job start), wait for it, so the job
   never draws into the buffer that is on screen.  Bounded wait. */
        .text
        .global fsw
fsw:
        mov     #8,r0
        cmp/eq  r0,r1
        bf      .go
        mov.l   L_last,r2
        mov.l   L_vdp,r3
        mov.l   L_lim,r4
.w:     mov.w   @(10,r3),r0
        and     #1,r0
        mov.b   @r2,r5
        cmp/eq  r5,r0
        bf      .ok
        mov.l   L_comm,r6               /* alternate the read address so the  */
        mov.w   @r6,r6                  /* emulator's poll detector does not  */
        dt      r4                      /* put this CPU to sleep on FS        */
        bf      .w
.ok:    mov.w   @(10,r3),r0
        and     #1,r0
        mov.b   r0,@r2
        mov     #8,r1
.go:    mov.l   L_send,r0
        jmp     @r0
        nop
        .align  2
L_last: .long   0x26015E48
L_vdp:  .long   0x20004100
L_lim:  .long   30000
L_send: .long   0x0600441C
L_comm: .long   0x2000402C
