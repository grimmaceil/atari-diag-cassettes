; System tapes, shared code: the test list, the per-test result flow, frame
; sync, yes/no answers, the test-result screen and the tape's results.
;
; Each test leaves its failed items in BADMASK[test] (item n = bit n-1), so
; the reporter plays A = test number, B = item, as the brief has it. A test
; ends with jmp tend; the tape's tlist says what comes next.

; The system tapes run no RAM tests, so their data lives in the first-error
; arrays ($70-$CF of the BSS page), which only merr writes. (qscr uses ECNTLO.)
TEST	= BSS+$E0		; current test, 1-7
NEXTVEC	= BSS+$E1		; 2: where the test flow goes on to
STASH	= BSS+$E3		; 8: BADMASK 1-8 while one test's code plays
TIDX	= BSS+$ED		; next tlist entry, times 2
ENDING	= BSS+$F7		; nonzero: the tape's results; START runs it again
T3D	= BSS+$70		; 96 bytes of test data:
NPORT	= T3D+$02		; joystick ports on this machine (paddles: twice)
				; $03-$1F: test 1's results (kept for the summary)
TSCR	= T3D+$20		; $20-$5F: scratch, each test its own use

; trun: from the boot, the first test on the list.
trun	lda #2			; ports: 4 on the 400/800, 2 on the XL/XE
	ldx MACHINE
	bne tst_xl
	lda #4
tst_xl	sta NPORT
	lda #0
	sta TIDX
	.ifdef MENU
	sta MRUN
	sta MMODE
	tax			; MNT: the tests on the tape
tst_n	lda ttests,x
	beq tst_nt
	inx
	bne tst_n
tst_nt	stx MNT
	stx MSEL		; the ALL line first
	lda DISPOK		; no picture: no menu, all of them in order
	beq tst_all
	jmp menu
tst_all	inc MMODE
	.endif
	jsr tnextv
	jmp (NEXTVEC)

; trestart: the tape's tests again from the first, with fresh results (not
; test 8, the 48k tape's RAM).
trestart lda #0
	sta ENDING
	sta TIDX
	ldx #7
trs_cl	sta BADMASK,x
	dex
	bne trs_cl
	jsr tnextv
	jmp (NEXTVEC)

; tend: the end of a test: its result, then the next one on the list (from
; the menu: back to the menu, the next test highlighted).
tend	.ifdef MENU
	ldx TEST
	lda bitn-1,x
	ora MRUN
	sta MRUN
	.endif
	jsr tnextv
	.ifdef MENU
	lda MMODE
	bne te_x
	inc MSEL		; the next test (after the last: the results)
	lda MSEL
	cmp MNT
	bne te_m
	inc MSEL
te_m	lda #<menu
	sta NEXTVEC
	lda #>menu
	sta NEXTVEC+1
te_x
	.endif
	jmp tresult

; tnextv: NEXTVEC = the next tlist entry.
tnextv	ldx TIDX
	lda tlist,x
	sta NEXTVEC
	lda tlist+1,x
	sta NEXTVEC+1
	inx
	inx
	stx TIDX
	rts

; vsync: wait for the start of the next frame (VCOUNT back from the bottom;
; 124 is reached on NTSC (130) and PAL (155)).
vsync	lda VCOUNT
	cmp #124
	bcc vsync
vs_2	lda VCOUNT
	cmp #124
	bcs vs_2
	rts

; yesno: wait for the answer, as long as it takes. C set: Y or START. C
; clear: N or SELECT. Console keys too, so a dead keyboard can answer. The
; border is purple while it waits, so a question shows without a picture.
; YNSND: the sound being asked about, repeated until the answer (about 0.7 s
; on, 0.5 s off): 0 none, 1 POKEY voice YNV/2, 2 the console speaker. A key
; pressed while the speaker tone runs (the CPU is busy making it) still
; counts: POKEY latches it in IRQST.
YNSND	= BSS+$F4
YNV	= BSS+$F5		; POKEY voice times 2 (its AUDF/AUDC offset)
YNFRM	= BSS+$F6		; frame in the on/off cycle
yesno	jsr waitrel
	lda #C_PURPLE
	sta COLBK
	lda #$40		; the keyboard IRQ latch (the CPU masks the IRQ)
	sta IRQEN
	lda #0
	sta YNFRM
yn_lp	lda YNFRM
	bne yn_s1
	jsr ynon
	jmp yn_f
yn_s1	cmp #42
	bne yn_f
	jsr ynoff
yn_f	jsr vsync
	inc YNFRM
	lda YNFRM
	cmp #72
	bne yn_k
	lda #0
	sta YNFRM
yn_k	lda IRQST		; a key since the last look?
	and #$40
	bne yn_con
	lda #0
	sta IRQEN
	lda #$40
	sta IRQEN
	lda KBCODE
	and #$3F
	cmp #$2B		; Y
	beq yn_yes
	cmp #$23		; N
	beq yn_no
yn_con	lda CONSOL
	lsr			; START
	bcc yn_yes
	lsr			; SELECT
	bcc yn_no
	jmp yn_lp
yn_no	clc
	bcc yn_x
yn_yes	sec
yn_x	php
	jsr ynoff
	lda #0
	sta IRQEN
	sta YNSND
	lda #C_BLACK
	sta COLBK
	jsr waitrel
	plp
	rts

; ynon/ynoff: YNSND's sound on, off. The console speaker has no hardware
; tone: ynon makes 0.7 s of it then and there (WAITMS toggles the speaker).
ynon	lda YNSND
	beq yo_x
	cmp #1
	bne yo_spk
	ldx YNV
	lda #F_LONG
	sta AUDF1,x
	lda #AUD_ON
	sta AUDC1,x
yo_x	rts
yo_spk	lda #$08
	sta SPKMASK
	WAITMS 700
	lda #0
	sta SPKMASK
	lda #42			; that was the on time: on to the gap
	sta YNFRM
	rts
ynoff	lda YNSND
	cmp #1
	bne yf_x
	ldx YNV
	lda #AUD_OFF
	sta AUDC1,x
yf_x	rts

; tresult: the end of test TEST. A pass gives the jingle and goes on after
; ~2 s (OPTION holds it). A fail plays that test's code (only that one) and
; waits for START, a key or fire; then the flow goes on at NEXTVEC.
tresult	jsr tshow
	ldx TEST
	lda BADMASK,x
	bne tr_fail
	.ifdef WANT_ROM
	cpx #1			; the ROMs: a pass waits too, to read the sums
	bne tr_ps
	stx ENDING		; (report.asm's pass: no going on by itself)
	stx NBANKS		; (one flash)
	lda #<tr_go
	sta CONTVEC
	lda #>tr_go
	sta CONTVEC+1
	jmp pass
tr_go	lda #0
	sta ENDING
	jmp (NEXTVEC)
tr_ps
	.endif
	lda NEXTVEC
	sta CONTVEC
	lda NEXTVEC+1
	sta CONTVEC+1
	jmp pass
tr_fail	ldx #8
tf_st	lda BADMASK,x
	sta STASH-1,x
	cpx TEST
	beq tf_keep
	lda #0
	sta BADMASK,x
tf_keep	dex
	bne tf_st
	lda #<tr_back
	sta CONTVEC
	lda #>tr_back
	sta CONTVEC+1
	jmp report
tr_back	ldx #8
tf_rs	lda STASH-1,x
	sta BADMASK,x
	dex
	bne tf_rs
	jmp (NEXTVEC)

; tpage: a fresh page for test TEST, titled A/Y.
tpage	ldx DISPOK
	beq tp_x
	pha
	tya
	pha
	jsr scr_on
	pla
	tay
	pla
	jsr header
	lda #2
	jmp machinfo
tp_x	rts

; tshow: the result lines of test TEST on rows 21-23 (the test's own screen
; stays above). Also scrtoggle's redraw.
tshow	lda TEST		; 8: past the last test, the tape's results
	cmp #8
	bne ts_t
	jmp results
ts_t	lda DISPOK
	beq ts_x
	lda SCRON
	bne ts_on
	jsr scr_on		; back from full-screen flashes: a plain page
	lda TEST
	asl
	tax
	lda tnames-2,x
	ldy tnames-1,x
	jsr header
ts_on	lda #21
	jsr clrrow
	PRINT 21, 0, s_test
	lda TEST
	clc
	adc #$10
	jsr putc
	lda #0
	jsr putc
	ldx TEST
	lda BADMASK,x
	bne ts_fail
	lda #<s_pass
	ldy #>s_pass
	jsr puts
	.ifdef WANT_ROM
	ldx TEST		; (the ROMs wait for a press)
	dex
	beq ts_go
	.endif
	PRINT 23, 0, s_tpass
ts_x	rts
	.ifdef WANT_ROM
ts_go	PRINT 23, 0, s_toggle
	rts
	.endif
ts_fail	lda #<s_fail
	ldy #>s_fail
	jsr puts
	lda #<s_items
	ldy #>s_items
	jsr puts
	ldx TEST
	lda BADMASK,x
	jsr putitems
	PRINT 23, 0, s_toggle
	rts

; putitems: the set bits of A as item numbers, " 1 3".
putitems sta MTMP
	ldx #0
pi_lp	lsr MTMP
	bcc pi_nx
	lda #0
	jsr putc
	txa
	clc
	adc #$11
	jsr putc
pi_nx	inx
	cpx #8
	bne pi_lp
	rts

redraw	= tshow			; scrtoggle's text screen

; ---------------------------------------------------------------------------
; final: past the last test. Every test on the tape with a failed item plays,
; A = test, B = item; all passed: one long flash per test.
final	lda #8			; tshow, as redraw, shows the results from here
	sta TEST
	.ifdef MENU
	lda #<menu		; START: back to the menu
	sta CONTVEC
	lda #>menu
	.else
	lda #<trestart		; START: the tape's tests again
	sta CONTVEC
	lda #>trestart
	.endif
	sta CONTVEC+1
	lda #1			; and the result stays up till then
	sta ENDING
	ldx #0
fi_cnt	lda ttests,x
	beq fi_n
	inx
	bne fi_cnt
fi_n	stx NBANKS
	lda DISPOK
	beq fi_chk
	jsr results
	.ifdef CHAIN
fi_chk	ldx #8			; and test 8, the RAM
	.else
fi_chk	ldx #7
	.endif
fi_lp	lda BADMASK,x
	bne fi_bad
	dex
	bne fi_lp
	jmp pass
fi_bad	jmp report

	.ifdef MENU
; ---------------------------------------------------------------------------
; The test menu (16k/48k sets): every test on the tape with its state, then
; ALL (every test in order) and the results. START runs the highlighted
; line, SELECT moves down, OPTION up; keys 1-7 run that test. After a test
; it comes back here with the next one highlighted, so START, START...
; walks the tests forward. It waits as long as it takes: no timeouts.
MSEL	= BSS+$EE		; highlighted line: a ttests index, MNT = ALL,
				; MNT+1 = the results
MMODE	= BSS+$EF		; nonzero: running all of them in order
MRUN	= BSS+$F0		; tests run so far, bit per test number
MNT	= BSS+$F3		; tests on the tape

menu	lda #0
	sta MMODE
	jsr mdraw
	jsr waitrel
mn_lp	jsr vsync
	lda CONSOL
	eor #7
	and #7
	bne mn_con
	lda SKSTAT		; a key: 1-7 runs that test
	and #4
	bne mn_lp
	lda KBCODE
	and #$3F
	.ifdef RAMAGAIN
	cmp #$32		; 0: the RAM test again (the 32k+ tape: tape 1's
	bne mn_n0		; code is still here, intact; it comes back here)
	jsr waitrel
	jmp RAMAGAIN
mn_n0
	.endif
	ldx #6
mn_dig	cmp kdigit,x
	beq mn_d
	dex
	bpl mn_dig
	bmi mn_lp
mn_d	inx			; test number X: its line, if it is on the tape
	txa
	ldx MNT
mn_fd	dex
	bmi mn_lp
	cmp ttests,x
	bne mn_fd
	stx MSEL
	jmp mgo
mn_con	lsr
	bcs mgo			; START
	lsr
	bcc mn_up
	ldx MNT			; SELECT: down (the last line is MNT+1, the
	inx			; results, or MNT+2, the RAM test again),
	.ifdef RAMAGAIN		; round to the top
	inx
	.endif
	stx MTMP
	ldx MSEL
	cpx MTMP
	inx
	bcc mn_set
	ldx #0
	beq mn_set
mn_up	ldx MSEL		; OPTION: up, round to the bottom
	dex
	bpl mn_set
	ldx MNT
	inx
	.ifdef RAMAGAIN
	inx
	.endif
mn_set	stx MSEL
	jmp menu

; mgo: run the highlighted line: a test, all of them, or the results.
mgo	jsr waitrel
	lda #0			; (a pass goes on by itself again)
	sta ENDING
	lda MSEL
	cmp MNT
	bcc mr_t
	beq mr_all
	.ifdef RAMAGAIN
	sbc MNT			; (carry set) 1: the results, 2: the RAM test
	cmp #2
	bne mg_fin
	jmp RAMAGAIN
mg_fin
	.endif
	jmp final
mr_all	inc MMODE		; all, from the first: every result starts clean
	ldx #7			; (not test 8, the RAM stages' result)
	lda #0
	sta MRUN
ma_cl	sta BADMASK,x
	dex
	bne ma_cl
	beq mr_go
mr_t	tax			; one test: its old result goes (a run after a
	ldy ttests,x		; fail must be able to pass)
	lda #0
	sta BADMASK,y
	txa
mr_go	asl
	sta TIDX
	jsr tnextv
	jmp (NEXTVEC)

; mdraw: the menu screen.
mdraw	jsr scr_on
	lda #<s_hmenu
	ldy #>s_hmenu
	jsr header
	lda #2
	jsr machinfo
	ldx #0
md_lp	stx CNT
	lda #0			; the highlighted line in inverse
	cpx MSEL
	bne md_inv
	lda #$80
md_inv	sta INV
	txa
	clc
	adc #4
	ldx #0
	jsr at
	lda #0
	jsr putc
	ldx CNT
	lda ttests,x
	beq md_res
	asl
	tax
	lda tnames-2,x
	ldy tnames-1,x
	jsr puts
	lda CNT			; its state at column 20
	clc
	adc #4
	ldx #20
	jsr at
	ldx CNT
	ldy ttests,x
	lda bitn-1,y
	and MRUN
	bne md_ran
	lda #<s_notrun
	ldy #>s_notrun
	jsr puts
	jmp md_nx
md_ran	lda BADMASK,y
	bne md_f
	lda #<s_pass
	ldy #>s_pass
	jsr puts
	jmp md_nx
md_f	pha
	lda #<s_fail
	ldy #>s_fail
	jsr puts
	pla
	jsr putitems
md_nx	ldx CNT
	inx
	bne md_lp
md_res	lda #<s_mall		; then ALL and the results
	ldy #>s_mall
	jsr puts
	lda #0
	sta INV
	ldx MNT
	inx
	cpx MSEL
	bne md_r
	lda #$80
	sta INV
md_r	txa
	clc
	adc #4
	ldx #0
	jsr at
	lda #0
	jsr putc
	lda #<s_mres
	ldy #>s_mres
	jsr puts
	.ifdef RAMAGAIN		; the 32k+ tape: the RAM test too, as key 0,
	lda #0			; with its result so far (test 8)
	sta INV
	ldx MNT
	inx
	inx
	cpx MSEL
	bne md_g
	lda #$80
	sta INV
md_g	txa
	clc
	adc #4
	ldx #0
	jsr at
	lda #0
	jsr putc
	lda #<s_mram
	ldy #>s_mram
	jsr puts
	lda #0
	sta INV
	ldx MNT
	inx
	inx
	txa
	clc
	adc #4
	ldx #20
	jsr at
	lda BADMASK+8
	bne md_gf
	lda #<s_pass
	ldy #>s_pass
	jsr puts
	jmp md_gx
md_gf	pha
	lda #<s_fail
	ldy #>s_fail
	jsr puts
	pla
	jsr putitems
md_gx
	.endif
	lda #0
	sta INV
	PRINT 18, 0, s_m1
	PRINT 19, 0, s_m2
	rts

kdigit	.byte $1F, $1E, $1A, $18, $1D, $1B, $33	; KBCODEs of 1-7
s_hmenu	dta d'MENU',$FF
s_notrun dta d'-',$FF
s_mall	dta d'ALL OF THEM, IN ORDER',$FF
s_mres	dta d'RESULTS AND THE FINAL CODE',$FF
s_m1	dta d'START=RUN  SELECT=DOWN  OPTION=UP',$FF
	.ifdef RAMAGAIN
s_m2	dta d'OR PRESS 0-7 TO RUN THAT TEST',$FF
s_mram	dta d'0 RAM TEST AGAIN',$FF
	.else
s_m2	dta d'OR PRESS 1-7 TO RUN THAT TEST',$FF
	.endif
s_toggle3 dta d'START=MENU  SELECT=RE-BEEP  OPTION=FLASH',$FF
	.endif

; results: every test on the tape, PASS or FAIL and its items, then the ROM
; names if test 1 ran.
results	jsr scr_on
	lda #<s_hres
	ldy #>s_hres
	jsr header
	lda #2
	jsr machinfo
	ldx #0
rz_lp	stx CNT
	lda ttests,x
	beq rz_end
	txa
	clc
	adc #4
	ldx #0
	jsr at
	ldx CNT
	lda ttests,x
	asl
	tax
	lda tnames-2,x
	ldy tnames-1,x
	jsr puts
	lda CNT
	clc
	adc #4
	ldx #18			; status at column 18
	jsr at
	ldx CNT
	ldy ttests,x
	.ifdef MENU
	lda bitn-1,y		; not run (from the menu)
	and MRUN
	bne rz_ran
	lda #<s_notrun
	ldy #>s_notrun
	jsr puts
	jmp rz_n
rz_ran
	.endif
	lda BADMASK,y
	bne rz_f
	lda #<s_pass
	ldy #>s_pass
	jsr puts
	jmp rz_n
rz_f	pha
	lda #<s_fail
	ldy #>s_fail
	jsr puts
	pla
	jsr putitems
rz_n	ldx CNT
	inx
	bne rz_lp
rz_end	.ifdef CHAIN
	lda CNT			; the 48k tape: RAM from stages 1-2, as test 8
	clc
	adc #4
	ldx #0
	jsr at
	lda #<s_t8
	ldy #>s_t8
	jsr puts
	lda CNT
	clc
	adc #4
	ldx #18
	jsr at
	lda BADMASK+8
	bne rz_rf
	lda #<s_pass
	ldy #>s_pass
	jsr puts
	jmp rz_rd
rz_rf	pha
	lda #<s_fail
	ldy #>s_fail
	jsr puts
	pla
	jsr putitems
rz_rd	inc CNT
	.endif
	.ifdef WANT_ROM
	lda CNT
	clc
	adc #5
	jsr rominfo
	.endif
	PRINT 18, 0, s_items2
	.ifdef MENU
	PRINT 23, 0, s_toggle3	; START: back to the menu
	.else
	PRINT 23, 0, s_toggle4	; START: the tests again
	.endif
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

; hex4: "$" A X (A = high byte).
hex4	pha
	lda #4			; '$'
	jsr putc
	pla
	jsr puthex
	txa
	jmp puthex

bitn	.byte 1, 2, 4, 8, 16, 32, 64, 128

tnames	.word s_t1, s_t2, s_t3, s_t4, s_t5, s_t6, s_t7
s_t1	dta d'1 ROMS',$FF
s_t2	dta d'2 KEYBOARD',$FF
s_t3	dta d'3 CONSOLE KEYS',$FF
s_t4	dta d'4 POKEY',$FF
s_t5	dta d'5 JOYSTICKS',$FF
s_t6	dta d'6 PADDLES',$FF
s_t7	dta d'7 GTIA',$FF
	.ifdef CHAIN
s_t8	dta d'8 RAM, BANKS',$FF
	.endif
s_test	dta d'TEST ',$FF
s_pass	dta d'PASS',$FF
s_fail	dta d'FAIL'*,$FF
s_items	dta d', ITEMS',$FF
s_tpass	dta d'NEXT TEST IN 2 S.  OPTION = FLASH      ',$FF
s_toggle dta d'START=GO ON SELECT=RE-BEEP OPTION=FLASH',$FF
s_toggle4 dta d'START=AGAIN SELECT=RE-BEEP OPTION=FLASH',$FF
s_items2 dta d'FAIL N: ITEM N. THE CODE IS TEST, ITEM.',$FF
s_heard	dta d'HEARD IT? Y/START = YES, N/SELECT = NO',$FF
s_hres	dta d'RESULTS',$FF
