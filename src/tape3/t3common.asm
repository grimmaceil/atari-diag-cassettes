; Tape 3 shared code (both stages): the per-test result flow, frame sync,
; yes/no answers, the test-result screen.
;
; Each test leaves its failed items in BADMASK[test] (item n = bit n-1), so
; the reporter plays A = test number, B = item, as the brief has it.

; Tape 3 runs no RAM tests, so its own data lives in the first-error arrays
; ($70-$CF of the BSS page), which only merr writes. (qscr uses ECNTLO.)
TEST	= BSS+$E0		; current test, 1-7
NEXTVEC	= BSS+$E1		; 2: where the test flow goes on to
STASH	= BSS+$E3		; 8: BADMASK 1-8 while one test's code plays
ANSTO	= BSS+$EB		; 2: yes/no timeout, frames
T3D	= BSS+$70		; 96 bytes of test data (each stage its own use)

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

; tshow: the result lines of test TEST on rows 21-23 (the test's own screen
; stays above). Also scrtoggle's redraw.
tshow	lda TEST		; 8: past the last test, the stage's summary
	cmp #8
	bne ts_t
	jmp sushow
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
	ldx TEST		; the failed items, as numbers
	lda BADMASK,x
	sta MTMP
	ldx #0
ts_it	lsr MTMP
	bcc ts_nx
	lda #0
	jsr putc
	txa
	clc
	adc #$11
	jsr putc
ts_nx	inx
	cpx #8
	bne ts_it
	PRINT 23, 0, s_toggle
	rts

redraw	= tshow			; scrtoggle's text screen

; clrrow: blank row A.
clrrow	ldx #0
	jsr at
	ldx #40
	lda #0
cr_lp	jsr putc
	dex
	bne cr_lp
	rts

tnames	.word s_t1, s_t2, s_t3, s_t4, s_t5, s_t6, s_t7
s_t1	dta d'1 ROM CHECKSUMS',$FF
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
