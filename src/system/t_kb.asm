; Test 2: keyboard. A key already down at the start is stuck (item 1). Then
; every key pressed shows on the map, and clicks the console speaker; SHIFT
; and CONTROL show with it, BREAK through its own interrupt latch. START
; ends the test; a key not pressed by then fails item 2. HELP and F1-F4
; (XL) show but aren't required.

KBSEEN	= TSCR+$00		; 8: KBCODEs seen, one bit each
KBX	= TSCR+$08		; bit 0 SHIFT, 1 CONTROL, 2 BREAK seen
KBLEFT	= TSCR+$09		; required keys still to press
KBPREV	= TSCR+$0A		; SKSTAT bit 2 last frame (key held = 0)
LCOL	= TSCR+$0B		; light: column of the character being lit
LPMY	= TSCR+$0C		; light: P/M byte of the key's text row
KACT	= TSCR+$0D		; offset of the key shown held ($FF: none)
KCACT	= TSCR+$0E		; nonzero: CONTROL shown held
SHACT	= TSCR+$0F		; nonzero: SHIFT shown held
BRKT	= TSCR+$10		; frames BREAK stays shown held (it has no key-up)
LMODE	= TSCR+$11		; light: $80 held (inverse + P/M), 0 back to done
LXS	= TSCR+$12		; light: caller's X; kbinv: its Y (+1)

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


t_kb	lda #2
	sta TEST
	lda #0			; nothing seen yet (the scratch is shared)
	ldx #KBX-KBSEEN
kb_clr	sta KBSEEN,x
	dex
	bpl kb_clr
	sta SHACT
	sta KCACT
	sta BRKT
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
	jsr kbinv		; the pressed keys in inverse: the result screen
	jsr pmoff		; has no P/M colors (nor do the flashes)
	jsr waitrel
	lda KBLEFT
	beq kb_end
	lda #2
	ora BADMASK+2
	sta BADMASK+2
kb_end	jmp tend

; kbinv: every key seen, inverse, and the legend to match, so the missing
; ones stand out on the result screen.
kbinv	lda DISPOK
	beq ki_x
	ldy #63
ki_lp	tya			; KBCODE Y seen?
	lsr
	lsr
	lsr
	tax
	tya
	and #7
	sta MTMP
	lda KBSEEN,x
	ldx MTMP
ki_sh	dex
	bmi ki_bit
	lsr
	bpl ki_sh		; (A shifts right: never negative after one)
ki_bit	lsr
	bcc ki_nx
	lda kbofs,y
	cmp #$FF
	beq ki_nx
	sty LXS+1		; (light keeps X, not Y)
	jsr light
	ldy LXS+1
ki_nx	dey
	bpl ki_lp
	lda KBX			; SHIFT, CONTROL, BREAK
	lsr
	pha
	bcc ki_c
	lda #KO_SHIFT1
	jsr light
	lda #KO_SHIFT2
	jsr light
ki_c	pla
	lsr
	pha
	bcc ki_b
	lda #KO_CTRL
	jsr light
ki_b	pla
	lsr
	bcc ki_l
	lda #KO_BREAK
	jsr light
ki_l	lda #KBROW+5
	jsr clrrow
	PRINT KBROW+5, 0, s_kb3
ki_x	rts

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
	PRINT 14, 0, s_kleft
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

	icl 'kbmap.asm'
kbrtab	.word kbrow0, kbrow1, kbrow2, kbrow3, kbrow4

s_kb1	dta d'PRESS EVERY KEY. START ENDS THE TEST.',$FF
s_kb2	dta d'NOT PRESSED YET  DONE  HELD',$FF
s_kb3	dta d'INVERSE: PRESSED. NORMAL: NOT PRESSED',$FF
KL_DONE	= 5*40+17		; legend words, as keyboard offsets
KL_HELD	= 5*40+23
s_stuck	dta d'A KEY WAS DOWN AT THE START: STUCK?'*,$FF
s_kleft	dta d'KEYS LEFT ',$FF
