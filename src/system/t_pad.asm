; Test 6: paddles. POTGO starts a scan; each POTn counts scanlines until its
; RC charge crosses the threshold, 228 at most.
;   open-input check: with nothing plugged in every input must read 228,
;   which proves the scan works. One that doesn't fails item = paddle.
;   live: value bar, min/max seen (a full turn reaches about 1 and 228),
;   jitter (spread over 16 frames: big with the knob still = dirty pot),
;   the paddle trigger. SELECT: fast scan (SKCTL bit 2). START ends it.
PCUR	= TSCR+$00		; 8: paddle values now
PMIN	= TSCR+$08		; 8
PMAX	= TSCR+$10		; 8
WMIN	= TSCR+$18		; 8: this 16-frame window, for the jitter
WMAX	= TSCR+$20		; 8
PJIT	= TSCR+$28		; 8: the last window's spread
PFRM	= TSCR+$30		; frame count in the window
PFAST	= TSCR+$31		; nonzero: fast pot scan (SKCTL bit 2)

t_pad	lda #6
	sta TEST
	lda #<s_t6
	ldy #>s_t6
	jsr tpage
	lda DISPOK
	beq pd_s0
	PRINT 5, 0, s_pd1
	PRINT 6, 0, s_pd2
pd_s0	lda #0
	sta PFAST
	jsr waitrel
pd_w	jsr vsync		; START: check, SELECT: skip it
	lda CONSOL
	lsr
	bcc pd_chk
	lsr
	bcs pd_w
	jmp pd_live
pd_chk	jsr potscan		; one scan to start, one to read
	jsr potscan
	ldx #0
pd_c	lda PCUR,x
	cmp #228
	beq pd_cok
	lda bitn,x
	ora BADMASK+6
	sta BADMASK+6
pd_cok	inx
	jsr npots
	bne pd_c

pd_live	jsr waitrel
	lda DISPOK
	beq pd_l0
	lda #5
	jsr clrrow
	lda #6
	jsr clrrow
	PRINT 5, 0, s_pd3
pd_l0	ldx #7
pd_i	lda #228
	sta PMIN,x
	sta WMIN,x
	lda #0
	sta PMAX,x
	sta WMAX,x
	sta PJIT,x
	dex
	bpl pd_i
	lda #0
	sta PFRM
pd_lp	jsr potscan
	ldx #0
pd_u	lda PCUR,x		; min/max, and the window
	cmp PMIN,x
	bcs pd_u1
	sta PMIN,x
pd_u1	cmp PMAX,x
	bcc pd_u2
	sta PMAX,x
pd_u2	cmp WMIN,x
	bcs pd_u3
	sta WMIN,x
pd_u3	cmp WMAX,x
	bcc pd_u4
	sta WMAX,x
pd_u4	inx
	jsr npots
	bne pd_u
	inc PFRM		; every 16 frames: the window's spread is the jitter
	lda PFRM
	and #15
	bne pd_sh
	ldx #7
pd_j	lda WMAX,x
	sec
	sbc WMIN,x
	bcs pd_j1
	lda #0
pd_j1	sta PJIT,x
	lda #228
	sta WMIN,x
	lda #0
	sta WMAX,x
	dex
	bpl pd_j
pd_sh	jsr potshow
	lda CONSOL
	lsr
	bcc pd_end
	lsr			; SELECT: fast scan on/off
	bcs pd_lp
	lda PFAST
	eor #1
	sta PFAST
	jsr waitrel
	jmp pd_lp
pd_end	lda #3			; SKCTL back to normal
	sta SKCTL
	jsr waitrel
	jmp tend

; npots: compare X with the number of paddles (twice the ports): Z set at
; the end.
npots	lda NPORT
	asl
	sta MTMP
	cpx MTMP
	rts

; potscan: wait a frame, read all eight, start the next scan.
potscan	jsr vsync
	ldx #0
ps_rd	lda POT0,x
	sta PCUR,x
	inx
	cpx #8
	bne ps_rd
	lda #3			; SKCTL bit 2: fast scan (a couple of scanlines)
	ldx PFAST
	beq ps_n
	lda #7
ps_n	sta SKCTL
	sta POTGO
	rts

; potshow: row 8+n per paddle: "P1 <bar> VAL MIN MAX JIT T".
potshow	lda DISPOK
	bne pw_go
	rts
pw_go	PRINT 7, 0, s_pdh
	lda PFAST
	beq pw_r
	PRINT 7, 0, s_fast
pw_r	ldx #0
pw_lp	stx CNT
	txa
	clc
	adc #8
	ldx #0
	jsr at
	lda #$30		; 'P'
	jsr putc
	lda CNT
	clc
	adc #$11
	jsr putc
	lda #0
	jsr putc
	ldx CNT			; the bar: value/12, up to 19 inverse spaces
	lda PCUR,x
	ldy #0
pw_div	cmp #12
	bcc pw_bar
	sbc #12
	iny
	bne pw_div
pw_bar	ldx #19
pw_b	lda #0
	cpy #0
	beq pw_sp
	lda #$80
	dey
pw_sp	jsr putc
	dex
	bne pw_b
	ldx CNT
	lda PCUR,x
	jsr put3
	ldx CNT
	lda PMIN,x
	jsr put3
	ldx CNT
	lda PMAX,x
	jsr put3
	ldx CNT
	lda PJIT,x
	jsr put3
	lda #0
	jsr putc
	ldx CNT			; the trigger: a joystick direction line
	jsr ptrig
	lda #0
	bcc pw_t
	lda #$B4		; inverse 'T'
pw_t	jsr putc
	ldx CNT
	inx
	jsr npots
	beq pw_x
	jmp pw_lp
pw_x	rts

; ptrig: C set if paddle X's trigger is pressed. Paddles 0-1 are PORTA bits
; 2-3, 2-3 bits 6-7; 4-7 the same in PORTB (400/800).
ptrig	txa
	and #3
	tay
	lda PORTA
	cpx #4
	bcc pt_a
	lda PORTB
pt_a	and ptbit,y
	clc
	bne pt_x
	sec
pt_x	rts
ptbit	.byte $04, $08, $40, $80

; put3: A as " nnn" (three digits, leading zeros).
put3	pha
	lda #0
	jsr putc
	pla
	ldx #0
p3_h	cmp #100
	bcc p3_t
	sbc #100
	inx
	bne p3_h
p3_t	pha
	txa
	clc
	adc #$10
	jsr putc
	pla
	ldx #0
p3_tl	cmp #10
	bcc p3_o
	sbc #10
	inx
	bne p3_tl
p3_o	pha
	txa
	clc
	adc #$10
	jsr putc
	pla
	clc
	adc #$10
	jmp putc

s_pd1	dta d'UNPLUG ALL PADDLES, THEN PRESS START',$FF
s_pd2	dta d'(SELECT SKIPS THE OPEN-INPUT CHECK)',$FF
s_pd3	dta d'TURN EACH. SELECT=FAST SCAN. START ENDS.',$FF
s_pdh	dta d'                       VAL MIN MAX JIT',$FF
s_fast	dta d'FAST SCAN'*,$FF
