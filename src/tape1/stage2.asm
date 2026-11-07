; A8 DIAG tape 1, stage 2. Loaded by stage 1 (with the OS's SIO) at S2LOAD,
; in bank 1 RAM stage 1 has just tested, and entered at S2LOAD+6 with
; interrupts off. Stage 1's results come over in its BSS page.
;
;   relocate test   the loader area, $0800 up to stage 1's TSTART: stage 1's
;                   own code and BSS, which stage 1 could not test
;   under the OS    XL/XE: the RAM behind the OS ROM ($C000-$CFFF and
;                   $D800-$FFFF; $D000-$D7FF is always I/O), as bank 4
;   130XE banks     the four extended 16K banks, as banks 5-8
;   summary         every test on the tape, with the first failure's detail
;
; Then the final code: the loader area counts as bank 1 for the beeps.
; Built with -d:S1BSS=... -d:S1TSTART=... from stage 1's label table.
;
; CHAIN3 (the 48k tape): then stage 3, the system tests, loads at $4000 if
; the RAM it needs passed (banks 1 and 2: the loader checks). All passed:
; it goes on by itself after the jingle. A fault elsewhere: its code plays,
; and START goes on. Banks 1-2 bad, or under 32K: the tape ends here and
; says which set to use instead.

	icl '../common/hw.asm'
	icl '../common/vars.asm'
	icl '../common/faults.asm'

LDRFOLD	= 1			; report.asm: fold the loader area into bank 1
SROW	= BSS+$DB		; summary: row of the item being printed
FONT	= $3800			; ROM font copy while the OS is switched out

	opt h-
S2LOAD	= $2000
	org S2LOAD

; Same header layout as a boot file: stage 1 checks the record count and
; load address, then jumps to S2LOAD+6.
	.byte 0
	.byte NREC
	.word S2LOAD
	.word 0

entry2	sei
	cld
	ldx #$FF
	txs
	ldx #0			; take over stage 1's results
tk_lp	lda S1BSS,x
	sta BSS,x
	inx
	bne tk_lp
	.ifdef CHAIN3
	lda #0			; stage 1's load may have needed a retry: its
	sta L2STAT		; SIO status is not about stage 3
	lda #<load2		; a press (or a pass) goes on to stage 3
	sta CONTVEC
	lda #>load2
	.else
	lda #0			; this stage's result is the tape's last
	.endif
	sta CONTVEC+1

	lda #C_YELLOW
	sta COLBK
	lda DISPOK
	beq rl_go
	jsr scr_on
	lda #<s_hrel
	ldy #>s_hrel
	jsr header
	lda #2
	jsr machinfo
	lda #3
	jsr chinfo
	PRINT 5, 0, s_tldr
	jsr ldrend

; Relocate test: the area stage 1 ran from. Errors are charged to the loader
; area's own entry, so the summary can tell it apart from the rest of bank 1.
rl_go	lda #LDRIDX
	sta CURBANK
	sta BANKOVR
	jsr setfmask
	lda #$08
	sta RBS
	lda #S1TSTART
	sta RBE
	jsr split
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

	lda MACHINE
	beq no_os
	jsr underos
	jsr xebanks
no_os	lda DISPOK
	beq fin
	jsr summary
fin	ldx #LDRIDX
fin_lp	lda BADMASK,x
	bne fin_bad
	dex
	bne fin_lp
	jmp pass
fin_bad	jmp report

redraw	= summary		; scrtoggle's text screen

	.ifdef CHAIN3
LDTO	= $4000			; loader.asm: stage 3, in bank 2
SKIPEOF	= 1			; loader.asm: stage 2's own EOF record comes first
results	= summary		; loader.asm: its redraw, with the L2MSG line
final	= fin			; and the tape's end when stage 3 can't load
	icl '../common/loader.asm'
; clrrow: blank row A.
clrrow	ldx #0
	jsr at
	ldx #40
	lda #0
cr_lp	jsr putc
	dex
	bne cr_lp
	rts
	.endif

; Progress lines for xlram.asm.
osprog	lda DISPOK
	beq pg_x
	PRINT 6, 0, s_tos
pg_x	rts
xeprog	lda DISPOK
	beq pg_x
	PRINT 7, 0, s_txe
	rts

; ldrend: "$xxFF", the end of the loader area.
ldrend	lda #S1TSTART-1
	jsr puthex
	lda #<s_ff
	ldy #>s_ff
	jmp puts

; ---------------------------------------------------------------------------
; summary: every test on the tape, then the first failure in detail.
SCOL	= 26			; status column
summary	jsr scr_on
	lda #<s_hsum
	ldy #>s_hsum
	jsr header
	lda #2
	jsr machinfo
	lda #3
	jsr chinfo

	lda #5
	sta SROW
	PRINT 5, 0, s_i1	; got here, so low RAM passed
	lda #<s_pass
	ldy #>s_pass
	jsr puts_st
	lda #6
	sta SROW
	PRINT 6, 0, s_i2	; and so did the display checks (or no summary)
	lda #<s_pass
	ldy #>s_pass
	jsr puts_st
	lda #7
	sta SROW
	PRINT 7, 0, s_i3
	lda VIDEOOK
	bne su_vok
	lda #<s_notc
	ldy #>s_notc
	jsr puts_st
	jmp su_banks
su_vok	lda #<s_conf
	ldy #>s_conf
	jsr puts_st

su_banks lda #1
	sta CURBANK
su_bk	clc
	adc #7			; rows 8-10
	sta SROW
	ldx #0
	jsr at
	lda CURBANK		; "4 BANK 1 $0000-$3FFF"
	clc
	adc #$13		; '3' + bank
	jsr putc
	lda #<s_bank
	ldy #>s_bank
	jsr puts
	lda CURBANK
	clc
	adc #$10
	jsr putc
	lda #<s_dol
	ldy #>s_dol
	jsr puts
	lda CURBANK
	sec
	sbc #1
	jsr bankhi
	jsr puthex
	lda #<s_00dash
	ldy #>s_00dash
	jsr puts
	lda CURBANK
	jsr bankhi
	sec
	sbc #1
	jsr puthex
	lda #<s_ff
	ldy #>s_ff
	jsr puts
	lda CURBANK		; present at all?
	sec
	sbc #1
	jsr bankhi
	cmp RAMTOP
	bcc su_have
	lda #<s_none
	ldy #>s_none
	jsr puts_st
	jmp su_next
su_have	jsr bankstat
su_next	inc CURBANK
	lda CURBANK
	cmp #4
	bne su_bk

	lda #11
	sta SROW
	PRINT 11, 0, s_i7	; loader area
	jsr ldrend
	lda #LDRIDX
	sta CURBANK
	jsr bankstat
	lda OSRAM
	beq su_cnt
	lda #12
	sta SROW
	PRINT 12, 0, s_i8
	lda OSRAM
	cmp #2
	beq su_os
	lda #<s_none
	ldy #>s_none
	jsr puts_st
	jmp su_xe
su_os	lda #4
	sta CURBANK
	jsr bankstat
su_xe	lda XERAM		; 130XE: one line for banks 5-8
	beq su_cnt
	lda #13
	sta SROW
	PRINT 13, 0, s_i9
	lda BADMASK+5
	ora BADMASK+6
	ora BADMASK+7
	ora BADMASK+8
	bne su_xf
	lda #<s_pass
	ldy #>s_pass
	jsr puts_st
	jmp su_cnt
su_xf	lda #<s_fail		; FAIL and which banks
	ldy #>s_fail
	jsr puts_st
	ldx #5
su_xl	lda BADMASK,x
	beq su_xn
	lda #0
	jsr putc
	txa
	clc
	adc #$10
	jsr putc
su_xn	inx
	cpx #9
	bne su_xl

su_cnt	PRINT 14, 0, s_nfail	; failures, and the first one's detail
	lda #0
	sta DVAL
	sta DVAL+1
	sta CNT			; first failed index
	ldx #LDRIDX
su_cl	lda BADMASK,x
	beq su_cn
	inc DVAL
	stx CNT
su_cn	dex
	bne su_cl
	jsr putdec
	lda CNT
	bne su_det
	PRINT 16, 0, s_nextok
	jmp su_end
su_det	sta CURBANK
	PRINT 16, 0, s_detail
	lda CURBANK
	cmp #LDRIDX
	beq su_dl
	cmp #5
	bcc su_mb
	lda #<s_xe
	ldy #>s_xe
	jsr puts
su_mb	lda #<s_bank
	ldy #>s_bank
	jsr puts
	lda CURBANK
	clc
	adc #$10
	jsr putc
	jmp su_dd
su_dl	lda #<s_ldr
	ldy #>s_ldr
	jsr puts
su_dd	lda #16
	sta RROW
	jsr faildetail
	PRINT 21, 0, s_nextbad
su_end
	.ifdef CHAIN3
	lda L2MSG+1		; why stage 3 didn't load
	beq su_l2
	lda #22
	jsr clrrow
	PRINT 22, 0, s_l2pre
	lda L2MSG
	ldy L2MSG+1
	jsr puts
	lda L2STAT
	beq su_l2
	jsr puthex
su_l2	lda CONTVEC+1
	beq su_t2
	PRINT 23, 0, s_toggle
	rts
su_t2
	.endif
	PRINT 23, 0, s_toggle2
	rts

; bankhi: A = bank-1 (0-3) -> A = its first page ($00/$40/$80/$C0).
bankhi	asl
	asl
	asl
	asl
	asl
	asl
	rts

; bankstat: PASS, or FAIL and the bad bits (as $xx if more than 3), for
; CURBANK, at the status column of the current row.
bankstat ldx CURBANK
	lda BADMASK,x
	bne bs_fail
	lda #<s_pass
	ldy #>s_pass
	jmp puts_st
bs_fail	lda #<s_fail
	ldy #>s_fail
	jsr puts_st
	ldx CURBANK
	lda BADMASK,x
	jsr popcnt
	cpx #4
	bcs bs_hex
	jmp putbits
bs_hex	lda #<s_dol
	ldy #>s_dol
	jsr puts
	ldx CURBANK
	lda BADMASK,x
	jmp puthex

; puts_st: print A/Y at the status column of row SROW.
puts_st	pha
	tya
	pha
	lda SROW
	ldx #SCOL
	jsr at
	pla
	tay
	pla
	jmp puts

; ---------------------------------------------------------------------------
	icl '../common/report.asm'
	icl '../common/screen.asm'
	icl '../common/ramtest.asm'
	icl '../common/info.asm'
	icl '../common/bits.asm'
	icl '../common/detail.asm'
	icl '../common/xlram.asm'

s_hpre	dta d' A8 DIAG  RAM TEST  ',$FF
s_hrel	dta d'LOADER AREA',$FF
s_hsum	dta d'SUMMARY',$FF
s_tldr	dta d'TESTING LOADER AREA $0800-$',$FF
s_i1	dta d'1 LOW RAM $0000-$07FF',$FF
s_i2	dta d'2 DISPLAY CHECKS',$FF
s_i3	dta d'3 VIDEO CHECK',$FF
s_i7	dta d'7 LOADER AREA $0800-$',$FF
s_i8	dta d'8 BANK 4 $C000-$FFFF',$FF
s_i9	dta d'9 130XE BANKS 5-8',$FF
s_xe	dta d' XE',$FF
s_bank	dta d' BANK ',$FF
s_ldr	dta d' LOADER AREA',$FF
s_dol	dta d' $',$FF
s_00dash dta d'00-$',$FF
s_ff	dta d'FF',$FF
s_pass	dta d'PASS',$FF
s_fail	dta d'FAIL'*,$FF
s_none	dta d'NOT FOUND',$FF
s_conf	dta d'CONFIRMED',$FF
s_notc	dta d'NOT CONFIRMED',$FF
s_tos	dta d'TESTING RAM UNDER THE OS ROM',$FF
s_txe	dta d'TESTING 130XE BANKS',$FF
s_nfail	dta d'FAILURES: ',$FF
s_detail dta d'DETAIL:',$FF
	.ifdef CHAIN3
s_nextok dta d'ALL PASSED. THE LAST LINE: WHAT NEXT',$FF
s_nextbad dta d'FIX THIS FIRST. THE LAST LINE: WHAT NEXT',$FF
s_toggle dta d'START=GO ON SELECT=RE-BEEP OPTION=FLASH',$FF
s_l2load dta d'LOADING THE SYSTEM TESTS, KEEP PLAYING',$FF
s_l2pre	dta d'SYSTEM TESTS: ',$FF
s_l2_8k	dta d'NEED 32K: USE THE 16K SET',$FF
s_l2_bad dta d'BANK 1 BAD: USE THE 400 SET',$FF
s_l2_big dta d'NEED BANK 2: USE 400 SET',$FF
s_l2_sio dta d'ERROR $',$FF
s_l2_hdr dta d'NOT ON TAPE',$FF
s_l2_sum dta d'BAD CHECKSUM',$FF
	.else
s_nextok dta d'ALL PASSED. NEXT: TAPE 02 OF THE SET',$FF
s_nextbad dta d'NEXT: FIX THIS ONE FIRST, THEN RE-RUN',$FF
	.endif
s_toggle2 dta d'SELECT=RE-BEEP  OPTION=FULL-SCREEN FLASH',$FF

PADTO	= [[*+2+$FF]/$100]*$100
	.if PADTO-*-2>0
	:[PADTO-*-2] .byte 0
	.endif
IMGSUM	.word 0			; mkcas.py: sum of every byte before this
IMGEND
NREC	= [IMGEND-S2LOAD]/128
BSS	= IMGEND
	.if [>BSS]+1>[>FONT]
	.error "stage 2 too big: $3800-$3FFF must stay free (font copy, screen block)"
	.endif
