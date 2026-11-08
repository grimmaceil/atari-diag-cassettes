; Next-stage loader, shared by the multi-stage tapes. Needs from the stage:
; results (redraws its text screen with the L2MSG line), final (the final
; result), the s_l2* strings, s_l2load. NORAMCHK: don't require RAM test
; results for banks 1-2 (tape 3 has none; its BADMASK holds test results).

; ---------------------------------------------------------------------------
; Stage 2: the next file on the tape, after this file's EOF record (which
; the OS boot reads and discards). It is read with the OS's SIO exactly the
; way the OS read this stage (cassette, short record gaps), so the OS
; interrupt handlers must run while it loads: VBI for SIO's gap and timeout
; timers, IRQ for the serial input. Low RAM, where the OS keeps its state,
; has passed and was restored, so that is safe now.
; It loads at LDTO, into RAM this stage has just tested: $2000 (bank 1) for
; tape 1's stage 2 (the 400 tape).
	.ifndef LDTO
LDTO	= $2000
	.endif
DDEVIC	= $0300		; SIO device control block, $0300-$030B
SIOV	= $E459
CASBUF	= $03FD		; record as read: $55 $55, type, 128 data bytes
CASDAT	= CASBUF+3
SDMCTL	= $022F		; OS shadows the VBI copies to the chips
SDLSTL	= $0230
CHACT	= $02F3
CHBAS	= $02F4
COLOR1	= $02C5
COLOR2	= $02C6
COLOR4	= $02C8
ATRACT	= $4D

load2	lda #0			; from here on a result is final
	sta CONTVEC+1
	lda RAMTOP
	cmp #>LDTO+$20	; the next stage needs 8K from LDTO
	bcs l2_ram
	lda #<s_l2_8k
	ldy #>s_l2_8k
	jmp l2_fail
l2_ram
	.ifndef NORAMCHK
	lda BADMASK+1
	beq l2_go
	.else
	jmp l2_go
	.endif
	lda #<s_l2_bad
	ldy #>s_l2_bad
	jmp l2_fail

l2_go	lda SCRON
	beq l2_os
	lda #22
	jsr clrrow
	lda #23
	jsr clrrow
	PRINT 22, 0, s_l2load
l2_os	lda SCRON		; keep the screen as it is while the VBI runs
	beq l2_dma
	lda #$22
l2_dma	sta SDMCTL
	lda #<SCRDL
	sta SDLSTL
	lda SCRPG
	clc
	adc #>SCRDL
	sta SDLSTL+1
	lda #$E0
	sta CHBAS
	lda #2
	sta CHACT
	lda #C_TEXTLUM
	sta COLOR1
	lda #C_TEXTBG
	sta COLOR2
	lda #C_YELLOW
	sta COLOR4
	lda #0
	sta ATRACT
	lda #$40		; VBI on
	sta NMIEN
	cli

	lda #<LDTO
	sta PTR
	lda #>LDTO
	sta PTR+1
	jsr rdrec		; first record: the stage 2 header
	.ifdef SKIPEOF
	bcc l2_hd		; SKIPEOF: this stage was loaded by a loader, not
	cmp #1			; the OS, so its own EOF record is still ahead
	bne l2_sio
	jsr rdrec
l2_hd
	.endif
	bcs l2_sio
	lda CASDAT+2		; load address must be LDTO
	cmp #<LDTO
	bne l2_hdr
	lda CASDAT+3
	cmp #>LDTO
	bne l2_hdr
	lda CASDAT+1		; records: even (whole pages), not zero
	beq l2_hdr
	sta S2LEFT
	lsr
	bcs l2_hdr
	sta S2PAGES
	clc			; its end page, plus a page of BSS
	adc #>LDTO+1
	cmp RAMTOP
	beq l2_fits
	bcs l2_big
l2_fits
	.ifndef NORAMCHK
	cmp #$41		; reaches into bank 2?
	bcc l2_copy
	lda BADMASK+2
	bne l2_big
	.endif

l2_copy	ldy #127
l2_cp	lda CASDAT,y
	sta (PTR),y
	dey
	bpl l2_cp
	lda PTR
	eor #$80
	sta PTR
	bne l2_next
	inc PTR+1
l2_next	dec S2LEFT
	beq l2_done
	jsr rdrec
	bcs l2_sio
	jmp l2_copy

l2_done	jsr l2stop
	jsr s2sum
	bne l2_bsum
	jmp LDTO+6

l2_big	lda #<s_l2_big
	ldy #>s_l2_big
	jmp l2_fail
l2_bsum	lda #<s_l2_sum
	ldy #>s_l2_sum
	jmp l2_fail

; A read error or the wrong file is worth another try: a player that does
; not stop when the motor does (AspeQt, a deck without motor control) has
; run past stage 2 or isn't at it yet. START (or the pass) retries.
l2_sio	sta L2STAT
	lda #<s_l2_sio
	ldy #>s_l2_sio
	bne l2_retry
l2_hdr	lda #<s_l2_hdr
	ldy #>s_l2_hdr
l2_retry ldx #<load2
	stx CONTVEC
	ldx #>load2
	stx CONTVEC+1

; l2_fail: A/Y = why stage 2 didn't run. Final unless l2_retry set CONTVEC.
l2_fail	sta L2MSG
	sty L2MSG+1
	jsr l2stop
	lda SCRON
	beq l2_end
	jsr results
l2_end	jmp final

; rdrec: read the next tape record into CASBUF, as the OS's RBLOK does.
; C clear if it read a data record; else C set, A = SIO status (1 = fine
; but not a data record).
rdrec	ldx #11
rr_dcb	lda dcbtab,x
	sta DDEVIC,x
	dex
	bpl rr_dcb
	jsr SIOV
	tya
	bmi rr_err
	lda CASBUF+2
	cmp #$FC		; full data record
	bne rr_type
	clc
	rts
rr_type	lda #1
rr_err	sec
	rts

; The DCB, $0300-$030B: cassette, unit 0, read ('R', status $40) 131 bytes
; into CASBUF, 35 s timeout, short gaps (DAUX2 bit 7: the motor stays on
; between records), as the OS's RBLOK sets it up for the boot.
dcbtab	.byte $60, 0, 'R', $40
	.word CASBUF
	.byte 35, 0
	.word 131
	.byte 0, $80

; l2stop: back to how this stage runs: no interrupts, motor off, POKEY
; reset from serial mode, sound off.
l2stop	sei
	lda #0
	sta NMIEN
	sta IRQEN
	sta AUDCTL
	sta SKCTL
	lda #3
	sta SKCTL
	lda #$3C
	sta PACTL
	lda #AUD_OFF
	sta AUDC1
	sta AUDC1+2
	sta AUDC1+4
	sta AUDC1+6
	rts

; s2sum: Z set if the 16-bit sum of the stage 2 image, less its last two
; bytes, matches those two bytes.
s2sum	lda #0
	sta SUM
	sta SUM+1
	sta PTR
	lda #>LDTO
	sta PTR+1
	ldx S2PAGES
	ldy #0
s2_lp	lda (PTR),y
	clc
	adc SUM
	sta SUM
	bcc s2_nc
	inc SUM+1
s2_nc	iny
	bne s2_lp
	inc PTR+1
	dex
	bne s2_lp
	dec PTR+1		; PTR -> last page; take its last two bytes back out
	ldy #$FE
	jsr s2_sub
	iny
	jsr s2_sub
	ldy #$FE
	lda (PTR),y
	cmp SUM
	bne s2_x
	iny
	lda (PTR),y
	cmp SUM+1
s2_x	rts
s2_sub	sec
	lda SUM
	sbc (PTR),y
	sta SUM
	bcs s2_sb
	dec SUM+1
s2_sb	rts



