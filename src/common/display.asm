; Machine detection and the display prerequisites (VCOUNT, character ROM
; sum, screen block), shared by the boot stages. Needs TSTART.

; ---------------------------------------------------------------------------
; Machine and video standard. The XL/XE OS ROM covers $C000-$FFFF; on the
; 400/800 nothing answers at $C000-$CFFF and the idle bus reads back the
; same byte every time. So count byte-to-byte changes over $C000-$C0FF.
detect	ldx #0
	ldy #0
	lda $C000
dt_lp	cmp $C000,x
	beq dt_same
	iny
	lda $C000,x
dt_same	inx
	bne dt_lp
	cpy #32
	lda #0
	bcc dt_set
	lda #1
dt_set	sta MACHINE
	lda PAL			; bits 1-3 are 0 on PAL
	and #$0E
	bne dt_x
	inc ISPAL
dt_x	rts

; ---------------------------------------------------------------------------
; Display prerequisites. DISPOK needs all of:
;   VCOUNT sweeps the frame (ANTIC is generating lines),
;   a 1K screen block passes the march test.
; The character ROM sum is only shown: the video check screen is the real
; font test, and the sum identifies the ROM once we have a table.
dprereq	lda #$FF
	sta VCMIN
	ldx #0			; ~65K samples, about 40 frames
	ldy #0
dp_vc	lda VCOUNT
	cmp VCMIN
	bcs dp_v1
	sta VCMIN
dp_v1	cmp VCMAX
	bcc dp_v2
	sta VCMAX
dp_v2	dex
	bne dp_vc
	dey
	bne dp_vc

	jsr fontsum		; read the font twice: a flaky ROM or bus differs
	lda SUM
	sta CHSUM
	lda SUM+1
	sta CHSUM+1
	jsr fontsum
	lda SUM
	cmp CHSUM
	bne dp_scr
	lda SUM+1
	cmp CHSUM+1
	bne dp_scr
	inc CHSTAB

dp_scr	jsr findscr
	lda VCMIN
	cmp #10
	bcs dp_x
	lda VCMAX
	cmp #100		; NTSC peaks at 130, PAL at 155
	bcc dp_x
	lda SCRPG
	beq dp_x
	inc DISPOK
dp_x	rts

; fontsum: SUM = 16-bit sum of the ROM font, $E000-$E3FF.
fontsum	lda #0
	sta SUM
	sta SUM+1
	sta PTR
	lda #$E0
	sta PTR+1
	ldy #0
cs_lp	lda (PTR),y
	clc
	adc SUM
	sta SUM
	bcc cs_nc
	inc SUM+1
cs_nc	iny
	bne cs_lp
	inc PTR+1
	lda PTR+1
	cmp #$E4
	bne cs_lp
	rts

; findscr: SCRPG = the first candidate 1K block that is present and passes
; the march test; 0 if none. Errors found here count against the bank.
findscr	ldx #0
fs_lp	stx CNT
	lda scrcand,x
	clc
	adc #4
	cmp RAMTOP
	beq fs_in
	bcs fs_next		; block runs past the end of RAM
fs_in	lda scrcand,x
	sta RNGS
	clc
	adc #4
	sta RNGE
	lda #1
	sta RNGN
	lda scrcand,x
	jsr pagebank
	sta CURBANK
	.ifndef QUICKSCR
	jsr setfmask
	.endif
	ldx CURBANK
	lda ECNTLO,x
	sta SCRERR
	lda ECNTHI,x
	sta SCRERR+1
	.if .def QUICKSCR
	jsr qscr
	.else
	jsr march2
	.endif
	ldx CURBANK
	lda ECNTLO,x
	cmp SCRERR
	bne fs_next
	lda ECNTHI,x
	cmp SCRERR+1
	bne fs_next
	ldx CNT
	lda scrcand,x
	sta SCRPG
	rts
fs_next	ldx CNT
	inx
	cpx #4
	bne fs_lp
	rts

; Candidates: just above the stage (fits an 8K 400), then the top 1K of
; each 16K bank.
SCR1	= [TSTART+3]&$FC
	.ifdef ONELOAD
scrcand	.byte SCR1, $BC, $BC, $BC	; $3C holds the BSS page, $7C the image
	.else
scrcand	.byte SCR1, $3C, $7C, $BC
	.endif
	.if .def ONELOAD		; the 48k+ tape: a 48K machine
	.if SCR1+4>$C0
	.error "stage too big: no screen block fits in 48K"
	.endif
	.elseif .def BOUNCE		; the 16K+ burn-in: it checks the room for
					; copy B itself, as it runs
	.elseif .def BIGSTAGE		; the 16k system tape: 16K
	.if SCR1+4>$40
	.error "stage too big: no screen block fits in 16K"
	.endif
	.else
	.if SCR1+4>$20
	.error "stage too big: no screen block fits in 8K"
	.endif
	.endif

	.if .def QUICKSCR
; qscr: the quick screen-block test for a tape that doesn't test RAM (tape 1
; has): $55, $AA, $00, $FF written to each byte of RNGS..RNGE and read back.
; A miss counts an error against CURBANK, as findscr expects.
qscr	lda #0
	sta PTR
	lda RNGS
	sta PTR+1
	ldy #0
qs_by	ldx #3
qs_pat	lda qspats,x
	sta (PTR),y
	cmp (PTR),y
	beq qs_ok
	stx MTMP
	ldx CURBANK
	inc ECNTLO,x
	ldx MTMP
qs_ok	dex
	bpl qs_pat
	iny
	bne qs_by
	inc PTR+1
	lda PTR+1
	cmp RNGE
	bne qs_by
	rts
qspats	.byte $55, $AA, $00, $FF

; popcnt: X = number of set bits in A (ramtest.asm has it otherwise).
popcnt	ldx #0
pc_lp	cmp #0
	beq pc_x
	lsr
	bcc pc_lp
	inx
	bcs pc_lp
pc_x	rts

; pagebank: A = page -> A = bank 1-4 (ramtest.asm has it otherwise).
pagebank rol
	rol
	rol
	and #3
	clc
	adc #1
	rts
	.endif
