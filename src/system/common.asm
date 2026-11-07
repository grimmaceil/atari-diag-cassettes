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
ANSTO	= BSS+$EB		; 2: yes/no timeout, frames
TIDX	= BSS+$ED		; next tlist entry, times 2
T3D	= BSS+$70		; 96 bytes of test data:
RTIME	= T3D+$00		; 2: frames left in a timed wait
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
	jsr tnextv
	jmp (NEXTVEC)

; tend: the end of a test: its result, then the next one on the list.
tend	jsr tnextv
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

; yesno: wait up to ~15 s for an answer. C set: Y or START. C clear: N,
; SELECT or no answer. Console keys too, so a dead keyboard can answer.
yesno	jsr waitrel
	lda #<[15*60]
	sta ANSTO
	lda #>[15*60]
	sta ANSTO+1
yn_lp	jsr vsync
	lda SKSTAT		; a key held?
	and #4
	bne yn_con
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
	lda ANSTO
	bne yn_dec
	dec ANSTO+1
yn_dec	dec ANSTO
	lda ANSTO
	ora ANSTO+1
	bne yn_lp
yn_no	jsr waitrel
	clc
	rts
yn_yes	jsr waitrel
	sec
	rts

; settime: RTIME = A seconds (in frames).
settime	tax
	lda #0
	sta RTIME
	sta RTIME+1
rt_lp	lda RTIME
	clc
	adc #60
	sta RTIME
	bcc rt_nc
	inc RTIME+1
rt_nc	dex
	bne rt_lp
	rts
; rtick: count a frame off RTIME. Z set when it runs out.
rtick	lda RTIME
	bne rk_d
	dec RTIME+1
rk_d	dec RTIME
	lda RTIME
	ora RTIME+1
	rts

; tresult: the end of test TEST. A pass gives the jingle and goes on after
; ~2 s (OPTION holds it). A fail plays that test's code (only that one) and
; waits for START, a key or fire; then the flow goes on at NEXTVEC.
tresult	jsr tshow
	ldx TEST
	lda BADMASK,x
	bne tr_fail
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
	PRINT 23, 0, s_tpass
ts_x	rts
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
	lda #0
	sta CONTVEC+1
	ldx #0
fi_cnt	lda ttests,x
	beq fi_n
	inx
	bne fi_cnt
fi_n	stx NBANKS
	lda DISPOK
	beq fi_chk
	jsr results
fi_chk	ldx #7
fi_lp	lda BADMASK,x
	bne fi_bad
	dex
	bne fi_lp
	jmp pass
fi_bad	jmp report

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
rz_end	.ifdef WANT_ROM
	lda CNT
	clc
	adc #5
	jsr rominfo
	.endif
	PRINT 18, 0, s_items2
	PRINT 23, 0, s_toggle2
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
s_test	dta d'TEST ',$FF
s_pass	dta d'PASS',$FF
s_fail	dta d'FAIL'*,$FF
s_items	dta d', ITEMS',$FF
s_tpass	dta d'NEXT TEST IN 2 S.  OPTION = FLASH      ',$FF
s_toggle dta d'START=GO ON  SELECT=REPLAY  OPTION=FLASH',$FF
s_toggle2 dta d'SELECT=REPLAY  OPTION=FULL-SCREEN FLASH',$FF
s_items2 dta d'FAIL N: ITEM N. THE CODE IS TEST, ITEM.',$FF
s_heard	dta d'HEARD IT? Y/START = YES, N/SELECT = NO',$FF
s_hres	dta d'RESULTS',$FF
