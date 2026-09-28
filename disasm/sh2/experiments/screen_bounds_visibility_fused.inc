; ============================================================================
; VR60 exact fused screen/bounds/visibility pass ($0235F6-$0236D9)
; ============================================================================
; Projects all four vertices once while accumulating X/Y bounds and the
; extreme-Y offsets.  It removes eight cache-through reloads and the two
; follow-up scans without changing signed-word truncation, tie behaviour,
; triangle duplication, pixel coverage, visibility or geometry.
;
; Differential model: 50,000 random/boundary cases, including int16/int32
; overflow, ties and both bit-0 modes.  Stock private internal entry points
; disappear; the preserved external func_031 RTS/NOP remains at $0236D6.
; ============================================================================

        assert  *=$0235F6,"fused screen/bounds/visibility start"

        dc.w    $51E3,$52E4,$6085,$81E0,$6085,$6485,$301C,$8190
        dc.w    $650F,$6653,$3428,$604B,$8191,$670F,$6C73,$EA00
        dc.w    $EB00,$6085,$6485,$301C,$8192,$6D0F,$3428,$604B
        dc.w    $8193,$640F,$3D53,$8902,$65D3,$A004,$3473,$36D3
        dc.w    $8900,$66D3,$3473,$8903,$EA04,$6743,$A005,$6085
        dc.w    $3C43,$8901,$EB04,$6C43,$6085,$6485,$301C,$8194
        dc.w    $6D0F,$3428,$604B,$8195,$640F,$3D53,$8902,$65D3
        dc.w    $A004,$3473,$36D3,$8900,$66D3,$3473,$8903,$EA08
        dc.w    $6743,$A005,$85E0,$3C43,$8901,$EB08,$6C43,$85E0
        dc.w    $C801,$8903,$5092,$1903,$A01C,$6893,$6085,$6485
        dc.w    $301C,$8196,$6D0F,$3428,$604B,$8197,$640F,$3D53
        dc.w    $8902,$65D3,$A004,$3473,$36D3,$8900,$66D3,$3473
        dc.w    $8903,$EA0C,$6743,$A005,$6893,$3C43,$8901,$EB0C
        dc.w    $6C43,$6893,$7802,$8597,$000B,$0009,$0009,$0009
        dc.w    $000B,$0009

        assert  *=$0236DA,"fused screen/bounds/visibility end"
