; Bad-bit lists for the result screens.

; putbits: " D4 D6" for every bad bit of bank CURBANK.
putbits	ldx CURBANK
	lda BADMASK,x
	sta MTMP
	ldx #0
pb_bit	lsr MTMP
	bcc pb_nob
	lda #0
	jsr putc
	lda #$24		; 'D'
	jsr putc
	txa
	clc
	adc #$10
	jsr putc
pb_nob	inx
	cpx #8
	bne pb_bit
	rts

; bitsline: the next row (RROW+1) gets " BITS D4 D6" for bank CURBANK.
bitsline inc RROW
	lda RROW
	ldx #0
	jsr at
	lda #<s_bits
	ldy #>s_bits
	jsr puts
	jmp putbits

s_bits	dta d'  BITS',$FF
