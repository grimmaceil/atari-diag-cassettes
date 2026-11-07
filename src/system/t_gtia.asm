; Test 7: GTIA by eye. Eight luminance steps and sixteen hues, drawn by
; changing COLPF2 down the screen with WSYNC (no interrupts). The video
; standard is shown. Item 1: the user says the ramps look wrong (or no
; answer in 30 s).
GL_ROW	= 5			; first text row of the luminance ramp
GH_ROW	= 13			; first text row of the hue ramp
t_gtia	lda #7
	sta TEST
	lda #<s_t7
	ldy #>s_t7
	jsr tpage
	lda DISPOK
	beq gt_g
	PRINT 4, 0, s_glum
	PRINT 12, 0, s_ghue
	PRINT 21, 0, s_gq
	lda #<s_vntsc
	ldy #>s_vntsc
	ldx ISPAL
	beq gt_v
	lda #<s_vpal
	ldy #>s_vpal
gt_v	pha
	tya
	pha
	lda #3
	ldx #0
	jsr at
	pla
	tay
	pla
	jsr puts
gt_g	jsr waitrel
gt_lp	lda VCOUNT		; luminance: 8 steps of 7 lines, rows 5-11 (8 of 8
	cmp #[32+GL_ROW*8]/2-1	; ran into row 12's label). VCOUNT counts line
	bne gt_lp		; pairs: start a pair early, end inside row 11
	ldx #0
gt_l	txa
	asl
	sta WSYNC
	sta COLPF2
	ldy #6
gt_l1	sta WSYNC
	dey
	bne gt_l1
	inx
	cpx #8
	bne gt_l
	lda #C_TEXTBG		; (in the horizontal blank after the last WSYNC)
	sta COLPF2
gt_w	lda VCOUNT		; hue: 16 steps of 4 lines, rows 13-20
	cmp #[32+GH_ROW*8]/2-1
	bne gt_w
	ldx #0
gt_h	txa
	asl
	asl
	asl
	asl
	ora #8
	sta WSYNC
	sta COLPF2
	ldy #3
gt_h1	sta WSYNC
	dey
	bne gt_h1
	inx
	cpx #16
	bne gt_h
	lda #C_TEXTBG
	sta COLPF2
	lda SKSTAT		; the answer, polled once a frame
	and #4
	bne gt_c
	lda KBCODE
	and #$3F
	cmp #$2B		; Y
	beq gt_yes
	cmp #$23		; N
	beq gt_no
gt_c	lda CONSOL
	lsr
	bcc gt_yes
	lsr
	bcc gt_no
	jmp gt_lp
gt_no	lda #1
	sta BADMASK+7
gt_yes	jsr waitrel
	lda DISPOK
	beq gt_end
	lda #21
	jsr clrrow
gt_end	jmp tend

s_glum	dta d'LUMINANCE: 8 EVEN STEPS, BLACK TO WHITE',$FF
s_ghue	dta d'HUES: 16 DIFFERENT COLORS',$FF
s_gq	dta d'RAMPS RIGHT? Y/START=YES, N/SELECT=NO',$FF
s_vpal	dta d'VIDEO: PAL ',$FF
s_vntsc	dta d'VIDEO: NTSC',$FF
