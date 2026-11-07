; Machine/display info lines, shared by the text screens.

; machinfo: "MACHINE 400/800  RAM 48K  NTSC" on row A.
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
	lda RAMTOP		; pages / 4 = K
	lsr
	lsr
	sta DVAL
	lda #0
	sta DVAL+1
	jsr putdec
	lda ISPAL
	beq mi_n
	lda #<s_pal
	ldy #>s_pal
	jmp puts
mi_n	lda #<s_ntsc
	ldy #>s_ntsc
	jmp puts

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


s_800	dta d'MACHINE 400/800',$FF
s_xl	dta d'MACHINE XL/XE',$FF
s_ram	dta d'  RAM ',$FF
s_pal	dta d'K  PAL',$FF
s_ntsc	dta d'K  NTSC',$FF
s_chrom	dta d'CHAR ROM $',$FF
s_unstab dta d' UNSTABLE',$FF
s_scr	dta d'  SCREEN $',$FF

