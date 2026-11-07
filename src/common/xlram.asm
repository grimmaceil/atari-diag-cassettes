; XL/XE extra RAM: the RAM under the OS ROM (bank 4) and the 130XE extended
; banks (5-8). Needs FONT (a free 1K block for the ROM font copy) and two
; progress hooks from the stage: osprog, xeprog (called with the screen
; readable). BURNIN: the VBI clock runs throughout (see tape 2), so page $FF
; under the OS is left out and holds the NMI vector.

	.if .def BURNIN
UOEND	= $FF
	.else
UOEND	= $00			; MEND $00 = up to $FFFF
	.endif

; ---------------------------------------------------------------------------
; underos: test the RAM under the XL/XE OS ROM as bank 4. PORTB bit 0 = 0
; switches the ROM out. While it is out:
;   - no interrupts: the NMI/IRQ vectors at $FFFA come from the RAM under
;     test (stage 2 already runs with SEI and NMIEN = 0; the XL RESET key is
;     a real reset, which brings the OS back);
;   - ANTIC would draw its characters from the test patterns at $E000, so
;     the ROM font is copied to FONT first and CHBASE points there.
underos	inc OSRAM		; an XL/XE
	ldy #0			; copy the font while the ROM is still in
	sty PTR
	sty SPTR
	lda #$E0
	sta PTR+1
	lda #>FONT
	sta SPTR+1
	ldx #4
uo_cp	lda (PTR),y
	sta (SPTR),y
	iny
	bne uo_cp
	inc PTR+1
	inc SPTR+1
	dex
	bne uo_cp
	lda #>FONT
	sta CHBASE
	jsr osprog		; the stage's progress line

	.if .def BURNIN
	lda #0			; no NMI while the vector is switched
	sta NMIEN
	.endif
	lda PORTB
	sta PBSAVE
	and #$FE
	sta PORTB
	.if .def BURNIN
	lda #<nmiraw		; the clock keeps running: its NMI vector now comes
	sta $FFFA		; from RAM, in page $FF, which is left untested
	lda #>nmiraw
	sta $FFFB
	lda #$40
	sta NMIEN
	.endif
	lda #$C0		; anything there? (a 600XL with 16K has nothing)
	jsr ramat
	bcs uo_back
	lda #$E0
	jsr ramat
	bcs uo_back
	inc OSRAM		; 2: present, tested
	inc NBANKS
	lda #2			; $C000-$CFFF and $D800-$FFFF (MEND $00 = to $FFFF)
	sta RNGN
	lda #$C0
	sta RNGS
	lda #$D0
	sta RNGE
	lda #$D8
	sta RNGS+1
	lda #UOEND
	sta RNGE+1
	lda #4
	sta CURBANK
	sta BANKOVR
	jsr setfmask
	jsr march2
	inc INAIA
	lda #0
	sta AIAMODE
	jsr aia
	inc AIAMODE
	jsr aia
	dec INAIA
	lda #0
	sta BANKOVR
uo_back	.if .def BURNIN
	lda #0
	sta NMIEN
	.endif
	lda PBSAVE		; the OS back in, and its font
	sta PORTB
	.if .def BURNIN
	lda #$40
	sta NMIEN
	.endif
	lda #$E0
	sta CHBASE
	rts

; ramat: C clear if page A holds RAM, by the same rule as stage 1's size
; probe: $A5 and $5A come back with 4 or fewer wrong bits in total (a ROM or
; an empty bus gets 8). Restores the byte.
ramat	sta PTR+1
	lda #0
	sta PTR
	tay
	lda (PTR),y
	sta MTMP
	lda #$A5
	sta (PTR),y
	lda (PTR),y
	eor #$A5
	jsr popcnt
	stx CNT
	lda #$5A
	sta (PTR),y
	lda (PTR),y
	eor #$5A
	jsr popcnt
	txa
	clc
	adc CNT
	tax
	lda MTMP
	sta (PTR),y
	cpx #5
	rts

; ---------------------------------------------------------------------------
; xebanks: 130XE extended RAM. With PORTB bit 4 = 0 the CPU sees extended
; bank (bits 2-3) at $4000-$7FFF instead of main RAM. Bit 5 (ANTIC access)
; is kept 1, so ANTIC goes on showing main RAM: the screen stays right even
; if it is in that window. Banks are charged as 5-8.
XEKEEP	= %11100011		; PORTB bits left as they were
xebanks	lda PORTB
	sta PBSAVE
	lda #$5A		; extended RAM exists if bank 0 and main RAM differ
	sta $4000
	ldx #0
	jsr xesel
	lda #$B0
	sta $4000
	jsr xemain
	lda $4000
	cmp #$5A
	bne xe_back		; bank 0 is main RAM: no extended RAM
	ldx #0
	jsr xesel
	lda $4000
	cmp #$B0
	beq xe_have
xe_back	lda #0
	sta BANKOVR
	jmp xemain
xe_have	inc XERAM
	jsr xemain
	jsr xeprog		; the stage's progress line
	lda #0
	sta XEBANK
xe_bank	ldx XEBANK
	jsr xesel
	txa
	clc
	adc #5
	sta CURBANK
	sta BANKOVR
	inc NBANKS
	lda #1
	sta RNGN
	lda #$40
	sta RNGS
	lda #$80
	sta RNGE
	jsr setfmask
	jsr march2
	inc INAIA
	lda #0
	sta AIAMODE
	jsr aia
	inc AIAMODE
	jsr aia
	dec INAIA
	inc XEBANK
	lda XEBANK
	cmp #4
	bne xe_bank

; The banks against each other: every byte of every bank gets its page
; number with the bank in bits 6-7, then all are checked. A bank-select
; fault (two banks the same, a bank that is main RAM) shows here.
	lda #0
	sta XEBANK
xw_bank	ldx XEBANK
	jsr xesel
	jsr xe_pg0
xw_by	jsr xe_val
	sta (PTR),y
	iny
	bne xw_by
	inc PTR+1
	bpl xw_by		; up to $7FFF
	inc XEBANK
	lda XEBANK
	cmp #4
	bne xw_bank
	inc INAIA
	lda #0
	sta XEBANK
xc_bank	ldx XEBANK
	jsr xesel
	txa
	clc
	adc #5
	sta CURBANK
	jsr setfmask
	jsr xe_pg0
xc_by	jsr xe_val
	sta MREAD
	lda (PTR),y
	FAULTINJ
	cmp MREAD
	beq xc_ok
	jsr merr
xc_ok	iny
	bne xc_by
	inc PTR+1
	bpl xc_by
	inc XEBANK
	lda XEBANK
	cmp #4
	bne xc_bank
	dec INAIA
	jmp xe_back

; xesel: CPU sees extended bank X at $4000-$7FFF. Keeps X.
xesel	txa
	asl
	asl
	sta MTMP
	lda PBSAVE
	and #XEKEEP
	ora #$20		; ANTIC: main RAM
	ora MTMP
	sta PORTB
	rts
xemain	lda PBSAVE
	sta PORTB
	rts
xe_pg0	lda #0
	sta PTR
	tay
	lda #$40
	sta PTR+1
	rts
; xe_val: the page in bits 0-5, the bank in bits 6-7.
xe_val	lda XEBANK		; bank 0-3 -> bits 6-7
	lsr
	ror
	ror
	sta CNT
	lda PTR+1
	and #$3F
	ora CNT
	rts

