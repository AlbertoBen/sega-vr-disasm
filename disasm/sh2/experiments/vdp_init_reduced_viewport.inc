; Isolated VR60 render-load experiment for $0232D4-$02332F.
;
; Byte-identical to sh2/generated/vdp_init_short.inc except for viewport clip:
;   y min/max: 16..207 -> 32..191  (160 scanlines)
;   x min/max:  0..319 -> 32..287  (256 pixels)
;
; Projection centre (160,112), code layout, call ABI, command protocol and
; simulation state are unchanged.  The block remains exactly 92 bytes.

        dc.w    $DE0D
        dc.w    $C70F
        dc.w    $E70E
        dc.w    $6DE3
        dc.w    $7D0C
        dc.w    $6106
        dc.w    $2D12
        dc.w    $4710
        dc.w    $8FFB
        dc.w    $7D04
        dc.w    $D009
        dc.w    $51E9
        dc.w    $210B
        dc.w    $E008
        dc.w    $970B
        dc.w    $811E
        dc.w    $7140
        dc.w    $811E
        dc.w    $7140
        dc.w    $811E
        dc.w    $7140
        dc.w    $811E
        dc.w    $4710
        dc.w    $8FF6
        dc.w    $7140
        dc.w    $000B
        dc.w    $0009
        dc.w    $0040
        dc.w    $C000
        dc.w    $0700
        dc.w    $2000
        dc.w    $0000
        dc.w    $0000
        dc.w    $00A0        ; projection centre x = 160
        dc.w    $0000
        dc.w    $0070        ; projection centre y = 112
        dc.w    $0000
        dc.w    $0020        ; y min = 32
        dc.w    $0000
        dc.w    $00BF        ; y max = 191
        dc.w    $0000
        dc.w    $0020        ; x min = 32
        dc.w    $0000
        dc.w    $011F        ; x max = 287
        dc.w    $0601
        dc.w    $8000
