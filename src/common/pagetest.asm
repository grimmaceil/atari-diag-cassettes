; The page test and the NOT test: position-independent (branches and (zp),y
; only), copied to PICBASE in low RAM and run from there, so they can test
; the RAM the calling program sits in without testing themselves. Used by
; the burn-in (its own RAM, every pass) and the one-load 16K RAM tape.
; Copy PICLEN bytes from pgsrc to PGCODE first; interrupts must be off.
;   PGCODE: the page at NTPTR, saved at BUFP (a tested page), March C- and
;           an address-in-page test, put back; bad bits ORed into NTERR.
;   NTCODE: X pages from NTPTR, each byte inverted, read back, restored,
;           read back; bad bits ORed into NTERR.
PICBASE	= $0400			; the page and NOT tests' copies, in low RAM
PGCODE	= PICBASE		; (the cassette buffer: free once booted)
NTCODE	= PICBASE+[ntsrc-pgsrc]
NTPTR	= $88			; page under test
NTERR	= $8A			; bad bits found
NTSAV	= $8B			; NOT test: the byte
BUFP	= $8C			; page test: the save page (in the screen block)
PA	= $8E			; page test: the march's two patterns
PB	= $8F

; The page test, copied to PGCODE and written to run from anywhere:
; branches and (zp),y only. The page at NTPTR: saved at BUFP, March C- with
; PA/PB = $00/$FF then $55/$AA (up w0; up r0 w1; up r1 w0; down r0 w1;
; down r1 w0; r0), then each byte its own low address and its complement,
; then put back from BUFP and read back. Bad bits ORed into NTERR. Keeps X.
pgsrc	ldy #0
pg_sv	lda (NTPTR),y
	sta (BUFP),y
	iny
	bne pg_sv
	sty PA			; ($00/$FF first)
	dey
	sty PB
	iny			; (Y back to 0)
pg_m	lda PA			; up: w0
pg_w0	sta (NTPTR),y
	iny
	bne pg_w0
pg_a	lda (NTPTR),y		; up: r0, w1
	eor PA
	ora NTERR
	sta NTERR
	lda PB
	sta (NTPTR),y
	iny
	bne pg_a
pg_b	lda (NTPTR),y		; up: r1, w0
	eor PB
	ora NTERR
	sta NTERR
	lda PA
	sta (NTPTR),y
	iny
	bne pg_b
	dey			; down: r0, w1
pg_c	lda (NTPTR),y
	eor PA
	ora NTERR
	sta NTERR
	lda PB
	sta (NTPTR),y
	dey
	cpy #$FF
	bne pg_c
pg_d	lda (NTPTR),y		; down: r1, w0 (Y is $FF again)
	eor PB
	ora NTERR
	sta NTERR
	lda PA
	sta (NTPTR),y
	dey
	cpy #$FF
	bne pg_d
	iny			; r0
pg_e	lda (NTPTR),y
	eor PA
	ora NTERR
	sta NTERR
	iny
	bne pg_e
	lda PA			; then $55/$AA, then on
	bne pg_ai
	lda #$55
	sta PA
	lda #$AA
	sta PB
	bne pg_m
pg_ai	tya			; address in page: each byte its low address
	sta (NTPTR),y
	iny
	bne pg_ai
pg_g	tya			; read it, write the complement
	eor (NTPTR),y
	ora NTERR
	sta NTERR
	tya
	eor #$FF
	sta (NTPTR),y
	iny
	bne pg_g
pg_h	tya			; read the complement
	eor #$FF
	eor (NTPTR),y
	ora NTERR
	sta NTERR
	iny
	bne pg_h
pg_r	lda (BUFP),y		; put the page back, read it back
	sta (NTPTR),y
	eor (NTPTR),y
	ora NTERR
	sta NTERR
	iny
	bne pg_r
	rts

; The NOT test, copied after the page test (so it never inverts itself) and
; written the same way. X pages from NTPTR; errors ORed into NTERR.
ntsrc	ldy #0
nt_lp	lda (NTPTR),y
	sta NTSAV
	eor #$FF
	sta (NTPTR),y
	eor (NTPTR),y		; bits that didn't take the inverse
	ora NTERR
	sta NTERR
	lda NTSAV
	sta (NTPTR),y
	eor (NTPTR),y		; bits that didn't come back
	ora NTERR
	sta NTERR
	iny
	bne nt_lp
	inc NTPTR+1
	dex
	bne nt_lp
	rts
PICLEN	= *-pgsrc
	.if PICLEN>$C8
	.error "page and NOT tests must end below ROWBUF ($04C8)"
	.endif
