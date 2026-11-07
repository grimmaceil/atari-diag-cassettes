; Test 5: joysticks and triggers, live: a direction or fire shows inverse
; while it is active. One already active at the start is stuck: item = port.
; START ends it, or a keyboard key (in case START is dead).
JX	= TSCR+$00		; jshow: label being printed
JBITS	= TSCR+$01		; jshow: the port's active bits

t_joy	lda #5
	sta TEST
	lda #<s_t5
	ldy #>s_t5
	jsr tpage
	lda DISPOK
	beq jy_s0
	PRINT 5, 0, s_joy1
jy_s0	ldx #0			; stuck: whatever is active now
jy_st	jsr jread
	beq jy_sn
	lda bitn,x
	ora BADMASK+5
	sta BADMASK+5
jy_sn	inx
	cpx NPORT
	bne jy_st
	jsr waitrel
jy_lp	jsr vsync
	ldx #0
jy_port	stx CNT
	jsr jread
	jsr jshow
	ldx CNT
	inx
	cpx NPORT
	bne jy_port
	lda CONSOL		; START ends it, or a key if START is dead
	lsr
	bcc jy_end
	lda SKSTAT
	and #4
	bne jy_lp
jy_end	jsr waitrel
	jmp tend

; jread: port X now: bits 0-3 up, down, left, right, bit 4 fire (1 =
; active). Ports 0-1 are PORTA, 2-3 PORTB (400/800 only). Keeps X.
jread	lda PORTA
	cpx #2
	bcc jr_a
	lda PORTB
jr_a	sta MTMP
	txa
	and #1
	beq jr_lo
	lsr MTMP		; odd port: the high nibble
	lsr MTMP
	lsr MTMP
	lsr MTMP
jr_lo	lda MTMP
	eor #$0F		; 0 = pressed
	and #$0F
	sta MTMP
	lda TRIG0,x
	and #1
	bne jr_x
	lda #$10
	ora MTMP
	sta MTMP
jr_x	lda MTMP
	rts

; jshow: port CNT's row (7+port), bits A: "STICK n  UP DOWN LEFT RIGHT
; FIRE", each active one inverse.
jshow	sta JBITS
	lda DISPOK
	beq js_x
	lda CNT
	clc
	adc #7
	ldx #0
	jsr at
	lda #<s_stick
	ldy #>s_stick
	jsr puts
	lda CNT
	clc
	adc #$11
	jsr putc
	lda #0
	sta JX
js_lp	lda #0
	sta INV
	jsr putc
	lsr JBITS
	bcc js_n
	lda #$80
	sta INV
js_n	lda JX
	asl
	tay
	lda jlabels,y
	pha
	lda jlabels+1,y
	tay
	pla
	jsr puts
	inc JX
	lda JX
	cmp #5
	bne js_lp
	lda #0
	sta INV
js_x	rts
jlabels	.word s_up, s_down, s_left, s_right, s_fire

s_joy1	dta d'MOVE EACH STICK, FIRE. START/A KEY ENDS',$FF
s_stick	dta d'STICK ',$FF
s_up	dta d'UP',$FF
s_down	dta d'DOWN',$FF
s_left	dta d'LEFT',$FF
s_right	dta d'RIGHT',$FF
s_fire	dta d'FIRE',$FF
