; RAM test engine: March C- and address-in-address over a range list,
; with errors charged per bank (see vars.asm for the result arrays).
; Needs the stack and zero page (PTR).

; pagebank: A = page -> A = bank 1-4.
pagebank rol
	rol
	rol
	and #3
	clc
	adc #1
	rts

; split: range list RNG* = [RBS, RBE) minus the screen block.
split	ldx #0
	lda SCRPG
	beq sp_all
	cmp RBE
	bcs sp_all		; block starts at or past the end
	clc
	adc #4
	cmp RBS
	beq sp_all
	bcc sp_all		; block ends at or before the start
	lda RBS
	cmp SCRPG
	bcs sp_hi
	sta RNGS		; part below the block
	lda SCRPG
	sta RNGE
	inx
sp_hi	lda SCRPG
	clc
	adc #4
	cmp RBE
	bcs sp_x
	sta RNGS,x		; part above the block
	lda RBE
	sta RNGE,x
	inx
sp_x	stx RNGN
	rts
sp_all	lda RBS
	sta RNGS
	lda RBE
	sta RNGE
	inx
	stx RNGN
	rts

; march2: March C- with $00/$FF, then (unless FAST) $55/$AA.
march2	lda #$00
	sta P0
	lda #$FF
	sta P1
	jsr march
	.if FAST=0
	lda #$55
	sta P0
	lda #$AA
	sta P1
	jsr march
	.endif
	rts

; March C- over the range list, background P0, inverse P1:
;   up(w0) up(r0,w1) up(r1,w0) down(r0,w1) down(r1,w0) up(r0)
march	lda #$40		; write only
	sta MFLAGS
	lda P0
	sta MWRITE
	jsr elem_up
	lda #0
	sta MFLAGS
	lda P0
	sta MREAD
	lda P1
	sta MWRITE
	jsr elem_up
	lda P1
	sta MREAD
	lda P0
	sta MWRITE
	jsr elem_up
	lda P0
	sta MREAD
	lda P1
	sta MWRITE
	jsr elem_dn
	lda P1
	sta MREAD
	lda P0
	sta MWRITE
	jsr elem_dn
	lda #$80		; read only
	sta MFLAGS
	lda P0
	sta MREAD
	jmp elem_up

; One march element over every range: ascending in order, descending in
; reverse order, so the element runs over the union as one sweep.
elem_up	ldx #0
eu_lp	cpx RNGN
	beq eu_x
	lda RNGS,x
	sta MSTART
	lda RNGE,x
	sta MEND
	txa
	pha
	jsr m_up
	pla
	tax
	inx
	bne eu_lp
eu_x	rts

elem_dn	ldx RNGN
ed_lp	dex
	bmi ed_x
	lda RNGS,x
	sta MSTART
	lda RNGE,x
	sta MEND
	txa
	pha
	jsr m_dn
	pla
	tax
	jmp ed_lp
ed_x	rts

; m_up: pages [MSTART, MEND) ascending: read and check MREAD, then write
; MWRITE (MFLAGS bit 6 skips the read, bit 7 the write).
m_up	lda #0
	sta PTR
	lda MSTART
	sta PTR+1
	ldy #0
mu_by	bit MFLAGS
	bvs mu_w
	lda (PTR),y
	FAULTINJ
	cmp MREAD
	beq mu_w
	jsr merr
mu_w	bit MFLAGS
	bmi mu_nx
	lda MWRITE
	sta (PTR),y
mu_nx	iny
	bne mu_by
	inc PTR+1
	lda PTR+1
	cmp MEND
	bne mu_by
	rts

; m_dn: the same, descending.
m_dn	lda #0
	sta PTR
	lda MEND
	sta PTR+1
md_pg	dec PTR+1
	ldy #$FF
md_by	bit MFLAGS
	bvs md_w
	lda (PTR),y
	FAULTINJ
	cmp MREAD
	beq md_w
	jsr merr
md_w	bit MFLAGS
	bmi md_nx
	lda MWRITE
	sta (PTR),y
md_nx	dey
	cpy #$FF
	bne md_by
	lda PTR+1
	cmp MSTART
	bne md_pg
	rts

; Address-in-address over the range list: every byte gets the low
; (AIAMODE=0) or high (1) byte of its own address, then all are checked.
; Low bytes catch A0-A7 faults, high bytes A8-A15 and bank mirroring. All
; ranges are written before any is checked. Errors are charged to the bank
; the bad byte is in.
aia	ldx #0
aw_r	cpx RNGN
	beq ac_go
	lda RNGS,x
	sta MSTART
	lda RNGE,x
	sta MEND
	txa
	pha
	jsr aia_w
	pla
	tax
	inx
	bne aw_r
ac_go	ldx #0
ac_r	cpx RNGN
	beq aia_x
	lda RNGS,x
	sta MSTART
	lda RNGE,x
	sta MEND
	txa
	pha
	jsr aia_c
	pla
	tax
	inx
	bne ac_r
aia_x	rts

aia_w	lda #0
	sta PTR
	lda MSTART
	sta PTR+1
	ldy #0
aw_by	jsr aia_val
	sta (PTR),y
	iny
	bne aw_by
	inc PTR+1
	lda PTR+1
	cmp MEND
	bne aw_by
	rts

aia_c	lda #0
	sta PTR
	lda MSTART
	sta PTR+1
	ldy #0
ac_pg	lda BANKOVR
	bne ac_bk
	lda PTR+1
	jsr pagebank
ac_bk	sta CURBANK
	jsr setfmask
ac_by	jsr aia_val
	sta MREAD
	lda (PTR),y
	FAULTINJ
	cmp MREAD
	beq ac_ok
	jsr merr
ac_ok	iny
	bne ac_by
	inc PTR+1
	lda PTR+1
	cmp MEND
	bne ac_pg
	rts

aia_val	lda AIAMODE
	bne av_hi
	tya
	rts
av_hi	lda PTR+1
	rts

; merr: A = value read, MREAD = expected, at (PTR),Y. Charge it to CURBANK,
; to MBAD or AIABAD depending on which test is running. Keeps Y.
merr	sta MTMP
	eor MREAD
	sta LXOR
	ldx CURBANK
	ora BADMASK,x
	sta BADMASK,x
	lda INAIA
	bne me_aia
	lda LXOR
	ora MBAD,x
	sta MBAD,x
	jmp me_first
me_aia	lda LXOR
	ora AIABAD,x
	sta AIABAD,x
me_first lda ECNTLO,x
	ora ECNTHI,x
	bne me_cnt
	tya			; first error: where, and what
	sta EADRLO,x
	lda PTR+1
	sta EADRHI,x
	lda MREAD
	sta EWROTE,x
	lda MTMP
	sta EREAD,x
me_cnt	inc ECNTLO,x
	bne me_x
	inc ECNTHI,x
	bne me_x
	dec ECNTLO,x		; saturate at $FFFF
	dec ECNTHI,x
me_x	rts

; setfmask: FMASK = FAULT_MASK if CURBANK is the fault bank, else 0.
setfmask
	lda #0
	.if FAULT_BANK>0
	ldx CURBANK
	cpx #FAULT_BANK
	bne sf_x
	lda #FAULT_MASK
	.if .def FAULT_EVERY
	.if .def BURNIN
	ldx FAULTON		; only on some passes (burn-in): intermittent
	bne sf_x
	lda #0
	.endif
	.endif
sf_x
	.endif
	sta FMASK
	rts

; popcnt: X = number of set bits in A.
popcnt	ldx #0
pc_lp	cmp #0
	beq pc_x
	lsr
	bcc pc_lp
	inx
	bcs pc_lp
pc_x	rts
