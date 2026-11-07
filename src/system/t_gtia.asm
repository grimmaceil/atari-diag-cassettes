; Test 7: GTIA by eye.
;   item 1: eight luminance steps and sixteen hues, drawn by changing COLPF2
;           down the screen with WSYNC (no interrupts), look wrong. The
;           video standard is shown.
;   item 2: the sprites look wrong: the word ATARI in players and missiles,
;           scrolling across in rainbow colors (see gsprite).
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
	jsr gsprite
gt_end	jmp tend

; ---------------------------------------------------------------------------
; gsprite: item 2, players and missiles. The word ATARI from the ROM font:
; players 0-3 are A T A R, and the four missiles side by side make the I as
; a fifth player (PRIOR bit 4: they take COLPF3's color). All double width,
; scrolling across one color clock a frame. A display-list interrupt on the
; text line above them changes their color on every scan line, the rainbow
; moving a step each frame. (DLI only: the OS VBI stays off, so nothing
; rewrites the hardware from the OS shadows.)
GPX	= TSCR+$00		; the word's left edge, color clocks
GBASE	= TSCR+$01		; the rainbow's first color, 0-15
GDLN	= TSCR+$02		; DLI: scan lines left
GPM	= $04			; P/M block: missiles $0580, players $0600-$07FF
GROW	= 10			; text rows 10-11: the letters (8 bytes, 2 lines each)
GY	= 16+GROW*4		; P/M byte of row GROW (double-line)
VDSLST	= $0200			; the OS NMI handler jumps here on a DLI
gsprite	ldx #4			; a plain page from row 4 down
gs_clr	txa
	pha
	jsr clrrow
	pla
	tax
	inx
	cpx #24
	bne gs_clr
	PRINT 4, 0, s_gs1
	PRINT 21, 0, s_gs2
	lda #0
	tay
gs_pm	sta GPM*$100+$100,y	; the P/M block clear
	sta GPM*$100+$200,y
	sta GPM*$100+$300,y
	iny
	bne gs_pm
	ldx #4			; the letters from the ROM font
gs_let	lda #0
	sta PTR+1
	lda gcodes,x		; font + code*8
	asl
	rol PTR+1
	asl
	rol PTR+1
	asl
	rol PTR+1
	sta PTR
	lda PTR+1
	ora #$E0
	sta PTR+1
	lda gdestl,x
	sta SPTR
	lda gdesth,x
	sta SPTR+1
	ldy #7
gs_cp	lda (PTR),y
	sta (SPTR),y
	dey
	bpl gs_cp
	dex
	bpl gs_let
	ldx #3
gs_sz	lda #1			; players double width
	sta SIZEP0,x
	dex
	bpl gs_sz
	lda #$55		; missiles too
	sta SIZEM
	lda #$11		; players in front, missiles as a fifth player
	sta PRIOR
	lda #GPM
	sta PMBASE
	lda #$2E		; + player and missile DMA, double-line
	sta DMACTL
	lda #3
	sta GRACTL
	lda #0
	sta GPX
	sta GBASE
	lda #<gdli		; the DLI, on row GROW-1's display-list byte
	sta VDSLST
	lda #>gdli
	sta VDSLST+1
	jsr gdlbyte
	ora #$80
	sta (PTR),y
	lda #$80
	sta NMIEN
	jsr waitrel
gs_lp	jsr vsync		; each frame: one step across, one rainbow step
	inc GPX
	lda GPX
	ldx #0
gs_hp	sta HPOSP0,x		; P0-P3, 20 color clocks apart
	clc
	adc #20
	inx
	cpx #4
	bne gs_hp
	sta HPOSP0+7		; the I: M3 (left) to M0, 4 apart
	clc
	adc #4
	sta HPOSP0+6
	adc #4
	sta HPOSP0+5
	adc #4
	sta HPOSP0+4
	lda GBASE
	clc
	adc #1
	and #15
	sta GBASE
	lda SKSTAT		; the answer
	and #4
	bne gs_c
	lda KBCODE
	and #$3F
	cmp #$2B		; Y
	beq gs_yes
	cmp #$23		; N
	beq gs_no
gs_c	lda CONSOL
	lsr
	bcc gs_yes
	lsr
	bcc gs_no
	jmp gs_lp
gs_no	lda #2
	ora BADMASK+7
	sta BADMASK+7
gs_yes	lda #0			; all off again
	sta NMIEN
	sta GRACTL
	sta PRIOR
	ldx #$11		; positions, sizes, graphics latches
gs_off	sta HPOSP0,x
	dex
	bpl gs_off
	jsr gdlbyte
	and #$7F
	sta (PTR),y
	lda #$22
	sta DMACTL
	jsr waitrel
	lda #21
	jmp clrrow

; gdlbyte: PTR/Y -> row GROW-1's display-list byte, A = it.
gdlbyte	lda #<SCRDL
	sta PTR
	lda SCRPG
	clc
	adc #>SCRDL
	sta PTR+1
	ldy #5+GROW-1		; 3 blank-line bytes, LMS row 0 (3), then a byte a row
	lda (PTR),y
	rts

; gdli: the rainbow, one color a scan line for the 16 lines of the letters.
gdli	pha
	txa
	pha
	lda #16
	sta GDLN
	ldx GBASE
gd_lp	lda grain,x
	sta WSYNC
	sta COLPM0
	sta COLPM0+1
	sta COLPM0+2
	sta COLPM0+3
	sta COLPF3
	inx
	dec GDLN
	bne gd_lp
	pla
	tax
	pla
	rti

gcodes	.byte $21, $34, $21, $32, $29	; A T A R I (screen codes)
gdestl	.byte <[GPM*$100+$200+GY], <[GPM*$100+$280+GY], <[GPM*$100+$300+GY]
	.byte <[GPM*$100+$380+GY], <[GPM*$100+$180+GY]
gdesth	.byte >[GPM*$100+$200+GY], >[GPM*$100+$280+GY], >[GPM*$100+$300+GY]
	.byte >[GPM*$100+$380+GY], >[GPM*$100+$180+GY]
grain	:2 .byte $18, $28, $38, $48, $58, $68, $78, $88, $98, $A8, $B8, $C8, $D8, $E8, $F8, $08

s_glum	dta d'LUMINANCE: 8 EVEN STEPS, BLACK TO WHITE',$FF
s_ghue	dta d'HUES: 16 DIFFERENT COLORS',$FF
s_gq	dta d'RAMPS RIGHT? Y/START=YES, N/SELECT=NO',$FF
s_vpal	dta d'VIDEO: PAL ',$FF
s_vntsc	dta d'VIDEO: NTSC',$FF
s_gs1	dta d'SPRITES: ATARI SHOULD SCROLL ACROSS',$FF
s_gs2	dta d'IN RAINBOW? Y/START=YES, N/SELECT=NO',$FF
