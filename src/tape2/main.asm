; A8 DIAG tape 2: RAM burn-in.
;
; Boots like tape 1 (alive, image checksum, low RAM, size probe, machine,
; display prerequisites; no video check), then loops the RAM tests over all
; the RAM it can reach until a key is pressed:
;   low RAM (non-destructive), the main banks above this stage, a global
;   address test, and on the XL/XE the RAM under the OS (bank 4, but not
;   page $FF) and the 130XE banks (5-8).
; Not covered: $0800 up to TSTART, where this stage runs (tape 1's stage 2
; tests it).
;
; Every bad bit goes in a log: bank, bit, the pass it was first seen in, and
; how many passes since then it failed in. A bit that fails every pass is
; solid; one that skips passes is intermittent.
;   green border     no errors yet
;   yellow border    an intermittent error has been seen
;   red border       solid errors only
;   bright pulse     end of a pass
; Any key, START, SELECT, OPTION or fire stops after the pass in progress;
; then the summary, and the beep code for every bank with a bad bit (steady
; yellow between repeats when all of them were intermittent).
;
; A VBI handler keeps the clock and watches for the stop press. It is off
; during the low RAM test (the stack is under test); that part is added to
; the clock as a fixed allowance, so the time is approximate.

	icl '../common/hw.asm'
	icl '../common/vars.asm'
	icl '../common/faults.asm'

BURNIN	= 1			; xlram.asm: page $FF stays out, NMI vector in RAM
LRCALL	= 1			; boot.asm: lowram can be called again
RPCOLVAR = 1			; report.asm: steady color from RPCOL
FONT	= $3800			; ROM font copy while the OS is switched out

; Tape 2 variables, in the BSS page above the shared ones.
PASSNO	= BSS+$E0		; 2: passes started
STOPREQ	= BSS+$E2		; a stop press was seen (set by the VBI)
TARM	= BSS+$E3		; VBI: controls seen released
TFRM	= BSS+$E4		; clock: frames left in this second
TSEC	= BSS+$E5		; clock: seconds, minutes, hours
TMIN	= BSS+$E6
THRS	= BSS+$E7
FPSV	= BSS+$E8		; frames per second, 50 or 60
RPCOL	= BSS+$E9		; report.asm: steady color between repeats
BCOL	= BSS+$EA		; border color for the state so far
FCNT	= BSS+$EB		; FAULT_EVERY countdown
FAULTON	= BSS+$EC		; FAULT_EVERY: inject on this pass
LOGROW	= BSS+$ED		; log printing: row
NSOLID	= BSS+$EE		; summary: solid and intermittent log entries
NINT	= BSS+$EF
LOGIX	= BSS+$F0		; log printing: entry index

; The error log, one entry per bank (1-9) and bit: index (bank-1)*8 + bit.
; In pages 5-6 of low RAM: free while this tape runs (no DOS, no OS floating
; point), and the per-pass low RAM test puts every byte back.
LOGN	= 72
FIRSTLO	= $0500			; pass first seen in (0 = never)
FIRSTHI	= FIRSTLO+LOGN
CNTLO	= FIRSTHI+LOGN		; passes failed in
CNTHI	= CNTLO+LOGN
EVER	= CNTHI+LOGN		; 16: every bad bit seen, per bank

VVBLKI	= $0222			; OS immediate VBI vector
XITVBV	= $E462			; OS VBI exit: restores the registers, RTI
NMIRES	= $D40F

	opt h-
LOAD	= $0800
	org LOAD

; Cassette boot header. The OS reads NREC records to LOAD, then JSRs LOAD+6.
	.byte 0
	.byte NREC
	.word LOAD
	.word init_rts

	icl '../common/boot.asm'

	ldx #0			; clear the log pages
	txa
cl_log	sta FIRSTLO,x
	sta FIRSTLO+$100,x
	inx
	bne cl_log
	jsr detect
	jsr dprereq
	lda #60
	ldx ISPAL
	beq bi_fps
	lda #50
bi_fps	sta FPSV
	sta TFRM
	lda #C_GREEN
	sta BCOL
	sta RPCOL
	.if .def FAULT_EVERY
	lda #FAULT_EVERY
	sta FCNT
	.endif
	lda DISPOK
	beq bi_vbi
	jsr scr_on
	jsr bscreen

bi_vbi	lda #$40		; keyboard interrupt on in POKEY (the CPU still
	sta IRQEN		; masks it): IRQST bit 6 latches a keypress
	lda #<vbios		; start the clock
	sta VVBLKI
	lda #>vbios
	sta VVBLKI+1
	lda #$40
	sta NMIEN

; ---------------------------------------------------------------------------
; One pass.
pass1	inc PASSNO
	bne ps_go
	inc PASSNO+1
ps_go	lda BCOL
	sta COLBK
	ldx #15			; this pass's bad bits; first errors stay
	lda #0
ps_clr	sta BADMASK,x
	dex
	bpl ps_clr
	sta NBANKS
	.if .def FAULT_EVERY
	sta FAULTON
	dec FCNT
	bne ps_nf
	inc FAULTON
	lda #FAULT_EVERY
	sta FCNT
ps_nf
	.endif
	jsr showpass

	lda #<s_low		; low RAM, with the VBI off
	ldy #>s_low
	jsr step
	lda #0
	sta NMIEN
	jsr lowram
	ldx #34			; the time it took, about 0.57 s
	lda ISPAL
	beq ps_lr
	ldx #28
ps_lr	jsr tick
	dex
	bne ps_lr
	lda #$40
	sta NMIEN

	lda #1			; main banks
	sta CURBANK
ps_bank	jsr bankrange
	bcs ps_nb
	inc NBANKS
	lda #<s_bank
	ldy #>s_bank
	jsr step
	lda CURBANK
	clc
	adc #$10
	jsr putc_s
	jsr split
	lda RNGN
	beq ps_nb
	jsr setfmask
	jsr march2
ps_nb	inc CURBANK
	lda CURBANK
	cmp #4
	bne ps_bank

	lda #<s_aia		; address-in-address over all of them
	ldy #>s_aia
	jsr step
	lda #TSTART
	sta RBS
	lda RAMTOP
	sta RBE
	jsr split
	inc INAIA
	lda #0
	sta AIAMODE
	jsr aia
	inc AIAMODE
	jsr aia
	dec INAIA

	lda MACHINE
	beq ps_end
	lda #0
	sta OSRAM
	sta XERAM
	jsr underos
	jsr xebanks

ps_end	jsr logpass
	jsr pulse
	lda DISPOK
	beq ps_next
	jsr showpass
	jsr showlog
ps_next	lda STOPREQ
	bne stop
	jmp pass1

; ---------------------------------------------------------------------------
; Stop: clock off, summary, then the code for every bank with a bad bit.
stop	lda #0
	sta NMIEN
	sta IRQEN
	ldx #15
st_m	lda EVER,x
	sta BADMASK,x
	dex
	bpl st_m
	jsr waitrel
	lda DISPOK
	beq st_code
	jsr summary
st_code	lda #0
	sta CONTVEC+1
	ldx #9
st_any	lda BADMASK,x
	bne st_bad
	dex
	bne st_any
	jmp pass
st_bad	lda BCOL		; yellow if every error was intermittent
	sta RPCOL
	jmp report

redraw	= summary		; scrtoggle's text screen

; ---------------------------------------------------------------------------
; The clock. vbios is the OS immediate VBI (VVBLKI); nmiraw is the NMI
; vector itself while the OS is switched out (xlram.asm). Both only touch A.
vbios	jsr tick
	jmp XITVBV
nmiraw	pha
	sta NMIRES
	jsr tick
	pla
	rti

; tick: one frame. Also latches a stop press (after a release, so a stuck
; key doesn't stop it). Uses A only.
tick	dec TFRM
	bne tk_in
	lda FPSV
	sta TFRM
	inc TSEC
	lda TSEC
	cmp #60
	bne tk_in
	lda #0
	sta TSEC
	inc TMIN
	lda TMIN
	cmp #60
	bne tk_in
	lda #0
	sta TMIN
	inc THRS
tk_in	lda STOPREQ
	bne tk_x
	lda IRQST		; a keypress POKEY latched: also seen when it fell
	and #$40		; in the low RAM test, with the VBI off
	bne tk_ni
	inc STOPREQ
	rts
tk_ni	jsr inputs
	bne tk_dn
	lda #1
	sta TARM
	rts
tk_dn	lda TARM
	beq tk_x
	inc STOPREQ
tk_x	rts

; ---------------------------------------------------------------------------
; logpass: put this pass's bad bits in the log.
logpass	ldx #1
lp_bank	lda BADMASK,x
	beq lp_next
	ora EVER,x
	sta EVER,x
	lda BADMASK,x
	sta MTMP
	txa			; Y = (bank-1)*8
	sec
	sbc #1
	asl
	asl
	asl
	tay
lp_bit	lsr MTMP
	bcc lp_nob
	lda FIRSTLO,y
	ora FIRSTHI,y
	bne lp_cnt
	lda PASSNO
	sta FIRSTLO,y
	lda PASSNO+1
	sta FIRSTHI,y
lp_cnt	lda CNTLO,y
	clc
	adc #1
	sta CNTLO,y
	bcc lp_nob
	lda CNTHI,y
	adc #0
	sta CNTHI,y
lp_nob	iny
	lda MTMP
	bne lp_bit
lp_next	inx
	cpx #10
	bne lp_bank

; The border: yellow once anything intermittent, else red if anything, else
; green. Also counts both kinds for the summary.
	lda #0
	sta NSOLID
	sta NINT
	ldy #LOGN-1
lc_lp	lda FIRSTLO,y
	ora FIRSTHI,y
	beq lc_n
	jsr solid
	bcc lc_int
	inc NSOLID
	bne lc_n
lc_int	inc NINT
lc_n	dey
	bpl lc_lp
	lda #C_GREEN
	ldx NINT
	bne lc_y
	ldx NSOLID
	beq lc_set
	lda #C_RED
	bne lc_set
lc_y	lda #C_YELLOW
lc_set	sta BCOL
	rts

; solid: C set if log entry Y failed in every pass since its first:
; count = PASSNO - first + 1. Keeps Y.
solid	lda PASSNO
	sec
	sbc FIRSTLO,y
	sta DVAL
	lda PASSNO+1
	sbc FIRSTHI,y
	sta DVAL+1
	inc DVAL
	bne so_c
	inc DVAL+1
so_c	lda DVAL
	cmp CNTLO,y
	bne so_no
	lda DVAL+1
	cmp CNTHI,y
	bne so_no
	sec
	rts
so_no	clc
	rts

; pulse: the green end-of-pass flash and beep, then the state color.
pulse	BEEP T_J1
	lda BCOL
	sta COLBK
	rts

; ---------------------------------------------------------------------------
; Screens.
bscreen	lda #<s_hburn
	ldy #>s_hburn
	jsr header
	lda #2
	jsr machinfo
	lda #3
	jsr chinfo
	PRINT 8, 0, s_legend
	PRINT 23, 0, s_stop
	rts

; step: "NOW: " + the string at A/Y on row 6, the rest of the row blank.
step	ldx DISPOK
	beq st_x
	pha
	tya
	pha
	lda #6
	jsr clrrow
	PRINT 6, 0, s_now
	pla
	tay
	pla
	jsr puts
	lda STOPREQ		; the stop line, once a press was seen
	beq st_x
	PRINT 23, 0, s_stopping
st_x	rts

; putc_s: putc, only with a screen.
putc_s	ldx DISPOK
	beq st_x
	jmp putc

; showpass: "PASS n   TIME h:mm:ss" on row 5.
showpass lda DISPOK
	beq st_x
	PRINT 5, 0, s_pass
	lda PASSNO
	sta DVAL
	lda PASSNO+1
	sta DVAL+1
	jsr putdec
	lda #<s_time
	ldy #>s_time
	jsr puts
	jsr puttime
	lda #0
	jmp putc

; puttime: h:mm:ss.
puttime	lda THRS
	sta DVAL
	lda #0
	sta DVAL+1
	jsr putdec
	lda #$1A		; ':'
	jsr putc
	lda TMIN
	jsr put2
	lda #$1A
	jsr putc
	lda TSEC
; put2: A (0-99) as two digits.
put2	ldx #0
p2_lp	cmp #10
	bcc p2_x
	sbc #10
	inx
	bne p2_lp
p2_x	pha
	txa
	clc
	adc #$10
	jsr putc
	pla
	clc
	adc #$10
	jmp putc

; showlog: the log from row 9: "B2 D4  FIRST 3  FAILED 5/7", up to 12
; entries, then "+n MORE".
LOGTOP	= 9
LOGMAX	= 12
showlog	lda #LOGTOP
	sta LOGROW
	lda #0
	sta LOGIX
	sta CNT			; entries not shown
sl_lp	ldy LOGIX
	lda FIRSTLO,y
	ora FIRSTHI,y
	bne sl_have
	jmp sl_next
sl_have	lda LOGROW
	cmp #LOGTOP+LOGMAX
	bcc sl_show
	inc CNT
	jmp sl_next
sl_show	jsr clrrow
	lda LOGROW
	ldx #0
	jsr at
	lda #$22		; 'B'
	jsr putc
	lda LOGIX		; bank = index/8 + 1
	lsr
	lsr
	lsr
	clc
	adc #$11
	jsr putc
	lda #0
	jsr putc
	lda #$24		; 'D'
	jsr putc
	lda LOGIX
	and #7
	clc
	adc #$10
	jsr putc
	lda #<s_first
	ldy #>s_first
	jsr puts
	ldy LOGIX
	lda FIRSTLO,y
	sta DVAL
	lda FIRSTHI,y
	sta DVAL+1
	jsr putdec
	lda #<s_failed
	ldy #>s_failed
	jsr puts
	ldy LOGIX
	lda CNTLO,y
	sta DVAL
	lda CNTHI,y
	sta DVAL+1
	jsr putdec
	lda #$0F		; '/'
	jsr putc
	ldy LOGIX		; passes since first
	jsr solid
	php
	jsr putdec		; DVAL is that count now
	plp
	bcs sl_sol
	lda #<s_int
	ldy #>s_int
	jsr puts
sl_sol	inc LOGROW
sl_next	inc LOGIX
	lda LOGIX
	cmp #LOGN
	beq sl_end
	jmp sl_lp
sl_end	lda CNT
	beq sl_x
	lda LOGROW
	ldx #0
	jsr at
	lda #$0B		; '+'
	jsr putc
	lda CNT
	sta DVAL
	lda #0
	sta DVAL+1
	jsr putdec
	lda #<s_more2
	ldy #>s_more2
	jsr puts
sl_x	rts

; summary: the run's result and the whole log.
summary	jsr scr_on
	lda #<s_hsum
	ldy #>s_hsum
	jsr header
	lda #2
	jsr machinfo
	lda #3
	jsr chinfo
	jsr showpass
	PRINT 6, 0, s_result
	lda NSOLID
	ora NINT
	bne su_bad
	lda #<s_noerr
	ldy #>s_noerr
	jsr puts
	PRINT 21, 0, s_nextok
	jmp su_end
su_bad	lda NSOLID
	sta DVAL
	lda #0
	sta DVAL+1
	jsr putdec
	lda #<s_nsol
	ldy #>s_nsol
	jsr puts
	lda NINT
	sta DVAL
	lda #0
	sta DVAL+1
	jsr putdec
	lda #<s_int
	ldy #>s_int
	jsr puts
	PRINT 8, 0, s_legend
	jsr showlog
	PRINT 21, 0, s_nextbad
su_end	PRINT 23, 0, s_toggle2
	rts

; clrrow: blank row A.
clrrow	ldx #0
	jsr at
	ldx #40
	lda #0
cr_lp	jsr putc
	dex
	bne cr_lp
	rts

; Progress hooks for xlram.asm.
osprog	lda #<s_os
	ldy #>s_os
	jmp step
xeprog	lda #<s_xe
	ldy #>s_xe
	jmp step

; bankrange: RBS/RBE = the pages of bank CURBANK to test. C set if none.
bankrange lda CURBANK
	sec
	sbc #1
	asl
	asl
	asl
	asl
	asl
	asl
	cmp #TSTART
	bcs br_s
	lda #TSTART
br_s	sta RBS
	lda CURBANK
	asl
	asl
	asl
	asl
	asl
	asl
	cmp RAMTOP
	bcc br_e
	lda RAMTOP
br_e	sta RBE
	lda RBS
	cmp RBE
	rts

	icl '../common/display.asm'

init_rts rts

; Low-RAM patterns: solid, checkerboard, walking 1, walking 0.
pats	.byte $00,$FF,$55,$AA
	.byte $01,$02,$04,$08,$10,$20,$40,$80
	.byte $FE,$FD,$FB,$F7,$EF,$DF,$BF,$7F
NPAT	= *-pats

	icl '../common/report.asm'
	icl '../common/screen.asm'
	icl '../common/ramtest.asm'
	icl '../common/info.asm'
	icl '../common/xlram.asm'

s_hpre	dta d' A8 DIAG  BURN-IN   ',$FF
s_hburn	dta d'BURN-IN',$FF
s_hsum	dta d'SUMMARY',$FF
s_legend dta d'BANK BIT  FIRST  FAILED/PASSES',$FF
s_stop	dta d'KEY = STOP AFTER THIS PASS',$FF
s_stopping dta d'STOPPING AFTER THIS PASS  ',$FF
s_now	dta d'NOW: ',$FF
s_low	dta d'LOW RAM $0000-$07FF',$FF
s_bank	dta d'BANK ',$FF
s_aia	dta d'ADDRESS TEST',$FF
s_os	dta d'UNDER THE OS',$FF
s_xe	dta d'130XE BANKS 5-8',$FF
s_pass	dta d'PASS ',$FF
s_time	dta d'   TIME ',$FF
s_first	dta d'  FIRST ',$FF
s_failed dta d'  FAILED ',$FF
s_int	dta d' INTERMITTENT',$FF
s_more2	dta d' MORE',$FF
s_result dta d'RESULT: ',$FF
s_noerr	dta d'NO ERRORS',$FF
s_nsol	dta d' SOLID, ',$FF
s_nextok dta d'NEXT: TAPE 02 OF THE SET',$FF
s_nextbad dta d'FIX SOLID ONES FIRST',$FF
s_toggle2 dta d'SELECT=RE-BEEP  OPTION=FULL-SCREEN FLASH',$FF

; Pad to a whole page; the last two bytes hold the image sum (mkcas.py).
PADTO	= [[*+2+$FF]/$100]*$100
	.if PADTO-*-2>0
	:[PADTO-*-2] .byte 0
	.endif
CKSUM	.word 0
IMGEND
NREC	= [IMGEND-LOAD]/128
BSS	= IMGEND
TSTART	= [>BSS]+1
