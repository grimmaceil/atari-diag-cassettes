; A8 DIAG tape 3, stage 1: the system tests that fit an 8K 400.
;   2 keyboard           stuck keys, then a key map lit as keys are pressed
;   3 console keys       START, SELECT, OPTION and the console speaker
; Then stage 2 (16K and up): 1 ROM checksums, 4 POKEY, 5 joysticks,
; 6 paddles, 7 GTIA, and the summary. (The numbers are the brief's.)
;
; Boots like the other tapes (alive, image checksum, low RAM, size probe,
; machine, display prerequisites). The screen block gets a quick test only:
; tape 1 tests RAM.
;
; A test that passes plays the jingle and goes on by itself (~2 s). One that
; fails shows which items failed and plays A = test number, B = item, until
; START, a key or fire; SELECT replays it, OPTION switches to full-screen
; flashes.

	icl '../common/hw.asm'
	icl '../common/vars.asm'
	icl '../common/faults.asm'

QUICKSCR = 1			; display.asm: quick screen-block test
NORAMCHK = 1			; loader.asm: BADMASK holds test results here
; ONESTAGE (build.py, the diag-400 set): an 8K 400 never loads stage 2, so
; the loader and its messages are left out and test 3 ends the tape.

; Stage 1 data, in T3D (see t3common.asm).
KBSEEN	= T3D+$08		; 8: KBCODEs seen, one bit each
KBX	= T3D+$10		; bit 0 SHIFT, 1 CONTROL, 2 BREAK seen
KBLEFT	= T3D+$11		; required keys still to press
KBPREV	= T3D+$12		; SKSTAT bit 2 last frame (key held = 0)
CONSEEN	= T3D+$13		; console keys seen (CONSOL bits, 1 = seen)
RTIME	= T3D+$14		; 2: frames left in a timed wait
LCOL	= T3D+$16		; light: column of the character being lit
LPMY	= T3D+$17		; light: P/M byte of the key's text row
KACT	= T3D+$18		; offset of the key shown held ($FF: none)
KCACT	= T3D+$19		; nonzero: CONTROL shown held
SHACT	= T3D+$1A		; nonzero: SHIFT shown held
BRKT	= T3D+$1B		; frames BREAK stays shown held (it has no key-up)
LMODE	= T3D+$1C		; light: $80 held (inverse + P/M), 0 back to done
LXS	= T3D+$1D		; light: caller's X

KBROW	= 8			; first row of the on-screen keyboard

; Each key shows one of three states, told apart by brightness so they read
; on a monochrome screen and without color vision:
;   not pressed yet   light letters on black
;   done              light letters on a mid green cell (P/M behind it)
;   held now          the same cell inverted: bright cell, darker letters
; GR.0 gives every character the same hue, but a player in front of the
; playfield lends its color to the cell and the letters keep the text
; brightness.
; Four quad-width players and four quad-width missiles are one bit per
; character column, so their memory is a color mask for the text screen.
; Double-line resolution, PM block at $0400: missiles $0580, players
; $0600-$07FF (free low RAM once the boot is done).
PMPAGE	= $04
C_LIT	= $C6			; behind a done key: luminance 6, between black and the text's 12

	opt h-
LOAD	= $0800
	org LOAD

; Cassette boot header. The OS reads NREC records to LOAD, then JSRs LOAD+6.
	.byte 0
	.byte NREC
	.word LOAD
	.word init_rts

	icl '../common/boot.asm'

	jsr detect
	jsr dprereq
	jmp t_kb

; ---------------------------------------------------------------------------
; Test 2: keyboard. A key already down at the start is stuck (item 1). Then
; every key pressed lights on the map, and clicks the console speaker; SHIFT
; and CONTROL light with it, BREAK through its own interrupt latch. START
; ends the test; a key not pressed by then fails item 2. HELP and F1-F4
; (XL) light but aren't required.
t_kb	lda #2
	sta TEST
	lda #<s_t2
	ldy #>s_t2
	jsr tpage
	lda #KBNREQ+3		; + SHIFT, CONTROL, BREAK
	sta KBLEFT
	lda DISPOK
	beq kb_stk
	PRINT 5, 0, s_kb1
	ldx #0
kb_rows	stx CNT
	txa
	clc
	adc #KBROW
	ldx #0
	jsr at
	lda CNT
	asl
	tax
	lda kbrtab,x
	ldy kbrtab+1,x
	jsr puts
	ldx CNT
	inx
	cpx #KBROWS
	bne kb_rows
	jsr pmon
	PRINT KBROW+5, 0, s_kb2	; the legend, in its own states
	lda #KL_DONE
	jsr light
	lda #KL_DONE
	jsr unlit
	lda #KL_HELD
	jsr light

kb_stk	lda SKSTAT		; stuck: a key or SHIFT down before any was asked
	and #$0C
	cmp #$0C
	beq kb_go
	lda #1
	sta BADMASK+2
	lda DISPOK
	beq kb_go
	PRINT 6, 0, s_stuck
kb_go	lda #$80		; BREAK: latched by POKEY's IRQ status (masked)
	sta IRQEN
	lda #4
	sta KBPREV
	lda #$FF
	sta KACT
	jsr waitrel

kb_lp	jsr vsync
	jsr showleft
	lda SKSTAT		; a new key down?
	and #4
	tax
	eor KBPREV
	stx KBPREV
	and #4
	beq kb_sh
	jsr kbup		; down or up, the key shown held is let go
	txa
	bne kb_sh		; that was a release
	lda KBCODE
	jsr kbdown
kb_sh	lda SKSTAT		; SHIFT: held while bit 3 = 0
	and #8
	bne kb_shup
	lda SHACT
	bne kb_br
	inc SHACT
	lda #1
	jsr kbextra
	lda #KO_SHIFT1
	jsr light
	lda #KO_SHIFT2
	jsr light
	jmp kb_br
kb_shup	lda SHACT
	beq kb_br
	lda #0
	sta SHACT
	lda #KO_SHIFT1
	jsr unlit
	lda #KO_SHIFT2
	jsr unlit
kb_br	lda BRKT		; BREAK: shown held for a moment
	beq kb_brk
	dec BRKT
	bne kb_brk
	lda #KO_BREAK
	jsr unlit
kb_brk	lda IRQST
	bmi kb_st
	lda #0
	sta IRQEN
	lda #$80
	sta IRQEN
	lda #4
	jsr kbextra
	lda #KO_BREAK
	jsr light
	lda #20
	sta BRKT
	jsr click
kb_st	lda CONSOL		; START ends it
	lsr
	bcc kb_done
	jmp kb_lp
kb_done

	lda #0
	sta IRQEN
	jsr pmoff		; before the result: the flash screen has no PMs
	jsr waitrel
	lda KBLEFT
	beq kb_end
	lda #2
	ora BADMASK+2
	sta BADMASK+2
kb_end	lda #<t_con
	sta NEXTVEC
	lda #>t_con
	sta NEXTVEC+1
	jmp tresult

; kbup: the key (and CONTROL) shown held goes back to done. Keeps X.
kbup	lda KACT
	cmp #$FF
	beq ku_c
	jsr unlit
	lda #$FF
	sta KACT
ku_c	lda KCACT
	beq ku_x
	lda #0
	sta KCACT
	lda #KO_CTRL
	jmp unlit
ku_x	rts

; kbdown: KBCODE A was pressed: show it (and CONTROL) held, count it.
kbdown	pha
	and #$80		; bit 7: CONTROL
	beq kd_nc
	sta KCACT
	lda #2
	jsr kbextra
	lda #KO_CTRL
	jsr light
kd_nc	pla
	and #$3F
	tay
	lsr			; seen before?
	lsr
	lsr
	tax
	tya
	and #7
	tay
	lda #0
	sec
kd_bit	rol
	dey
	bpl kd_bit
	sta MTMP
	and KBSEEN,x
	bne kd_lit
	lda MTMP		; first time: count it if it's a required key
	ora KBSEEN,x
	sta KBSEEN,x
	lda MTMP
	and kbreq,x
	beq kd_lit
	dec KBLEFT
kd_lit	lda KBCODE
	and #$3F
	tax
	lda kbofs,x
	sta KACT
	cmp #$FF
	beq kd_x
	jsr light
kd_x	jmp click

; kbextra: SHIFT/CONTROL/BREAK bit A seen: count it the first time.
kbextra	tax
	and KBX
	bne ke_x
	txa
	ora KBX
	sta KBX
	dec KBLEFT
ke_x	rts

; light: show the key label at keyboard offset A (up to the next space) held:
; inverse, with the P/M color behind it, which stays when unlit puts the
; label back to normal video (done). Keeps X.
light	ldy #$80
	bne li_go
unlit	ldy #0
li_go	sty LMODE
	ldy DISPOK
	beq li_x
	stx LXS
	pha
	ldx #16+KBROW*4		; P/M byte of text row 0 is 16 (scan line 32)
li_dv	cmp #40			; offset -> row (X, 4 bytes a row) and column
	bcc li_rc
	sbc #40
	inx
	inx
	inx
	inx
	bne li_dv
li_rc	sta LCOL
	stx LPMY
	pla
	clc
	adc #<[KBROW*40]
	sta CUR
	lda SCRPG
	adc #>[KBROW*40]
	sta CUR+1
	ldy #0
li_lp	lda (CUR),y
	and #$7F
	beq li_end		; the space after the label
	cmp #$7F
	beq li_end		; the row's $FF end
	ora LMODE
	sta (CUR),y
	bit LMODE
	bpl li_nx
	jsr pmset
li_nx	inc LCOL
	iny
	bne li_lp
li_end	ldx LXS
li_x	rts

; pmset: set column LCOL's bit in the P/M mask for the 4 bytes (8 scan
; lines) from LPMY. Columns 0-31: player LCOL/8, bit 7 leftmost; 32-39:
; missile (LCOL-32)/2, two bits each, M0 in bits 0-1. Keeps Y.
pmset	tya
	pha
	lda LCOL
	cmp #32
	bcs pm_m
	tay
	and #7
	tax
	lda pmpbit,x
	sta MTMP
	tya
	lsr			; player number; the high half of it picks the
	lsr			; page, the low bit the half page
	lsr
	lsr
	tax
	lda #0
	ror
	ora LPMY
	sta PTR
	txa
	clc
	adc #PMPAGE+2
	sta PTR+1
	bne pm_set
pm_m	and #7
	tax
	lda pmmbit,x
	sta MTMP
	lda LPMY
	ora #$80
	sta PTR
	lda #PMPAGE+1
	sta PTR+1
pm_set	ldy #3
pm_lp	lda (PTR),y
	ora MTMP
	sta (PTR),y
	dey
	bpl pm_lp
	pla
	tay
	rts
pmpbit	.byte $80, $40, $20, $10, $08, $04, $02, $01
pmmbit	.byte $02, $01, $08, $04, $20, $10, $80, $40

; pmon: clear the P/M block, line the players and missiles up with the 40
; columns (playfield starts at color clock 48, 4 clocks a column) and start
; P/M DMA. Only with the text screen on.
pmon	lda #0
	tay
pn_clr	sta PMPAGE*$100+$100,y
	sta PMPAGE*$100+$200,y
	sta PMPAGE*$100+$300,y
	iny
	bne pn_clr
	ldx #7
pn_pos	lda pmhpos,x
	sta HPOSP0,x
	dex
	bpl pn_pos
	ldx #3
pn_sz	lda #3
	sta SIZEP0,x
	lda #C_LIT
	sta COLPM0,x
	dex
	bpl pn_sz
	lda #$FF
	sta SIZEM
	lda #1
	sta PRIOR
	lda #PMPAGE
	sta PMBASE
	lda #$2E		; + missile and player DMA, double-line
	sta DMACTL
	lda #3
	sta GRACTL
	rts
pmhpos	.byte 48, 80, 112, 144, 176, 184, 192, 200

; pmoff: P/M off and out of sight ($D000-$D011: positions, sizes and the
; graphics latches all 0). The display list DMA stays as it was.
pmoff	lda #0
	sta GRACTL
	ldx #$11
pf_lp	sta HPOSP0,x
	dex
	bpl pf_lp
	sta PRIOR
pf_x	rts

; showleft: "KEYS LEFT nn" on row 14.
showleft	lda DISPOK
	beq pf_x
	PRINT 14, 0, s_left
	lda KBLEFT
	sta DVAL
	lda #0
	sta DVAL+1
	jsr putdec
	lda #0
	jmp putc

; click: a short burst on the console speaker (the keyboard click).
click	lda #$08
	sta SPKMASK
	WAITMS 30
	lda #0
	sta SPKMASK
	lda #$08
	sta SPKPH
	sta CONSOL
	rts

; ---------------------------------------------------------------------------
; Test 3: console keys and the speaker.
;   items 1-3: START, SELECT, OPTION not seen within 30 s
;   item 4: the speaker click not heard
t_con	lda #3
	sta TEST
	lda #<s_t3
	ldy #>s_t3
	jsr tpage
	PRINT 5, 0, s_con1
	PRINT 8, 0, s_cons
	lda #<[30*60]
	sta RTIME
	lda #>[30*60]
	sta RTIME+1
	lda #0
	sta CONSEEN
	jsr waitrel
co_lp	jsr vsync
	lda CONSOL		; seen = pressed at least once
	eor #7
	and #7
	ora CONSEEN
	sta CONSEEN
	lsr
	bcc co_2
	lda #0
	jsr lcon
co_2	lda CONSEEN
	and #2
	beq co_3
	lda #7
	jsr lcon
co_3	lda CONSEEN
	and #4
	beq co_t
	lda #15
	jsr lcon
co_t	lda CONSEEN
	cmp #7
	beq co_spk
	lda RTIME
	bne co_dec
	dec RTIME+1
co_dec	dec RTIME
	lda RTIME
	ora RTIME+1
	bne co_lp
co_spk	lda CONSEEN		; the keys never seen are items 1-3
	eor #7
	sta BADMASK+3
	jsr waitrel
	PRINT 11, 0, s_spk
	lda #$08		; 1.5 s of console speaker tone
	sta SPKMASK
	WAITMS 1500
	lda #0
	sta SPKMASK
	PRINT 12, 0, s_heard
	jsr yesno
	bcs co_end
	lda #8
	ora BADMASK+3
	sta BADMASK+3
	.ifdef ONESTAGE
co_end	lda #<final
	sta NEXTVEC
	lda #>final
	.else
co_end	lda #<load2
	sta NEXTVEC
	lda #>load2
	.endif
	sta NEXTVEC+1
	jmp tresult

; lcon: invert the console key label at row 8, column A.
lcon	clc
	adc #<[8*40]
	sta CUR
	lda SCRPG
	adc #>[8*40]
	sta CUR+1
	ldx DISPOK
	beq lc_x
	ldy #0
lc_lp	lda (CUR),y
	beq lc_x
	ora #$80
	sta (CUR),y
	iny
	bne lc_lp
lc_x	rts

; tpage: a fresh page for test TEST, titled A/Y.
tpage	ldx DISPOK
	beq tp_x
	pha
	tya
	pha
	jsr scr_on
	pla
	tay
	pla
	jsr header
	lda #2
	jmp machinfo
tp_x	rts

; ---------------------------------------------------------------------------
; Stage 2 not run (8K, or a load error): the result of tests 1-3 is final.
; results is also the loader's redraw.
results	jsr scr_on
	lda #<s_hres
	ldy #>s_hres
	jsr header
	lda #2
	jsr machinfo
	ldx #2			; the tests this stage ran
rz_lp	stx CNT
	txa
	clc
	adc #4
	ldx #0
	jsr at
	lda CNT
	asl
	tax
	lda tnames-2,x
	ldy tnames-1,x
	jsr puts
	lda #0
	jsr putc
	ldx CNT
	lda BADMASK,x
	beq rz_p
	lda #<s_fail
	ldy #>s_fail
	jsr puts
	jmp rz_n
rz_p	lda #<s_pass
	ldy #>s_pass
	jsr puts
rz_n	ldx CNT
	inx
	cpx #4
	bne rz_lp
	.ifndef ONESTAGE
	lda L2MSG+1
	beq rs_pr
	PRINT 22, 0, s_l2pre
	lda L2MSG
	ldy L2MSG+1
	jsr puts
	lda L2STAT
	beq rs_pr
	jsr puthex
	.endif
rs_pr	lda CONTVEC+1
	beq rs_fin
	PRINT 23, 0, s_toggle
	rts
rs_fin	PRINT 23, 0, s_toggle2
	rts

sushow	= results		; t3common's redraw once the tests are over
final	lda #8
	sta TEST
	lda #2			; pass: one long flash per test (2 and 3 ran)
	sta NBANKS
	ldx #8
fi_lp	lda BADMASK,x
	bne fi_bad
	dex
	bne fi_lp
	jmp pass
fi_bad	jmp report

	.ifndef ONESTAGE
	icl '../common/loader.asm'
	.endif
	icl '../common/display.asm'

init_rts rts

; Low-RAM patterns: solid, checkerboard, walking 1, walking 0.
pats	.byte $00,$FF,$55,$AA
	.byte $01,$02,$04,$08,$10,$20,$40,$80
	.byte $FE,$FD,$FB,$F7,$EF,$DF,$BF,$7F
NPAT	= *-pats

	icl '../common/report.asm'
	icl '../common/screen.asm'
	icl '../common/info.asm'
	icl 't3common.asm'
	icl 'kbmap.asm'
kbrtab	.word kbrow0, kbrow1, kbrow2, kbrow3, kbrow4

s_hpre	dta d' A8 DIAG  TAPE 3/3  ',$FF
s_hres	dta d'RESULTS',$FF
s_kb1	dta d'PRESS EVERY KEY. START ENDS THE TEST.',$FF
s_kb2	dta d'NOT PRESSED YET  DONE  HELD',$FF
KL_DONE	= 5*40+17		; legend words, as keyboard offsets
KL_HELD	= 5*40+23
s_stuck	dta d'A KEY WAS DOWN AT THE START: STUCK?'*,$FF
s_left	dta d'KEYS LEFT ',$FF
s_con1	dta d'PRESS START, SELECT AND OPTION.',$FF
s_cons	dta d'START  SELECT  OPTION',$FF
s_spk	dta d'LISTEN: A TONE FROM THE CONSOLE SPEAKER',$FF
s_heard	dta d'HEARD IT? Y/START = YES, N/SELECT = NO',$FF
s_toggle2 dta d'SELECT=REPLAY  OPTION=FULL-SCREEN FLASH',$FF
	.ifndef ONESTAGE
s_l2load dta d'LOADING STAGE 2, KEEP TAPE PLAYING',$FF
s_l2pre	dta d'STAGE 2: ',$FF
s_l2_8k	dta d'NEEDS 16K, TAPE 3 ENDS HERE',$FF
s_l2_bad dta d'NOT LOADED',$FF
s_l2_big dta d'TOO BIG FOR THE RAM',$FF
s_l2_sio dta d'ERROR $',$FF
s_l2_hdr dta d'NOT ON TAPE',$FF
s_l2_sum dta d'BAD CHECKSUM',$FF
	.endif

; Pad to a whole page; the last two bytes hold the image sum (mkcas.py).
PADTO	= [[*+2+$FF]/$100]*$100
	.if PADTO-*-2>0
	:[PADTO-*-2] .byte 0
	.endif
CKSUM	.word 0
IMGEND
NREC	= [IMGEND-LOAD]/128
BSS	= IMGEND
TSTART	= [>BSS]+1
