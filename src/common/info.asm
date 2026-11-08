; Machine/display info lines, shared by the text screens.

; machinfo: "FOUND: 400/800  RAM 16K  NTSC" on row A.
machinfo ldx #0
	jsr at
	lda MACHINE
	beq mi_8
	lda #<s_xl
	ldy #>s_xl
	bne mi_p
mi_8	lda #<s_800
	ldy #>s_800
mi_p	jsr puts
	lda #<s_ram
	ldy #>s_ram
	jsr puts
	lda RAMK		; all of it, in K (boot.asm)
	sta DVAL
	lda #0
	sta DVAL+1
	jsr putdec
	lda ISPAL
	beq mi_n
	lda #<s_pal
	ldy #>s_pal
	bne mi_v
mi_n	lda #<s_ntsc
	ldy #>s_ntsc
mi_v	jsr puts
	lda RAMTOP		; a cartridge, the way the OS tells: RAM ends
	cmp #$C0		; below $C000 and $BFFC holds 0. Its 8K of RAM
	bcs mi_x		; at $A000 isn't tested: remove it for a full test
	lda $BFFC
	bne mi_x
	lda #<s_cartin
	ldy #>s_cartin
	jmp puts
mi_x	rts

; chinfo: "CHAR ROM $xxxx  SCREEN $xx00" on row A.
chinfo	ldx #0
	jsr at
	lda #<s_chrom
	ldy #>s_chrom
	jsr puts
	lda CHSUM+1
	jsr puthex
	lda CHSUM
	jsr puthex
	lda CHSTAB
	bne ci_s
	lda #<s_unstab
	ldy #>s_unstab
	jsr puts
ci_s	lda #<s_scr
	ldy #>s_scr
	jsr puts
	lda SCRPG
	jsr puthex
	lda #0
	jmp puthex


s_800	dta d'FOUND: 400/800',$FF	; what the tape detected
s_xl	dta d'FOUND: XL/XE',$FF
s_ram	dta d'  RAM ',$FF
s_pal	dta d'K  PAL',$FF
s_ntsc	dta d'K  NTSC',$FF
s_cartin dta d'  CART IN'*,$FF
s_chrom	dta d'CHAR ROM $',$FF
s_unstab dta d' UNSTABLE',$FF
s_scr	dta d'  SCREEN $',$FF

