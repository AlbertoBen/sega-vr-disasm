/*
 * VR60 band split (research prototype, Master side).
 *
 * Entered from stage D at 060011EE instead of the join routine 06004438
 * (literal 0600122C retargeted), i.e. right after the Master published the
 * terminal status 6 record.  R1 = terminal record base.  Returns by tail-
 * jumping to the original join with PR (= 060011F4) untouched.
 *
 * For the still-unstarted ring records K..T-1 the Master:
 *   1. unpublishes them (status 0) so the Slave waits on them;
 *   2. per record, in ring order: copies it, clips it at scanline s,
 *      rewrites the Slave's copy to the top part (rows < s) and republishes
 *      it (status 4), then draws the bottom part itself with a private copy
 *      of the cmd1 rasterizer using CPU stores (the Slave stays the sole
 *      owner of the VDP fill engine).
 * Band ownership keeps painter order within each band.
 *
 * Scratch: 26014B00.. (SDRAM, measured never written in the Big Forest run).
 *   +00 w  split row s          +04 l activations   +08 l records
 *   +0C l  all-bottom (blanked) +10 l straddled     +14 l skipped (few pending)
 *   +40    copy of original record (64 B)
 *   +80    bottom piece (64 B)
 *   +C0    fake rasterizer context (+24 = record pointer)
 */
        .text
        .global mdrv
        .global msolid

        .equ    SCR_S,     0x00
        .equ    SCR_ACT,   0x04
        .equ    SCR_REC,   0x08
        .equ    SCR_BLANK, 0x0C
        .equ    SCR_SPLIT, 0x10
        .equ    SCR_SKIP,  0x14
        .equ    SCR_ORIG,  0x40
        .equ    SCR_BOT,   0x80
        .equ    SCR_CTX,   0xC0
        .equ    MINPEND,   24
        .equ    MARGIN,    3
        .equ    S_INIT,    140
        .equ    S_MIN,     40
        .equ    S_MAX,     200

mdrv:
        sts.l   pr,@-r15
        mov.l   r1,@-r15
        mov.l   r2,@-r15
        mov.l   r3,@-r15
        mov.l   r4,@-r15
        mov.l   r5,@-r15
        mov.l   r6,@-r15
        mov.l   r7,@-r15
        mov.l   r8,@-r15
        mov.l   r9,@-r15
        mov.l   r10,@-r15
        mov.l   r11,@-r15
        mov.l   r12,@-r15
        mov.l   r13,@-r15
        mov.l   r14,@-r15
        stc.l   gbr,@-r15
        sts.l   mach,@-r15
        sts.l   macl,@-r15

        mov.l   L_scr,r14
        /* T index = (R1 >> 6) & 0xFF */
        mov     r1,r9
        shlr2   r9
        shlr2   r9
        shlr2   r9
        extu.b  r9,r9

        /* split row s */
        mov.w   @(SCR_S,r14),r0
        extu.w  r0,r10
        tst     r10,r10
        bf      .have_s
        mov.l   L_sinit,r10
.have_s:

        /* scan back over published (status 4) records */
        mov     r9,r8
        mov     #0,r13
.scan:
        add     #-1,r8
        extu.b  r8,r8
        bsr     recaddr
        mov     r8,r0
        mov.w   @(28,r11),r0
        cmp/eq  #4,r0
        bf      .scan_done
        add     #1,r13
        mov.l   L_maxscan,r0
        cmp/hs  r0,r13
        bf      .scan
.scan_done:
        /* r8 = last non-pending index; F = r8+1; P = r13 */
        mov     #MINPEND,r0
        cmp/hs  r0,r13
        bt      .enough
        mov.l   @(SCR_SKIP,r14),r0
        add     #1,r0
        bra     .exit
        mov.l   r0,@(SCR_SKIP,r14)
.enough:
        add     #-MARGIN,r13            /* N = P - MARGIN */
        mov     r9,r8
        sub     r13,r8                  /* K = T - N */
        extu.b  r8,r8
        mov.l   @(SCR_ACT,r14),r0
        add     #1,r0
        mov.l   r0,@(SCR_ACT,r14)

        /* unpublish K..T-1 */
        mov     r8,r12
        mov     r13,r7
        mov     #0,r2
.unpub:
        bsr     recaddr
        mov     r12,r0
        mov     r2,r0
        mov.w   r0,@(28,r11)
        add     #1,r12
        dt      r7
        bf/s    .unpub
        extu.b  r12,r12

        /* remember K-1 for the one-time painter-order wait before drawing */
        mov     r8,r0
        add     #-1,r0
        extu.b  r0,r0
        mov.w   r0,@(26,r14)            /* SCR+1A */
        mov     #0,r12                  /* Qr: bottom pieces drawn */
        mov     #0,r0
        mov.l   r0,@(40,r14)            /* SCR+28: Qw, bottom pieces queued */
        mov     #0,r13                  /* waited flag */

/* R = r8 prepares (clip + republish) up to 64 records ahead of D = r12,
   which the Master draws.  T = r9 ends both. */
.prep_check:
        cmp/eq  r9,r8
        bt      .draw_step
        mov.l   @(40,r14),r0
        sub     r12,r0
        mov     #64,r1
        cmp/hs  r1,r0
        bt      .draw_step

        bsr     recaddr
        mov     r8,r0
        mov.l   @(SCR_REC,r14),r0
        add     #1,r0
        mov.l   r0,@(SCR_REC,r14)
        /* classify from the ring copy directly (cache-through word reads) */
        mov.w   @r11,r0                 /* x0 */
        cmp/pz  r0
        bf      .prep_pub               /* empty polygon */
        mov.w   @(2,r11),r0
        mov     r0,r6                   /* y0 */
        mov     r11,r1
        mov     #6,r3
.ylast:
        mov.w   @(6,r1),r0
        cmp/pz  r0
        bf      .ylast_done
        dt      r3
        bf/s    .ylast
        add     #4,r1
.ylast_done:
        mov.w   @(2,r1),r0
        mov     r0,r7                   /* ylast */
        mov.w   r0,@(24,r14)            /* SCR+18: polygon bottom row */
        cmp/gt  r10,r7                  /* ylast <= s: all top */
        bf      .prep_pub
        /* needs the Master: copy the record into its slot */
        mov.l   @(40,r14),r0
        bsr     slotaddr
        nop                             /* r2 = slot of queue entry Qw */
        mov.l   r2,@(32,r14)            /* SCR+20: current slot */
        mov     r11,r1
        mov     #16,r3
.copy:
        mov.l   @r1+,r0
        dt      r3
        mov.l   r0,@r2
        bf/s    .copy
        add     #4,r2
        mov     r10,r0
        add     #-1,r0
        cmp/ge  r0,r6                   /* y0 >= s-1: all bottom */
        bf      .straddle
        mov     #-1,r0
        mov.w   r0,@r11                 /* blank the Slave copy */
        mov.l   @(SCR_BLANK,r14),r0
        add     #1,r0
        mov.l   r0,@(SCR_BLANK,r14)
        bra     .prep_draw1
        nop

.straddle:
        mov.l   @(SCR_SPLIT,r14),r0
        add     #1,r0
        mov.l   r0,@(SCR_SPLIT,r14)
        /* top part slot -> Slave record: rows [.., s-1] */
        mov.l   @(32,r14),r4
        mov     r11,r5
        mov.l   L_ymin,r6
        mov     r10,r7
        add     #-1,r7
        mov.w   @(24,r14),r0
        mov     r0,r2
        bsr     clip
        mov     #7,r3
        mov.l   @(32,r14),r4
        add     #32,r4
        mov     r11,r5
        add     #32,r5
        mov.l   L_ymin,r6
        mov     r10,r7
        add     #-1,r7
        mov.w   @(24,r14),r0
        mov     r0,r2
        bsr     clip
        mov     #8,r3
        bsr     republish
        nop
        /* bottom part in place in the slot: rows [s, ..] */
        mov.l   @(32,r14),r4
        mov     r4,r5
        mov.l   L_ymax,r7
        mov     r10,r6
        mov.w   @(24,r14),r0
        mov     r0,r2
        bsr     clip
        mov     #7,r3
        mov.l   @(32,r14),r4
        add     #32,r4
        mov     r4,r5
        mov.l   L_ymax,r7
        mov     r10,r6
        mov.w   @(24,r14),r0
        mov     r0,r2
        bsr     clip
        mov     #8,r3
        bra     .prep_type1
        nop
.prep_draw1:
        bsr     republish
        nop
.prep_type1:
        mov.l   @(40,r14),r0
        add     #1,r0
        bra     .prep_next
        mov.l   r0,@(40,r14)            /* Qw++ */
.prep_pub:
        bsr     republish
        nop
.prep_next:
        add     #1,r8
        bra     .prep_check
        extu.b  r8,r8

.draw_step:
        mov.l   @(40,r14),r0
        cmp/eq  r0,r12                  /* queue empty (only when R == T) */
        bt      .loop_done
        tst     r13,r13
        bf      .waited
        mov.w   @(26,r14),r0
        bsr     recaddr
        nop
.wait_prev:
        mov.w   @(28,r11),r0
        cmp/eq  #8,r0
        bf      .wait_prev
        mov     #1,r13
.waited:
        bsr     slotaddr
        mov     r12,r0
        mov     r2,r5
        mov.l   L_ctx,r0
        mov.l   r5,@(36,r0)
        mov.l   r8,@-r15
        mov.l   r9,@-r15
        mov.l   r10,@-r15
        mov.l   r12,@-r15
        mov.l   r13,@-r15
        mov.l   r14,@-r15
        mov.l   L_vdp,r1
        ldc     r1,gbr
        mov     r0,r14
        mov.l   L_mraster,r0
        jsr     @r0
        nop
        mov.l   @r15+,r14
        mov.l   @r15+,r13
        mov.l   @r15+,r12
        mov.l   @r15+,r10
        mov.l   @r15+,r9
        mov.l   @r15+,r8
.draw_next:
        bra     .prep_check
        add     #1,r12
.loop_done:

        /* adapt s: if the Slave already acknowledged the terminal (AB00)
           the Master was the slower side -> give it fewer rows (s += 4). */
        bsr     recaddr
        mov     r9,r0
        mov.w   @(28,r11),r0
        mov.l   L_ab00,r1
        cmp/eq  r1,r0
        bt      .master_slow
        /* Slave still busy: count its not-yet-started records (status 4) */
        mov     r9,r8
        mov     #0,r13
.cnt:
        add     #-1,r8
        bsr     recaddr
        mov     r8,r0
        mov.w   @(28,r11),r0
        cmp/eq  #4,r0
        bf      .cnt_done
        add     #1,r13
        mov     #64,r0
        cmp/hs  r0,r13
        bf      .cnt
.cnt_done:
        mov     #4,r0
        cmp/hi  r0,r13                  /* more than 4 left -> Master was fast */
        bt      .master_fast
        bra     .store_s
        nop
.master_slow:
        add     #4,r10
        mov.l   L_smax,r0
        cmp/gt  r0,r10
        bf      .store_s
        bra     .store_s
        mov     r0,r10
.master_fast:
        add     #-4,r10
        mov.l   L_smin,r0
        cmp/ge  r0,r10
        bt      .store_s
        mov     r0,r10
.store_s:
        mov     r10,r0
        mov.w   r0,@(SCR_S,r14)

.exit:
        lds.l   @r15+,macl
        lds.l   @r15+,mach
        ldc.l   @r15+,gbr
        mov.l   @r15+,r14
        mov.l   @r15+,r13
        mov.l   @r15+,r12
        mov.l   @r15+,r11
        mov.l   @r15+,r10
        mov.l   @r15+,r9
        mov.l   @r15+,r8
        mov.l   @r15+,r7
        mov.l   @r15+,r6
        mov.l   @r15+,r5
        mov.l   @r15+,r4
        mov.l   @r15+,r3
        mov.l   @r15+,r2
        mov.l   @r15+,r1
        lds.l   @r15+,pr
        mov.l   L_join,r0
        jmp     @r0
        nop

/* r11 = cache-through ring record for index r0 (0..255); clobbers r0 */
recaddr:
        extu.b  r0,r0
        shll2   r0
        shll2   r0
        shll2   r0
        mov.l   L_ring,r11
        rts
        add     r0,r11

/* r2 = bottom-piece slot for index r0 (64 slots of 64 B); clobbers r0 */
slotaddr:
        mov     #63,r2
        and     r2,r0
        shll2   r0
        shll2   r0
        shll2   r0
        mov.l   L_orig,r2
        rts
        add     r0,r2

/* status 4 at r11+1C */
republish:
        mov     #4,r0
        rts
        mov.w   r0,@(28,r11)

/*
 * clip: copy chain r4 -> r5 restricted to rows [r6, r7] (r6 <= r7), with
 * rasterizer-exact interpolation of new vertices, then the FFFF/FFFF
 * terminator.  Leaf; clobbers r0-r7, r1-r3, macl; preserves r8-r14.
 */
clip:
        sts.l   pr,@-r15
        mov.l   r8,@-r15
        mov.l   r9,@-r15
        mov.l   r10,@-r15
        mov.l   r11,@-r15
        mov.l   r12,@-r15
        mov.l   r13,@-r15
        mov.l   r14,@-r15
        mov     r2,r13                  /* polygon bottom row */
        mov     r3,r14                  /* pairs the destination can hold */
        mov.w   @r4+,r8                 /* xa */
        mov.w   @r4+,r9                 /* ya */
        cmp/pz  r8
        bf      .c_term
.c_loop:
        cmp/ge  r13,r9                  /* ya reached the bottom: last vertex */
        bf/s    .c_read
        mov     #-1,r11
        bra     .c_have
        nop
.c_read:
        mov.w   @r4,r10                 /* xb */
        mov.w   @(2,r4),r0
        mov     r0,r11                  /* yb (negative = none) */
.c_have:
        cmp/ge  r6,r9                   /* ya >= ylo ? */
        bt      .c_inband
        /* ya < ylo */
        cmp/pz  r11
        bf      .c_term
        cmp/gt  r6,r11                  /* yb > ylo ? */
        bf      .c_adv
        bsr     interp
        mov     r6,r12                  /* y = ylo */
        mov.w   r0,@r5
        mov     r6,r0
        mov.w   r0,@(2,r5)
        add     #4,r5
        add     #-1,r14
        cmp/gt  r7,r11                  /* yb > yhi -> also emit yhi */
        bf      .c_adv
        bsr     interp
        mov     r7,r12
        mov.w   r0,@r5
        mov     r7,r0
        mov.w   r0,@(2,r5)
        add     #-1,r14
        bra     .c_term
        add     #4,r5
.c_inband:
        cmp/gt  r7,r9                   /* ya > yhi -> done */
        bt      .c_term
        mov.w   r8,@r5
        mov     r9,r0
        mov.w   r0,@(2,r5)
        add     #4,r5
        add     #-1,r14
        cmp/pz  r11
        bf      .c_term
        cmp/gt  r7,r11                  /* yb > yhi ? */
        bf      .c_adv
        cmp/ge  r7,r9                   /* ya >= yhi: nothing more */
        bt      .c_term
        bsr     interp
        mov     r7,r12
        mov.w   r0,@r5
        mov     r7,r0
        mov.w   r0,@(2,r5)
        add     #-1,r14
        bra     .c_term
        add     #4,r5
.c_adv:
        cmp/pl  r14                     /* destination full: stop */
        bf      .c_term
        mov     r10,r8
        mov     r11,r9
        bra     .c_loop
        add     #4,r4
.c_term:
        cmp/pl  r14                     /* room left for the terminator? */
        bf      .c_noterm
        mov     #-1,r0
        mov.w   r0,@r5
        mov.w   r0,@(2,r5)
.c_noterm:
        mov.l   @r15+,r14
        mov.l   @r15+,r13
        mov.l   @r15+,r12
        mov.l   @r15+,r11
        mov.l   @r15+,r10
        mov.l   @r15+,r9
        mov.l   @r15+,r8
        lds.l   @r15+,pr
        rts
        nop

/* x on segment (r8,r9)-(r10,r11) at row r12, as the cmd1 edge stepper
   computes it: ((xa<<16)|0x8000) + (y-ya) * (4*(xa-xb)*coef[ya-yb]).
   Returns r0; clobbers r1-r3, macl. */
interp:
        mov     r9,r2
        sub     r11,r2                  /* ya - yb (<= 0) */
        shll    r2
        mov.l   L_coef,r0
        mov.w   @(r0,r2),r3
        mov     r8,r1
        sub     r10,r1                  /* xa - xb */
        muls.w  r1,r3
        sts     macl,r1
        shll2   r1                      /* slope */
        mov     r12,r2
        sub     r9,r2                   /* y - ya */
        mul.l   r2,r1
        sts     macl,r1
        mov     r8,r0
        shll16  r0
        mov.l   L_half,r3
        or      r3,r0
        add     r1,r0
        swap.w  r0,r0
        rts
        exts.w  r0,r0

/*
 * Master solid span callback (entered by JSR/JMP @R14 from the Master copy
 * of the rasterizer).  Same pixel semantics as C0000188 but CPU word stores
 * instead of the VDP fill.  In: r1 row base, r4 colour, r5 row base,
 * r12/r13 16.16 x.  Clobbers r0-r3 only.
 */
        .align  2
msolid:
        swap.w  r12,r2
        exts.w  r2,r2
        swap.w  r13,r3
        exts.w  r3,r3
        add     r2,r1
        cmp/eq  r2,r3
        bt      .ms_single
        mov     #1,r0
        tst     r0,r2
        bt      .ms_even_l
        mov.b   r4,@r1
        add     #1,r1
        add     #1,r2
.ms_even_l:
        tst     r0,r3
        bf/s    .ms_odd_r
        mov     r3,r0
        mov.b   r4,@(r0,r5)
.ms_odd_r:
        sub     r2,r0
        add     #1,r0
        mov     #2,r2
        cmp/ge  r2,r0
        bf/s    .ms_done
        shlr    r0                      /* r0 = words (>= 1) */
        mov     r0,r2                   /* r2 = words */
        /* align to a longword with one word store */
        mov     r1,r0
        tst     #2,r0
        bt      .ms_long_start
        mov.w   r4,@r1
        add     #2,r1
        dt      r2
        bt      .ms_done
.ms_long_start:
        extu.w  r4,r3
        mov     r3,r0
        shll16  r0
        or      r0,r3                   /* colour in all four bytes */
        mov     r2,r0                   /* r0 = words */
        shlr    r2                      /* longwords */
        tst     r2,r2
        bt      .ms_tail
.ms_long:
        mov.l   r3,@r1
        dt      r2
        bf/s    .ms_long
        add     #4,r1
.ms_tail:
        tst     #1,r0
        bt      .ms_done
        mov.w   r4,@r1
.ms_done:
        rts
        nop
.ms_single:
        rts
        mov.b   r4,@r1

        .align  2
L_scr:     .long   0x26014B00
L_ring:    .long   0x26018000
L_coef:    .long   0x060048D0
L_half:    .long   0x00008000
L_vdp:     .long   0x20004100
L_mraster: .long   0x02306800
L_join:    .long   0x06004438
L_orig:    .long   0x26014C00
L_bot:     .long   0x26014C40
L_ctx:     .long   0x26014B80
L_sinit:   .long   S_INIT
L_maxscan: .long   250
L_ymin:    .long   -32768
L_ymax:    .long   32767
L_ab00:    .long   0xFFFFAB00
L_smax:    .long   S_MAX
L_smin:    .long   S_MIN
