; Boot sequence shared by the boot stages: alive, image checksum, low RAM
; test, then (with the stack allowed) the RAM size probe. Included straight
; after the cassette boot header; falls through to the stage's code at the
; end, with RAMTOP set. Needs LOAD, IMGEND, CKSUM, BSS from the stage.
; LRCALL: lowram may also be called with JSR once STACKOK is set; it then
; returns (errors are charged to bank 1 as at boot).

; ---------------------------------------------------------------------------
; Nothing below may use the stack or zero page until low RAM passes.
entry	sei
	cld
	lda #0
	sta NMIEN
	sta IRQEN
	sta DMACTL		; ANTIC off: GTIA shows COLBK on the whole screen
	sta AUDCTL
	sta SKCTL		; reset POKEY's serial state from the tape load
	lda #3
	sta SKCTL
	lda #AUD_OFF
	sta AUDC1
	sta AUDC1+2
	sta AUDC1+4
	sta AUDC1+6
	lda #$3C
	sta PACTL		; cassette motor off
	lda #$08
	sta CONSOL

	ldx #0			; clear BSS (absolute,X: no zero page needed)
	txa
clr	sta BSS,x
	inx
	bne clr
	lda #$08
	sta SPKPH

	; Alive: green and a rising chirp.
	lda #C_GREEN
	sta COLBK
	lda #AUD_ON
	sta AUDC1
	ldx #80
ch_step	stx AUDF1
	ldy #40
ch_line	sta WSYNC
	dey
	bne ch_line
	dex
	cpx #20
	bne ch_step
	lda #AUD_OFF
	sta AUDC1

	lda #C_YELLOW
	sta COLBK

; ---------------------------------------------------------------------------
; Image checksum. The OS checks each record in the cassette buffer, but not
; the copy to LOAD, so the copy is verified here. 16-bit sum of every image
; byte except the stored sum. The page operand of ck_op changes as the loop
; runs; mkcas.py allows for that.
	lda #>LOAD
	sta ck_op+2
	ldx #0
ck_lp
ck_op	lda LOAD,x
	clc
	adc SUM
	sta SUM
	bcc ck_nc
	inc SUM+1
ck_nc	inx
	bne ck_lp
	inc ck_op+2
	lda ck_op+2
	cmp #>IMGEND
	bne ck_lp
	; take the two stored-sum bytes back out
	sec
	lda SUM
	sbc CKSUM
	sta SUM
	bcs ck_s1
	dec SUM+1
ck_s1	sec
	lda SUM
	sbc CKSUM+1
	sta SUM
	bcs ck_s2
	dec SUM+1
ck_s2	lda SUM
	cmp CKSUM
	bne ck_bad
	lda SUM+1
	cmp CKSUM+1
	beq lowram
ck_bad	inc LOADERR
	jmp report

; ---------------------------------------------------------------------------
; Low RAM, $0000-$07FF: zero page, stack, OS variables, cassette buffer.
; Non-destructive: each byte is saved, hit with every pattern, restored.
; Bytes are tested one at a time, so this finds stuck and shorted bits, not
; address faults; the march and address tests in main RAM cover those.
; The page operands of lr_a..lr_d walk $00-$07.
lowram	lda #0
	sta lr_a+2
	sta lr_b+2
	sta lr_c+2
	sta lr_d+2
	tax
lr_byte
lr_a	lda $FF00,x		; page set at run time; $FF00 forces absolute,X
	sta MTMP
	ldy #NPAT-1
lr_pat	lda pats,y
lr_b	sta $FF00,x
lr_c	eor $FF00,x		; A = bits that came back wrong
	.if FAULT_BANK=0
	eor #FAULT_MASK
	.endif
	beq lr_ok
	sta LXOR
	ora BADMASK+1		; low RAM is in bank 1
	sta BADMASK+1
	lda ECNTLO+1
	ora ECNTHI+1
	bne lr_cnt
	stx EADRLO+1		; first error only
	lda lr_a+2
	sta EADRHI+1
	lda pats,y
	sta EWROTE+1
	eor LXOR
	sta EREAD+1
lr_cnt	inc ECNTLO+1
	bne lr_ok
	inc ECNTHI+1
lr_ok	dey
	bpl lr_pat
	lda MTMP
lr_d	sta $FF00,x
	inx
	bne lr_byte
	inc lr_a+2
	inc lr_b+2
	inc lr_c+2
	inc lr_d+2
	lda lr_a+2
	cmp #8
	bne lr_byte

	.if .def LRCALL
	lda STACKOK		; called again later (burn-in): just return
	beq lr_boot
	rts
lr_boot
	.endif
	lda BADMASK+1
	beq lr_pass
	jmp report		; still no stack: report needs none

; ---------------------------------------------------------------------------
; Low RAM is good: from here on, the stack and zero page are allowed.
lr_pass	ldx #$FF
	txs
	inc STACKOK

; RAM size. One probe per 4K block from $2000 (the stage itself loaded below
; $2000, and every machine has 8K). A block counts as RAM if $A5 and $5A
; come back with 4 or fewer wrong bits in total. A floating bus reads back
; the same byte for both, so it is wrong in exactly 8 bits; this way a block
; with a few dead bits is still found and tested, not taken for missing.
	lda #$20
	sta RAMTOP
	lda #0
	sta PTR
	tay
pr_lp	lda RAMTOP
	cmp #$C0		; $C000 up is ROM or I/O on every model
	beq pr_done
	sta PTR+1
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
	bcs pr_done
	lda RAMTOP
	clc
	adc #$10
	sta RAMTOP
	bne pr_lp
pr_done
