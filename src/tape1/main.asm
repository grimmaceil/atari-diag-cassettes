; A8 DIAG tape 1, stage 1: boot and RAM, abstract (beep/flash) reporting.
;
;   green + chirp       alive: the CPU is running the loaded code
;   yellow              testing (a hang shows yellow)
;   red + beep code     fail; see report.asm for the code
;   purple + siren      video check timed out: last 10 s to press a key
;
; With the display checks passed the text stays on; during the pauses in the
; result code a key switches between text and full-screen flashes.
;   green + jingle      pass; then one long flash per 16K bank tested
;
; Once low RAM passes it checks the display (VCOUNT, a 1K screen block) and
; shows the video check screen, then runs the RAM test with text progress
; and results. If the display checks fail it stays beeps-only.
;
; Build flags (mads -d:NAME=value):
;   FAULT_BANK=0..4, FAULT_BIT=1..8   inject a stuck bit; bank 0 = low RAM
;   FAST=1                            skip the $55/$AA march pass

	icl '../common/hw.asm'
	icl '../common/vars.asm'
	icl '../common/faults.asm'

	opt h-
LOAD	= $0800
	org LOAD

; Cassette boot header. The OS reads NREC records to LOAD, then JSRs LOAD+6.
; We never return, so CASINI and DOSVEC are never used.
	.byte 0
	.byte NREC
	.word LOAD
	.word init_rts

	icl '../common/boot.asm'
	jsr detect
	jsr dprereq
	lda DISPOK		; no display: beeps only (ANTIC stays off)
	beq rt_go
	jsr vcheck		; confirmed or not, the text stays on from here:
	jsr ramscreen		; the display checks passed, so it can't hurt
rt_go	jsr ramtest
	lda DISPOK
	beq rt_res
	jsr results
rt_res	lda #<load2		; a press (or a pass) goes on to stage 2
	sta CONTVEC
	lda #>load2
	sta CONTVEC+1
	lda SCRON
	beq final
	jsr results		; again: the prompt line now names START
final	ldx #4
res_lp	lda BADMASK,x
	bne res_bad
	dex
	bne res_lp
	jmp pass
res_bad	jmp report

redraw	= results		; scrtoggle's text screen

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

	icl '../common/display.asm'

; ---------------------------------------------------------------------------
; Video check: text, the full character set, inverse video and 8 color
; bars. The bars are drawn by racing the beam (COLPF2 changed every 8 lines
; with WSYNC), so no interrupts are needed. A press confirms the video; it
; only counts after every input has been seen released, so a stuck key can't
; confirm by itself. No press in 20 s (plus the last chance) leaves
; VIDEOOK = 0; the text stays on anyway and the results say so.
BARROW	= 14
BARV	= [32+BARROW*8]/2	; VCOUNT at the top of the bars

vcheck	jsr scr_on
	lda #C_YELLOW
	sta COLBK
	lda #<s_hvid
	ldy #>s_hvid
	jsr header
	PRINT 2, 0, s_v1
	PRINT 3, 0, s_v2
	PRINT 4, 0, s_v3
	PRINT 8, 1, s_set1
	PRINT 9, 1, s_set2
	lda #$80
	sta INV
	PRINT 10, 1, s_set1
	lda #0
	sta INV
	lda #11
	jsr machinfo
	lda #12
	jsr chinfo
	ldx #0
vc_bars	stx CNT
	txa
	clc
	adc #BARROW
	ldx #2
	jsr at
	lda #<s_bar
	ldy #>s_bar
	jsr puts
	lda CNT
	clc
	adc #$11		; '1'
	jsr putc
	ldx CNT
	inx
	cpx #8
	bne vc_bars

	lda #20
	sta SECLEFT
	jsr showsec
	jsr fps
	sta FRM

vk_frame lda VCOUNT
	cmp #BARV
	bne vk_frame
	ldx #0
vk_bar	lda barcol,x
	sta WSYNC
	sta COLPF2
	ldy #7
vk_line	sta WSYNC
	dey
	bne vk_line
	inx
	cpx #8
	bne vk_bar
	sta WSYNC
	lda #C_TEXTBG
	sta COLPF2

	jsr inputs
	bne vk_down
	lda #1
	sta ARMED
	bne vk_tick
vk_down	lda ARMED
	beq vk_tick
	inc VIDEOOK
	lda #AUD_OFF
	sta AUDC1
vk_rel	jsr inputs		; let go before moving on
	bne vk_rel
	rts

vk_tick	jsr siren
	dec FRM
	bne vk_wrap
	jsr fps
	sta FRM
	dec SECLEFT
	bne vk_show
	lda LASTCH		; time's up: one last chance, then beeps only
	bne vk_x
	inc LASTCH
	lda #LASTSECS
	sta SECLEFT
	lda #C_PURPLE
	sta COLBK
vk_show	jsr showsec
vk_wrap	lda VCOUNT		; wait for the next frame to begin
	cmp #BARV
	bcs vk_wrap
	jmp vk_frame
vk_x	lda #AUD_OFF
	sta AUDC1
	lda #C_YELLOW		; back to "testing" for the beeps-only run
	sta COLBK
	rts

; siren: a two-tone warble over the first 3 s of the last chance, to call
; someone back to the screen. Called once per frame.
LASTSECS = 10
siren	lda LASTCH
	beq sn_off
	lda SECLEFT
	cmp #LASTSECS-2
	bcc sn_off
	lda FRM			; swap pitch every 16 frames
	and #16
	beq sn_lo
	lda #F_SIRH
	bne sn_on
sn_lo	lda #F_SIRL
sn_on	sta AUDF1
	lda #AUD_ON
	sta AUDC1
	rts
sn_off	lda #AUD_OFF
	sta AUDC1
	rts


fps	lda ISPAL
	bne fps_p
	lda #60
	rts
fps_p	lda #50
	rts

showsec	lda LASTCH
	bne ss_last
	PRINT 6, 0, s_secs
	jmp ss_num
ss_last	PRINT 6, 0, s_last
ss_num
	lda SECLEFT
	sta DVAL
	lda #0
	sta DVAL+1
	jsr putdec
	lda #0			; blank the old second digit
	jmp putc

barcol	.byte $16,$36,$56,$76,$96,$B6,$D6,$F6

; ---------------------------------------------------------------------------
; RAM test, bank by bank (16K each) from TSTART to RAMTOP, minus the screen
; block (tested in findscr). Below TSTART is low RAM (tested) and this stage.
ramtest	lda #1
	sta CURBANK
rt_bank	jsr bankrange
	bcs rt_next
	inc NBANKS
	jsr showbank
	jsr split
	lda RNGN
	beq rt_next
	jsr setfmask
	jsr march2
rt_next	inc CURBANK
	lda CURBANK
	cmp #4
	bne rt_bank

; Address-in-address over everything at once, so a bank that mirrors
; another (an address-line or decoder fault) shows up too.
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
	rts

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


; ---------------------------------------------------------------------------
; Text screens for the RAM test.
ramscreen jsr scr_on
	lda #C_YELLOW
	sta COLBK
	lda #<s_hram
	ldy #>s_hram
	jsr header
	lda #2
	jsr machinfo
	lda #3
	jmp chinfo

showbank lda DISPOK
	beq sb_x
	PRINT 5, 0, s_testing
	lda CURBANK
	clc
	adc #$10
	jmp putc
sb_x	rts

; results: one line per bank (plus the bad bits for a failed one), then the
; overall result. The full detail (first error, hint) is on stage 2's summary.
;   BANK 2 $4000-$7FFF  FAIL
;    FIRST $4000 W $00 R $10 X $10 HI
;    ERRORS 65535  BITS D4
;    ONE BIT: ONE RAM CHIP
results	jsr ramscreen
	PRINT 4, 0, s_legend
	lda #6
	sta RROW
	lda #1
	sta CURBANK
rs_bank	lda RROW
	ldx #0
	jsr at
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
	lda CURBANK		; $(b-1)*40 00 - $(b*40-1) FF
	sec
	sbc #1
	asl
	asl
	asl
	asl
	asl
	asl
	jsr puthex
	lda #<s_00dash
	ldy #>s_00dash
	jsr puts
	lda CURBANK
	asl
	asl
	asl
	asl
	asl
	asl
	sec
	sbc #1
	jsr puthex
	lda #<s_ff
	ldy #>s_ff
	jsr puts
	jsr bankrange
	bcc rs_found
	lda #<s_none
	ldy #>s_none
	jsr puts
	jmp rs_next
rs_found ldx CURBANK
	lda BADMASK,x
	bne rs_fail
	lda #<s_pass
	ldy #>s_pass
	jsr puts
	jmp rs_next
rs_fail	lda #<s_fail
	ldy #>s_fail
	jsr puts
	jsr bitsline
rs_next	inc RROW
	inc CURBANK
	lda CURBANK
	cmp #4
	beq rs_end
	jmp rs_bank

rs_end	lda MACHINE
	beq rs_tot
	lda RROW
	ldx #0
	jsr at
	lda #<s_bank4
	ldy #>s_bank4
	jsr puts
rs_tot	lda VIDEOOK
	bne rs_vok
	PRINT 21, 0, s_vnot
rs_vok	lda CONTVEC+1
	beq rs_end2
	PRINT 23, 0, s_toggle
	jmp rs_l2
rs_end2	PRINT 23, 0, s_toggle2
rs_l2	lda L2MSG+1		; why stage 2 didn't run
	beq rs_res
	PRINT 22, 0, s_l2pre
	lda L2MSG
	ldy L2MSG+1
	jsr puts
	lda L2STAT
	beq rs_res
	jsr puthex
rs_res
	PRINT 20, 0, s_result
	ldx #4
rs_any	lda BADMASK,x
	bne rs_bad
	dex
	bne rs_any
	lda #<s_allpass
	ldy #>s_allpass
	jmp puts
rs_bad	lda #<s_somefail
	ldy #>s_somefail
	jmp puts

; ---------------------------------------------------------------------------
; Strings, in screen codes ($FF ends).
s_hpre	dta d' A8 DIAG  RAM TEST  ',$FF	; header prefix (header inverts it)
s_hvid	dta d'VIDEO CHECK',$FF
s_hram	dta d'RAM TEST',$FF
s_v1	dta d'CAN YOU READ THIS AND SEE 8 COLOR BARS?',$FF
s_v2	dta d'IF SO, PRESS A KEY, START, SELECT,',$FF
s_v3	dta d'OPTION OR FIRE.',$FF
s_secs	dta d'SECONDS LEFT: ',$FF
s_last	dta d'LAST CHANCE'*,d' - SECONDS LEFT: ',$FF
s_set1	dta d'ABCDEFGHIJKLMNOPQRSTUVWXYZ 0123456789',$FF
s_set2	dta d'!"#$%&()*+,-./:;<=>?@[]^_',$FF
s_bar	dta d'COLOR BAR ',$FF
s_testing dta d'TESTING BANK ',$FF
s_legend dta d'CODE: LONG=BANK, SHORT=BIT (D0=1)',$FF
s_bank	dta d'BANK ',$FF
s_dol	dta d' $',$FF
s_00dash dta d'00-$',$FF
s_ff	dta d'FF  ',$FF
s_none	dta d'NOT FOUND',$FF
s_pass	dta d'PASS',$FF
s_fail	dta d'FAIL'*,$FF
s_bank4	dta d'BANK 4 $C000-$FFFF  IN STAGE 2',$FF
s_result dta d'RESULT: ',$FF
s_vnot	dta d'VIDEO NOT CONFIRMED',$FF
s_toggle dta d'START=GO ON SELECT=RE-BEEP OPTION=FLASH',$FF
s_toggle2 dta d'SELECT=RE-BEEP  OPTION=FULL-SCREEN FLASH',$FF
s_l2load dta d'LOADING STAGE 2, KEEP TAPE PLAYING',$FF
s_l2pre	dta d'STAGE 2: ',$FF
s_l2_8k	dta d'NEEDS 16K. NEXT: 400 TAPE 02',$FF
s_l2_bad dta d'NOT LOADED, BANK 1 FAILED',$FF
s_l2_big dta d'TOO BIG FOR THE GOOD RAM',$FF
s_l2_sio dta d'ERROR $',$FF
s_l2_hdr dta d'NOT ON TAPE',$FF
s_l2_sum dta d'BAD CHECKSUM',$FF
s_allpass dta d'ALL RAM PASSED',$FF
s_somefail dta d'FAIL - CODE REPEATS ON BORDER'*,$FF

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
	icl '../common/bits.asm'

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
