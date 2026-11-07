; Failed-bank detail lines (first error, count, bits, hint), for the text
; screens that have room for them. Uses RROW/CURBANK.

; faildetail: the three detail lines for CURBANK, from row RROW+1.
faildetail
	inc RROW
	lda RROW
	ldx #0
	jsr at
	lda #<s_first
	ldy #>s_first
	jsr puts
	ldx CURBANK
	lda EADRHI,x
	jsr puthex
	lda EADRLO,x
	jsr puthex
	lda #<s_w
	ldy #>s_w
	jsr puts
	ldx CURBANK
	lda EWROTE,x
	jsr puthex
	lda #<s_r
	ldy #>s_r
	jsr puts
	ldx CURBANK
	lda EREAD,x
	jsr puthex
	lda #<s_x
	ldy #>s_x
	jsr puts
	ldx CURBANK
	lda EWROTE,x
	eor EREAD,x
	sta MTMP		; bits that differ
	jsr puthex
	ldx CURBANK		; read as 1 where 0 was written: HI
	lda MTMP
	and EREAD,x
	sta CNT
	lda MTMP
	and EWROTE,x
	beq fd_hi
	lda CNT
	beq fd_lo
	lda #<s_mix
	ldy #>s_mix
	bne fd_hl
fd_hi	lda #<s_hi
	ldy #>s_hi
	bne fd_hl
fd_lo	lda #<s_lo
	ldy #>s_lo
fd_hl	jsr puts

	inc RROW
	lda RROW
	ldx #0
	jsr at
	lda #<s_errs
	ldy #>s_errs
	jsr puts
	ldx CURBANK
	lda ECNTLO,x
	sta DVAL
	lda ECNTHI,x
	sta DVAL+1
	jsr putdec
	lda #<s_bits
	ldy #>s_bits
	jsr puts
	jsr putbits

	inc RROW		; hint
	lda RROW
	ldx #1
	jsr at
	ldx CURBANK
	lda MBAD,x
	bne fd_m
	lda #<s_haddr
	ldy #>s_haddr
	jmp puts
fd_m	lda BADMASK,x
	cmp #$FF
	bne fd_some
	lda #<s_hall
	ldy #>s_hall
	jmp puts
fd_some	jsr popcnt
	cpx #1
	bne fd_sev
	lda #<s_hone
	ldy #>s_hone
	jmp puts
fd_sev	lda #<s_hsev
	ldy #>s_hsev
	jmp puts

s_first	dta d' FIRST $',$FF
s_w	dta d' W $',$FF
s_r	dta d' R $',$FF
s_x	dta d' X $',$FF
s_hi	dta d' HI',$FF
s_lo	dta d' LO',$FF
s_mix	dta d' MIX',$FF
s_errs	dta d' ERRORS ',$FF
s_haddr	dta d'ADDRESS TEST ONLY: ADDR LINE/MIRROR',$FF
s_hall	dta d'ALL BITS: BOARD, SLOT OR DECODER',$FF
s_hone	dta d'ONE BIT: ONE RAM CHIP',$FF
s_hsev	dta d'SEVERAL BITS: CHIPS OR DATA BUS',$FF
