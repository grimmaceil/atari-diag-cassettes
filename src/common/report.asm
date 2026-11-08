; Abstract reporter: border flashes paired with beeps.
; Uses no stack and no zero page, so it can report a low-RAM failure. Calls go
; through NCALL, which keeps the return address in a BSS vector; each call
; level has its own vector, so levels nest but don't recurse.

; No-stack call: NCALL vector, target. The callee returns with JMP (vector).
; Clobbers A.
.macro NCALL
	lda #<ret
	sta :1
	lda #>ret
	sta :1+1
	jmp :2
ret
.endm

; WAITMS ms: busy-wait about that many milliseconds. Clobbers A/X/Y.
; delay counts X + 256*(Y-1) scanlines, so Y is the scanline count
; rounded up to whole pages.
.macro WAITMS
	ldx #<[:1*157/10]
	ldy #>[:1*157/10+255]
	NCALL RET2, delay
.endm

; BEEP n: one flash+beep from the tone table (T_* below), then 200 ms
; dark and silent.
.macro BEEP
	ldx #:1
	NCALL RET1, tone
.endm

C_FLASH	= C_RED+4	; fail flash: brighter than the steady fail color
C_GFLASH = C_GREEN+4

; Tone table: frequency, flash color, length.
T_ALONG	= 0		; group A: long, red
T_BSHORT = 1		; group B: short, red
T_END	= 2		; end of list: low, long, red
T_J1	= 3		; pass jingle, green
T_J2	= 4
T_J3	= 5
T_GLONG	= 6		; pass: one long green flash per bank
tt_frq	.byte F_LONG, F_SHORT, F_END, F_J1, F_J2, F_J3, F_LONG
tt_col	.byte C_FLASH, C_FLASH, C_FLASH, C_GFLASH, C_GFLASH, C_GFLASH, C_GFLASH
tt_lx	.byte <[600*157/10], <[200*157/10], <[600*157/10], <[100*157/10], <[100*157/10], <[300*157/10], <[600*157/10]
tt_ly	.byte >[600*157/10+255], >[200*157/10+255], >[600*157/10+255], >[100*157/10+255], >[100*157/10+255], >[300*157/10+255], >[600*157/10+255]

; ---------------------------------------------------------------------------
; delay: X + 256*(Y-1) scanlines, timed by WSYNC. While SPKMASK=$08 it also
; drives the console speaker at ~980 Hz, so a beep is still heard if POKEY is
; dead. (The OS keyclick drives CONSOL the same way.) Returns via RET2.
delay
dl_lp	sta WSYNC
	txa
	and #7
	bne dl_nt
	lda SPKPH
	eor SPKMASK
	sta SPKPH
	sta CONSOL
dl_nt	dex
	bne dl_lp
	dey
	bne dl_lp
	jmp (RET2)

; tone: flash and beep tone X of the table, then 200 ms black and silent.
; Returns via RET1.
tone	lda tt_col,x
	sta COLBK
	lda tt_frq,x
	sta AUDF1
	lda #AUD_ON
	sta AUDC1
	lda #$08
	sta SPKMASK
	ldy tt_ly,x
	lda tt_lx,x
	tax
	NCALL RET2, delay
	lda #AUD_OFF
	sta AUDC1
	lda #0
	sta SPKMASK
	lda #$08
	sta SPKPH
	sta CONSOL
	lda #C_BLACK
	sta COLBK
	WAITMS 200
	jmp (RET1)

; ---------------------------------------------------------------------------
; report: the failure code, repeated until a press continues to CONTVEC
; (when set; never before low RAM passes). Without CONTVEC it never returns.
;   for each bad bank (1-4 main, 5-8 130XE): A = bank number (long), then
;   for each bad bit,
;   B = bit number 1-8 (short), then the low end-of-list tone.
;   Between repeats the border holds steady red for 3 s.
; A bad image checksum reports as A = 1 then the end tone, with no B groups:
; the RAM the loader landed in is suspect but no bit is known.
report	lda #AUD_OFF
	sta AUDC1
	lda #C_RED
	sta COLBK
	WAITMS 1000

rp_top	lda LOADERR
	beq rp_banks
	BEEP T_ALONG
	WAITMS 800
	BEEP T_END
	jmp rp_wait

rp_banks lda #1
	sta RBANK
rp_bank	ldx RBANK
	lda BADMASK,x
	.if .def LDRFOLD
	cpx #1			; the loader area is part of bank 1
	bne rp_fold
	ora BADMASK+LDRIDX
rp_fold	cmp #0			; the CPX changed Z
	.endif
	bne rp_have
	jmp rp_next
rp_have	sta RMASK
	lda RBANK
	sta RCNT
rp_along BEEP T_ALONG
	dec RCNT
	bne rp_along
	WAITMS 800		; +200 after the last tone = 1 s between groups

	lda #0
	sta RBIT
rp_bit	lsr RMASK		; D0 first, reported as 1
	bcc rp_nobit
	ldx RBIT
	inx
	stx RCNT
rp_bshort BEEP T_BSHORT
	dec RCNT
	bne rp_bshort
	WAITMS 800
rp_nobit inc RBIT
	lda RBIT
	cmp #8
	bne rp_bit

	BEEP T_END
	WAITMS 800
rp_next	inc RBANK
	lda RBANK
	cmp #9			; banks 1-8
	beq rp_wait
	jmp rp_bank

rp_wait	lda #30
	sta RCNT
	.if .def RPCOLVAR
	lda RPCOL		; the stage picks the steady color (burn-in: yellow
	.else			; when every error was intermittent)
	lda #C_RED
	.endif
	sta HOLDC
	NCALL RET1, hold
	jmp rp_top

; ---------------------------------------------------------------------------
; pass: rising jingle. With a continue vector: hold green ~2 s, then go on.
; Without (the end of the tape): every ~5 s one long green flash per bank
; tested, steady green between, forever.
pass	BEEP T_J1
	BEEP T_J2
	BEEP T_J3
	lda #20
	sta RCNT
	lda #C_GREEN
	sta HOLDC
	NCALL RET1, hold
	lda CONTVEC+1
	beq pa_top
	.ifdef RESTART
	lda ENDING		; the system tapes' end: START goes on (again),
	bne pa_top		; nothing goes on by itself
	.endif
	jmp (CONTVEC)
pa_top	lda NBANKS
	sta RCNT
pa_long	BEEP T_GLONG
	dec RCNT
	bne pa_long
	lda #50
	sta RCNT
	lda #C_GREEN
	sta HOLDC
	NCALL RET1, hold
	jmp pa_top

; hold: border = HOLDC for RCNT tenths of a second (set HOLDC before the
; NCALL: NCALL itself clobbers A). Once low RAM has passed (STACKOK) it
; also reads the controls; a press only counts after all of them have been
; seen released, so a stuck key does nothing:
;   START, any key, fire   go on to CONTVEC (if one is set)
;   SELECT                 end the pause: replay the code now
;   OPTION                 text <-> full-screen flashes (if the display
;                          checks passed); holding it holds the result
; Before low RAM passes STACKOK is 0 and no JSR runs. Returns via RET1.
hold	lda #0
	sta HARMED
ho_lp	lda HOLDC
	sta COLBK
	WAITMS 100
	lda STACKOK
	beq ho_n
	jsr inputs
	bne ho_in
	lda #1			; all released
	sta HARMED
	bne ho_n
ho_in	ldx HARMED
	beq ho_n
	lsr			; bit 0: go on
	bcc ho_sel
	ldx CONTVEC+1
	beq ho_n
	jsr waitrel
	jmp (CONTVEC)
ho_sel	lsr			; bit 1: SELECT
	bcc ho_opt
	jsr waitrel
	jmp (RET1)
ho_opt	lda DISPOK		; bit 2: OPTION
	beq ho_n
	jsr scrtoggle
ho_n	dec RCNT
	bne ho_lp
	jmp (RET1)

; inputs: A = bit 0 go on (START, a key, fire 0/1), bit 1 SELECT,
; bit 2 OPTION. Zero (Z set) when nothing is pressed.
inputs	lda CONSOL		; 0 = pressed
	eor #7
	and #7
	sta INB
	lda SKSTAT		; bit 2 = 0 while a key is held
	and #4
	beq in_go
	lda TRIG0
	and TRIG1
	and #1
	bne in_x
in_go	lda INB
	ora #1
	sta INB
in_x	lda INB
	rts

; waitrel: wait until every control is released.
waitrel	jsr inputs
	bne waitrel
	rts

; scrtoggle: text results <-> full-screen flashes (ANTIC off, easier to
; read when the picture is garbled). redraw is the stage's results screen.
scrtoggle lda SCRON
	beq tg_on
	jsr scr_off
	jmp waitrel
tg_on	jsr redraw
	jmp waitrel
