; A8 DIAG tape 2: RAM burn-in.
;
; Boots like tape 1 (alive, image checksum, low RAM, size probe, machine,
; display prerequisites; no video check), then loops the RAM tests over all
; the RAM it can reach until a key is pressed:
;   low RAM (non-destructive), the main banks above this stage, a global
;   address test, and on the XL/XE the RAM under the OS (bank 4, but not
;   page $FF) and the 130XE banks (5-8).
; Not covered: $0800 up to TSTART, where this stage runs (tape 1's stage 2
; tests it), unless built with:
;   OWNTEST (diag-400-burnin): every pass also checks this stage's own RAM.
;     Its image sum must not change from pass 1's (the code changes a few of
;     its own operands as it runs, the same way every pass). Then each page
;     from $0800 up to TSTART is saved in the screen block, given March C-
;     ($00/$FF and $55/$AA) and an address-in-page test, put back and read
;     back: the full patterns, and the code survives. With no display (no
;     tested buffer) this stage's RAM takes a NOT test instead (invert,
;     read back, put back, read back). Then the screen block: a visible
;     sweep, an inverse bar down the screen (see sweep), every pass, in
;     every burn-in build. These tests
;     run from copies in low RAM ($0400-$04FF), written with branches and
;     (zp),y only so they run from anywhere and never test themselves; the
;     VBI and ANTIC are off. Faults go in the log as bank 9 ("B9", this
;     tape's RAM), and beep as bank 1.
;   NOXL (diag-400-burnin): no RAM under the OS, no 130XE banks (an 8K
;     machine is never an XL), which leaves the room for OWNTEST.
;   BOUNCE (diag-burnin, 16K and up): two copies take turns. Copy A runs at
;     $0800; at the end of each pass the running copy writes the other one
;     BOFF pages away (A up, B back down), adds BOFF to every byte the
;     bitmap at BMAP marks (the high bytes of its own addresses; build.py
;     makes the bitmap by assembling at two addresses), copies its BSS page
;     across, reads it all back, and goes on there. Each copy tests the
;     other's RAM in full, march and address tests included, so over two
;     passes every byte from $0800 up is tested, this tape's own RAM too.
;     So one counted pass is A's half and B's half together: the log, the
;     pass number and the border all go by the pair. The distance is BOFF
;     on the 400/800, BOFFXL on the XL/XE: there copy B sits at $8000, out
;     of the 130XE's banking window ($4000-$7FFF), which the extended-bank
;     test switches away from under the CPU. Both are whole 1K blocks, and
;     the bitmap works for any such distance (no page number overflows).
;     Without the RAM for copy B (it needs about 20K), A gives its own RAM
;     the OWNTEST checks instead (BOUNCE builds include OWNTEST).
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
	.ifdef BOUNCE
FONT	= LOAD+$3000		; ROM font copy while the OS is out (moves with
				; the copy; BOFF is a whole number of 1K blocks)
REGLO	= BSS+$F4		; bankrange: the region, pages [REGLO, REGHI)
REGHI	= BSS+$F5
XOFF	= BSS+$F6		; the distance to copy B, pages: BOFF or BOFFXL
BOFFXL	= $78			; XL/XE: copy B at $8000
BMP	= $88			; bcopy: bitmap pointer, its byte, its bit,
BMB	= $8A			; bytes left, write (0) or read back, the
BMK	= $8B			; offset in pages, a read-back failed
BLEFT	= $8C
BVER	= $8E
BDIR	= $8F
BFAIL	= $90
	.else
FONT	= $3800			; ROM font copy while the OS is switched out
	.endif
	.ifdef OWNTEST
LDRFOLD	= 1			; report.asm: bank 9 (own RAM) beeps as bank 1
REFSUM	= BSS+$F1		; 2: pass 1's image sum
REFOK	= BSS+$F3		; nonzero: REFSUM is set
	.endif

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
	.ifdef BOUNCE
LOAD	= BLOAD			; build.py: $0800 (and $0C00 for the bitmap)
	.else
LOAD	= $0800
	.endif
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
	.ifdef BOUNCE
	lda #BOFF
	ldx MACHINE
	beq bi_off
	lda #BOFFXL
bi_off	sta XOFF
	.endif
	.ifdef OWNTEST
	ldx #0			; the page and NOT tests into low RAM
nt_cp	lda pgsrc,x
	sta PGCODE,x
	inx
	cpx #PICLEN
	bne nt_cp
	.endif
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
pass1
	.ifdef BOUNCE
	lda #>LOAD		; copy B: the second half of A's pass, which
	cmp #$08		; goes on as it is
	beq ps_a
	jmp ps_half
ps_a
	.endif
	inc PASSNO
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

ps_half	lda #<s_low		; low RAM, with the VBI off
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
	.ifdef OWNTEST
	jsr owntest
	jsr sweep
	.endif
	lda #$40
	sta NMIEN

	.ifdef BOUNCE
	lda #$08		; main banks: below this copy (copy B: A's RAM)
	sta REGLO
	lda #>LOAD
	sta REGHI
	jsr banks
	lda #TSTART		; and above it
	sta REGLO
	lda RAMTOP
	sta REGHI
	jsr banks
	lda RAMTOP		; one flash per 16K bank, at the end
	clc
	adc #$3F
	asl
	rol
	rol
	and #3
	sta NBANKS
	lda #<s_aia		; address-in-address, each region
	ldy #>s_aia
	jsr step
	lda #>LOAD
	cmp #$09
	bcc ps_ai2
	lda #$08
	sta RBS
	lda #>LOAD
	sta RBE
	jsr aiarun
ps_ai2	lda #TSTART
	sta RBS
	lda RAMTOP
	sta RBE
	jsr aiarun
	jmp ps_xl
	.endif
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

ps_xl
	.ifndef NOXL
	lda MACHINE
	beq ps_end
	lda #0
	sta OSRAM
	sta XERAM
	jsr underos
	jsr xebanks
	.endif

ps_end
	.ifdef BOUNCE
	jsr halfa		; copy A's half with copy B to come: the log, and
	bcc ps_log		; a stop, wait for B's half (the pass in progress
	jsr bounce		; is the pair)
	lda STOPREQ		; (the copy didn't read back: A goes on alone)
	beq ps_ag
	jsr logpass
	jmp stop
ps_ag	jmp pass1
ps_log
	.endif
	jsr logpass
	jsr pulse
	lda DISPOK
	beq ps_next
	jsr showpass
	jsr showlog
ps_next	lda STOPREQ
	bne stop
	.ifdef BOUNCE
	jsr bounce		; on to the other copy, if there is room for it
	.endif
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

	.ifndef NOXL
; Progress hooks for xlram.asm.
osprog	lda #<s_os
	ldy #>s_os
	jmp step
xeprog	lda #<s_xe
	ldy #>s_xe
	jmp step
	.endif

	.ifdef BOUNCE
; banks: the march over banks 1-3, each clipped to [REGLO, REGHI).
banks	lda #1
	sta CURBANK
bk_lp	jsr bankrange
	bcs bk_nb
	lda #<s_bank
	ldy #>s_bank
	jsr step
	lda CURBANK
	clc
	adc #$10
	jsr putc_s
	jsr split
	lda RNGN
	beq bk_nb
	jsr setfmask
	jsr march2
bk_nb	inc CURBANK
	lda CURBANK
	cmp #4
	bne bk_lp
	rts

; aiarun: address-in-address over [RBS, RBE), both modes.
aiarun	jsr split
	inc INAIA
	lda #0
	sta AIAMODE
	jsr aia
	inc AIAMODE
	jsr aia
	dec INAIA
	rts

; halfa: C set if this is copy A and copy B fits (A's pass is half a pass).
halfa	lda #>LOAD
	cmp #$08
	bne ha_no
	jmp broom
ha_no	clc
	rts

; broom: C set if the RAM reaches copy B's screen block (its last page).
broom	lda #SCR1+4
	clc
	adc XOFF
	sta MTMP
	lda RAMTOP
	cmp MTMP
	rts

; bounce: write the other copy and go on there. Copy A goes up to B if the
; RAM reaches B's screen block; B always comes back down. The VBI is off
; while the image and the BSS page (clock included) are copied and read
; back; the clock gets the time back as an allowance.
bounce	lda #>LOAD
	cmp #$08
	bne bo_dn
	jsr broom
	bcc bo_x
	lda XOFF
	bne bo_go
bo_dn	lda #0
	sec
	sbc XOFF
bo_go	sta BDIR
	lda #0
	sta NMIEN
	ldx #24			; the time the copy takes, about 0.4 s, first:
bo_t	jsr tick		; the clock goes across with the BSS page
	dex
	bne bo_t
	lda #0
	sta BVER
	sta BFAIL
	jsr bcopy
	inc BVER
	jsr bcopy
	lda BFAIL
	beq bo_sw
	lda #$40		; the copy didn't read back: stay here (the next
	sta NMIEN		; pass's march finds that RAM)
bo_x	rts
bo_sw	lda #<vbios		; the VBI and the code: the other copy's
	sta VVBLKI
	lda #>vbios
	clc
	adc BDIR
	sta VVBLKI+1
	lda #<resume
	sta PTR
	lda #>resume
	clc
	adc BDIR
	sta PTR+1
	jmp (PTR)

; resume: here in the other copy. Its own screen block, then the next pass.
resume	ldx #$FF
	txs
	lda DISPOK
	beq rs_vbi
	lda #SCR1
	sta SCRPG
	jsr scr_on
	jsr bscreen
	jsr showpass
	jsr showlog
rs_vbi	lda #$40
	sta NMIEN
	jmp pass1

; bcopy: BVER 0: write this copy's image BDIR pages away, plus BDIR on
; every byte the bitmap marks; then the rest (the bitmap, padding, BSS page)
; as is. BVER 1: read it all back the same way, BFAIL nonzero on a miss.
bcopy	lda #0
	sta PTR
	sta SPTR
	sta BMK			; (0: fetch a bitmap byte first)
	lda #>LOAD
	sta PTR+1
	clc
	adc BDIR
	sta SPTR+1
	lda #<BMAP
	sta BMP
	lda #>BMAP
	sta BMP+1
	lda #<[BMAP-LOAD]
	sta BLEFT
	lda #>[BMAP-LOAD]
	sta BLEFT+1
	ldy #0
bc_lp	lda BMK
	bne bc_hb
	lda (BMP),y
	sta BMB
	inc BMP
	bne bc_m1
	inc BMP+1
bc_m1	lda #1
	sta BMK
bc_hb	lda BMB
	and BMK
	beq bc_raw
	lda (PTR),y
	clc
	adc BDIR
	jmp bc_put
bc_raw	lda (PTR),y
bc_put	jsr bc_st
	asl BMK
	jsr bc_inc
	bne bc_lp
	lda #<[BSS+$100-BMAP]	; the rest, as is
	sta BLEFT
	lda #>[BSS+$100-BMAP]
	sta BLEFT+1
bc_r	lda (PTR),y
	jsr bc_st
	jsr bc_inc
	bne bc_r
	rts
; bc_st: store A at (SPTR), or compare it there.
bc_st	ldx BVER
	bne bc_cmp
	sta (SPTR),y
	rts
bc_cmp	cmp (SPTR),y
	beq bc_ok
	inc BFAIL
bc_ok	rts
; bc_inc: both pointers on, one byte less to go. Z set at the end.
bc_inc	inc PTR
	bne bc_i1
	inc PTR+1
bc_i1	inc SPTR
	bne bc_i2
	inc SPTR+1
bc_i2	lda BLEFT
	bne bc_i3
	dec BLEFT+1
bc_i3	dec BLEFT
	lda BLEFT
	ora BLEFT+1
	rts
	.endif

	.ifdef OWNTEST
; owntest: this stage's own RAM (called with the VBI off). The image sum
; first, then the page test over $0800 up to TSTART (the NOT test without a
; display), then the NOT test over the screen block, with ANTIC off (the
; display list is in that block; the screen is redrawn after). The clock
; gets the time back as a fixed allowance, like the low RAM test.
owntest
	.ifdef BOUNCE
	lda #>LOAD		; copy B, or A with copy B coming: the bounce
	cmp #$08		; tests this RAM in full
	bne ot_no
	jsr broom
	bcc ot_go
ot_no	rts
ot_go
	.endif
	lda #0
	sta NTERR
	sta SUM
	sta SUM+1
	sta PTR
	lda #>LOAD
	sta PTR+1
	ldy #0
ot_sum	lda (PTR),y		; every image byte but the stored sum
	clc
	adc SUM
	sta SUM
	bcc ot_nc
	inc SUM+1
ot_nc	iny
	bne ot_s1
	inc PTR+1
ot_s1	lda PTR+1
	cmp #>CKSUM
	bne ot_sum
	cpy #<CKSUM
	bne ot_sum
	lda REFOK		; pass 1: this is the reference
	bne ot_cmp
	inc REFOK
	lda SUM
	sta REFSUM
	lda SUM+1
	sta REFSUM+1
ot_cmp	lda SUM			; changed: the bits that differ, as a hint
	eor REFSUM
	sta NTERR
	lda SUM+1
	eor REFSUM+1
	ora NTERR
	sta NTERR
	lda #0			; (the display stays on: the top rows show the
	sta NTPTR		; save page at work)
	sta BUFP
	lda #>LOAD
	sta NTPTR+1
	ldx #TSTART-[>LOAD]
	lda DISPOK		; no display: no tested save page, the NOT test
	bne ot_pg0
	jsr NTCODE
	ldx #9			; about 0.15 s
	bne ot_end
ot_pg0	lda SCRPG		; the page test, page by page
	sta BUFP+1
ot_pg	jsr PGCODE
	inc NTPTR+1
	dex
	bne ot_pg
	lda SCRON		; the screen back: it was the save page
	beq ot_nt
	jsr scr_on
	jsr bscreen
	jsr showpass
	jsr showlog
ot_nt	ldx #60			; about 1 s
ot_end	lda NTERR
	ora BADMASK+LDRIDX
	sta BADMASK+LDRIDX
ot_t	jsr tick
	dex
	bne ot_t
	rts

; sweep: the screen block, with the display on so the test can be seen.
; Row by row: the row saved in ROWBUF, inverted (read back), held inverted
; two frames, read again (bits that didn't hold), put back (read back): an
; inverse bar runs down the screen. Then the display list, NOT-tested in
; the vertical blank, while ANTIC isn't reading it. Called with the VBI off:
; it counts its own frames on the clock.
ROWBUF	= PICBASE+$C8		; 40 bytes, after the page and NOT tests
sweep	lda DISPOK
	beq sw_no
	lda SCRON
	bne sw_go
sw_no	rts
sw_go	lda #0
	sta NTERR
	sta NTPTR
	lda SCRPG
	sta NTPTR+1
	ldx #24
sw_row	ldy #39
sw_inv	lda (NTPTR),y		; save, invert, read back
	sta ROWBUF,y
	eor #$FF
	sta (NTPTR),y
	eor (NTPTR),y
	ora NTERR
	sta NTERR
	dey
	bpl sw_inv
	jsr swframe
	jsr swframe
	ldy #39
sw_bk	lda ROWBUF,y		; still inverted? then back, read back
	eor #$FF
	eor (NTPTR),y
	ora NTERR
	sta NTERR
	lda ROWBUF,y
	sta (NTPTR),y
	eor (NTPTR),y
	ora NTERR
	sta NTERR
	dey
	bpl sw_bk
	lda NTPTR		; the next row
	clc
	adc #40
	sta NTPTR
	bcc sw_nc
	inc NTPTR+1
sw_nc	dex
	bne sw_row
sw_vb	lda VCOUNT		; the display list, $3C0-$3FF: in the blank
	cmp #124
	bcc sw_vb
	lda #0			; (the rows left NTPTR at +$3C0)
	sta NTPTR
	lda SCRPG
	clc
	adc #3
	sta NTPTR+1
	ldy #$C0
sw_dl	lda (NTPTR),y
	sta NTSAV
	eor #$FF
	sta (NTPTR),y
	eor (NTPTR),y
	ora NTERR
	sta NTERR
	lda NTSAV
	sta (NTPTR),y
	eor (NTPTR),y
	ora NTERR
	sta NTERR
	iny
	bne sw_dl
	lda NTERR
	ora BADMASK+LDRIDX
	sta BADMASK+LDRIDX
sw_x	rts
; swframe: wait for the next frame, and count it (the VBI is off).
swframe	lda VCOUNT
	cmp #124
	bcc swframe
sf_2	lda VCOUNT
	cmp #124
	bcs sf_2
	jmp tick

	icl '../common/pagetest.asm'
	.endif

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
	.ifdef BOUNCE
	cmp REGLO
	bcs br_s
	lda REGLO
	.else
	cmp #TSTART
	bcs br_s
	lda #TSTART
	.endif
br_s	sta RBS
	lda CURBANK
	asl
	asl
	asl
	asl
	asl
	asl
	.ifdef BOUNCE
	cmp REGHI
	bcc br_e
	lda REGHI
	.else
	cmp RAMTOP
	bcc br_e
	lda RAMTOP
	.endif
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
	.ifndef NOXL
	icl '../common/xlram.asm'
	.endif

	.ifdef NOXL			; the tape's name
s_hpre	dta d' DIAG-400-MEMTEST  ',$FF
	.else
s_hpre	dta d' DIAG-MEMTEST  ',$FF
	.endif
s_hburn	dta d'MEMTEST',$FF
s_hsum	dta d'SUMMARY',$FF
s_legend dta d'BANK BIT  FIRST  FAILED/PASSES',$FF
s_stop	dta d'KEY = STOP AFTER THIS PASS',$FF
s_stopping dta d'STOPPING AFTER THIS PASS  ',$FF
s_now	dta d'NOW: ',$FF
s_low	dta d'LOW RAM $0000-$07FF',$FF
s_bank	dta d'BANK ',$FF
s_aia	dta d'ADDRESS TEST',$FF
	.ifndef NOXL
s_os	dta d'UNDER THE OS',$FF
s_xe	dta d'130XE BANKS 5-8',$FF
	.endif
s_pass	dta d'PASS ',$FF
s_time	dta d'   TIME ',$FF
s_first	dta d'  FIRST ',$FF
s_failed dta d'  FAILED ',$FF
s_int	dta d' INTERMITTENT',$FF
s_more2	dta d' MORE',$FF
s_result dta d'RESULT: ',$FF
s_noerr	dta d'NO ERRORS',$FF
s_nsol	dta d' SOLID, ',$FF
s_nextok dta d'ALL PASSED',$FF
s_nextbad dta d'FIX SOLID ONES FIRST',$FF
s_toggle2 dta d'SELECT=RE-BEEP  OPTION=FULL-SCREEN FLASH',$FF

	.ifdef BOUNCE
; The relocation bitmap: one bit per image byte before BMAP, LSB first; set
; for the bytes that hold this copy's own page numbers (build.py).
BMAP	ins '../../build/bounce.bmap'
	.endif

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
