; ============================================================================
; Exception Vector Trampolines ($000200-$0003BE)
;
; 63 JMP abs.l entries ($4EF9 + 32-bit address) that redirect exception
; vectors to their actual handlers in the main code region ($0088xxxx).
; Most point to $00880832 (generic exception handler); notable exceptions:
;   $0002A2 → $0088170A (Level 4 H-INT handler)
;   $0002AE → $00881684 (Level 6 V-INT handler)
;
; Followed by 35 NOPs ($4E71) padding $00037A-$0003BE.
; ============================================================================

exception_vector_trampolines:
        jmp     $00880838.l      ; $000200
        jmp     $00880832.l      ; $000206
        jmp     $00880832.l      ; $00020C
        jmp     $00880832.l      ; $000212
        jmp     $00880832.l      ; $000218
        jmp     $00880832.l      ; $00021E
        jmp     $00880832.l      ; $000224
        jmp     $00880832.l      ; $00022A
        jmp     $00880832.l      ; $000230
        jmp     $00880832.l      ; $000236
        jmp     $00880832.l      ; $00023C
        jmp     $00880832.l      ; $000242
        jmp     $00880832.l      ; $000248
        jmp     $00880832.l      ; $00024E
        jmp     $00880832.l      ; $000254
        jmp     $00880832.l      ; $00025A
        jmp     $00880832.l      ; $000260
        jmp     $00880832.l      ; $000266
        jmp     $00880832.l      ; $00026C
        jmp     $00880832.l      ; $000272
        jmp     $00880832.l      ; $000278
        jmp     $00880832.l      ; $00027E
        jmp     $00880832.l      ; $000284
        jmp     $00880832.l      ; $00028A
        jmp     $00880832.l      ; $000290
        jmp     $00880832.l      ; $000296
        jmp     $00880832.l      ; $00029C
        jmp     $0088170A.l      ; $0002A2 - Level 4 H-INT handler
        jmp     $00880832.l      ; $0002A8
        ifd     VR60_FPS_COUNTER
        jmp     $00880000+vr60_fps_vint_wrapper ; $0002AE - every VBlank
        else
        jmp     $00881684.l      ; $0002AE - 32X V-INT trampoline
        endif
        jmp     $00880832.l      ; $0002B4
        jmp     $00880832.l      ; $0002BA
        jmp     $00880832.l      ; $0002C0
        jmp     $00880832.l      ; $0002C6
        jmp     $00880832.l      ; $0002CC
        jmp     $00880832.l      ; $0002D2
        jmp     $00880832.l      ; $0002D8
        jmp     $00880832.l      ; $0002DE
        jmp     $00880832.l      ; $0002E4
        jmp     $00880832.l      ; $0002EA
        jmp     $00880832.l      ; $0002F0
        jmp     $00880832.l      ; $0002F6
        jmp     $00880832.l      ; $0002FC
        jmp     $00880832.l      ; $000302
        jmp     $00880832.l      ; $000308
        jmp     $00880832.l      ; $00030E
        ifd     VR60_30_PREFETCH
        jmp     $00880000+vr60_30_prefetch_trap ; $000314 - TRAP #15
        else
        jmp     $00880832.l      ; $000314
        endif
        jmp     $00880832.l      ; $00031A
        jmp     $00880832.l      ; $000320
        jmp     $00880832.l      ; $000326
        jmp     $00880832.l      ; $00032C
        jmp     $00880832.l      ; $000332
        jmp     $00880832.l      ; $000338
        jmp     $00880832.l      ; $00033E
        jmp     $00880832.l      ; $000344
        jmp     $00880832.l      ; $00034A
        jmp     $00880832.l      ; $000350
        jmp     $00880832.l      ; $000356
        jmp     $00880832.l      ; $00035C
        jmp     $00880832.l      ; $000362
        jmp     $00880832.l      ; $000368
        jmp     $00880832.l      ; $00036E
        jmp     $00880832.l      ; $000374
        nop                      ; $00037A
        nop                      ; $00037C
        nop                      ; $00037E
        nop                      ; $000380
        nop                      ; $000382
        nop                      ; $000384
        nop                      ; $000386
        nop                      ; $000388
        nop                      ; $00038A
        nop                      ; $00038C
        nop                      ; $00038E
        nop                      ; $000390
        nop                      ; $000392
        nop                      ; $000394
        nop                      ; $000396
        nop                      ; $000398
        nop                      ; $00039A
        nop                      ; $00039C
        nop                      ; $00039E
        nop                      ; $0003A0
        nop                      ; $0003A2
        nop                      ; $0003A4
        nop                      ; $0003A6
        nop                      ; $0003A8
        nop                      ; $0003AA
        nop                      ; $0003AC
        nop                      ; $0003AE
        nop                      ; $0003B0
        nop                      ; $0003B2
        nop                      ; $0003B4
        nop                      ; $0003B6
        nop                      ; $0003B8
        nop                      ; $0003BA
        nop                      ; $0003BC
        nop                      ; $0003BE
