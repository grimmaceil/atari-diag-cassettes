; Test 3: console keys and the speaker.
;   items 1-3: START, SELECT, OPTION not seen (it waits for all three, or for
;              a keyboard key when one of them is dead)
;   item 4: the speaker tone not heard (it repeats until the answer)
CONSEEN	= TSCR+$00		; console keys seen (CONSOL bits, 1 = seen)

t_con	lda #3
	sta TEST
	lda #<s_t3
	ldy #>s_t3
	jsr tpage
	PRINT 5, 0, s_con1
	PRINT 6, 0, s_con2
	PRINT 8, 0, s_cons
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
	lda SKSTAT		; a keyboard key: one of them is dead
	and #4
	bne co_lp
co_spk	lda CONSEEN		; the keys never seen are items 1-3
	eor #7
	sta BADMASK+3
	jsr waitrel
	PRINT 11, 0, s_spk
	PRINT 12, 0, s_heard
	lda #2			; the speaker tone, over and over
	sta YNSND
	jsr yesno
	bcs co_end
	lda #8
	ora BADMASK+3
	sta BADMASK+3
co_end	jmp tend

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

s_con1	dta d'PRESS START, SELECT AND OPTION.',$FF
s_con2	dta d'(ONE DEAD? PRESS ANY KEY TO GO ON.)',$FF
s_cons	dta d'START  SELECT  OPTION',$FF
s_spk	dta d'LISTEN: A TONE FROM THE CONSOLE SPEAKER',$FF
