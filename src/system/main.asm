; A8 DIAG system tapes: one boot stage that runs a list of tests. build.py
; picks the tests with WANT_* defines, and SETNO/TAPENO for the header:
;   1 ROMs (WANT_ROM)            identified by CRC32 against published tables
;   2 keyboard (WANT_KB)         stuck keys, then a map with three key states
;   3 console keys (WANT_CON)    START, SELECT, OPTION and the console speaker
;   5 joysticks (WANT_JOY)       live, per port
;   6 paddles (WANT_PAD)         open-input check, then live values
;   4 POKEY (WANT_POK)           timer IRQ, RANDOM, the four voices by ear
;   7 GTIA (WANT_GTIA)           luminance and hue ramps by eye
; They run in that order (progressive: the Y/N answers later tests ask for
; come from the keyboard and console keys tested before them). The numbers
; are the brief's, so a test's beep code is the same on every tape.
;
; Boots like the other tapes (alive, image checksum, low RAM, size probe,
; machine, display prerequisites). The screen block gets a quick test only:
; tape 1 tests RAM. The image must fit an 8K 400 (display.asm checks).
;
; A test that passes plays the jingle and goes on by itself (~2 s). One that
; fails shows which items failed and plays A = test number, B = item, until
; START, a key or fire; SELECT replays it, OPTION switches to full-screen
; flashes. After the last test, the tape's results and the final code.
;
; CHAIN (the 48k tape): not a boot file but stage 3 of tape 1, loaded at $4000
; by its stage 2 once the RAM it needs has passed. It takes over stage 2's
; results; their RAM faults become test 8, item = bank, on the results
; screen and in the final code. Built with -d:PREVBSS=... (stage 2's BSS).

	icl '../common/hw.asm'
	icl '../common/vars.asm'
	icl '../common/faults.asm'

QUICKSCR = 1			; display.asm: quick screen-block test
RESTART	= 1			; report.asm: the end waits for START (see final)

	opt h-
	.ifdef SYSLOAD
LOAD	= SYSLOAD		; the 48k+ one-load tape: in the payload, right
				; after stage 2's BSS page (build.py)
	.elseif .def SYSAT
LOAD	= SYSAT			; the 32k+ one-load tape: in tape 1's image,
				; after its stage 2 (build.py's build_one32)
	.elseif .def CHAIN
LOAD	= $4000
	.else
LOAD	= $0800
	.endif
	org LOAD

	.ifdef CHAIN
; Same header layout as a boot file: the loader checks the record count and
; load address, then jumps to LOAD+6.
	.byte 0
	.byte NREC
	.word LOAD
	.word 0

	sei
	cld
	ldx #$FF
	txs
	ldx #0			; take over stage 2's results
ch_tk	lda PREVBSS,x
	sta BSS,x
	inx
	bne ch_tk
	lda #0			; RAM faults (banks 1-8; the loader area is
	sta MTMP		; bank 1) into test 8, item = bank
	ldx #8
ch_rm	lda BADMASK,x
	beq ch_rn
	lda bitn-1,x
	ora MTMP
	sta MTMP
	lda #0
	sta BADMASK,x
ch_rn	dex
	bne ch_rm
	lda BADMASK+LDRIDX
	beq ch_r9
	lda #1
	ora MTMP
	sta MTMP
	lda #0
	sta BADMASK+LDRIDX
ch_r9	lda MTMP
	sta BADMASK+8
	jmp trun
	.else
; Cassette boot header. The OS reads NREC records to LOAD, then JSRs LOAD+6.
	.byte 0
	.byte NREC
	.word LOAD
	.word init_rts

	icl '../common/boot.asm'

	jsr detect
	jsr dprereq
	jmp trun
	.endif

; The tests, in running order, then final. ttests: their numbers, 0 ends.
tlist
	.ifdef WANT_ROM
	.word t_rom
	.endif
	.ifdef WANT_KB
	.word t_kb
	.endif
	.ifdef WANT_CON
	.word t_con
	.endif
	.ifdef WANT_JOY
	.word t_joy
	.endif
	.ifdef WANT_PAD
	.word t_pad
	.endif
	.ifdef WANT_POK
	.word t_pok
	.endif
	.ifdef WANT_GTIA
	.word t_gtia
	.endif
	.word final

ttests
	.ifdef WANT_ROM
	.byte 1
	.endif
	.ifdef WANT_KB
	.byte 2
	.endif
	.ifdef WANT_CON
	.byte 3
	.endif
	.ifdef WANT_JOY
	.byte 5
	.endif
	.ifdef WANT_PAD
	.byte 6
	.endif
	.ifdef WANT_POK
	.byte 4
	.endif
	.ifdef WANT_GTIA
	.byte 7
	.endif
	.byte 0

	.ifdef WANT_ROM
	icl 't_rom.asm'
	.endif
	.ifdef WANT_KB
	icl 't_kb.asm'
	.endif
	.ifdef WANT_CON
	icl 't_con.asm'
	.endif
	.ifdef WANT_JOY
	icl 't_joy.asm'
	.endif
	.ifdef WANT_PAD
	icl 't_pad.asm'
	.endif
	.ifdef WANT_POK
	icl 't_pok.asm'
	.endif
	.ifdef WANT_GTIA
	icl 't_gtia.asm'
	.endif

	.ifndef CHAIN
	icl '../common/display.asm'

init_rts rts

; Low-RAM patterns: solid, checkerboard, walking 1, walking 0.
pats	.byte $00,$FF,$55,$AA
	.byte $01,$02,$04,$08,$10,$20,$40,$80
	.byte $FE,$FD,$FB,$F7,$EF,$DF,$BF,$7F
NPAT	= *-pats
	.endif

	icl '../common/report.asm'
	icl '../common/screen.asm'
	icl '../common/info.asm'
	icl 'common.asm'

; The header bar names the tape, as its file is named (SETNO 0 = the 400
; set, 1 = 16K, 2 = the old 48k tape, 3 = controls, 4 = 32k+), so it can't
; be taken for the machine found: that is the FOUND line below it.
	.if SETNO=2
s_hpre	dta d' DIAG-48K-XL-XE  ',$FF
	.elseif SETNO=4
s_hpre	dta d' DIAG-32K-XL-XE  ',$FF
	.elseif SETNO=3
s_hpre	dta d' DIAG-CONTROLS  ',$FF
	.elseif SETNO=1
s_hpre	dta d' DIAG-16K-02-SYSTEM  ',$FF
	.else
s_hpre	dta d' DIAG-400-0',[TAPENO+$10]
	.if TAPENO=2
	dta d'-ROM  ',$FF
	.elseif TAPENO=3
	dta d'-INPUT  ',$FF
	.elseif TAPENO=4
	dta d'-PORTS  ',$FF
	.else
	dta d'-AV  ',$FF
	.endif
	.endif

; Pad to a whole page; the last two bytes hold the image sum (mkcas.py).
PADTO	= [[*+2+$FF]/$100]*$100
	.if PADTO-*-2>0
	:[PADTO-*-2] .byte 0
	.endif
CKSUM	.word 0			; (as stage 3: the loader's plain sum)
IMGEND
NREC	= [IMGEND-LOAD]/128
	.ifdef SHAREBSS
BSS	= SHAREBSS		; one image: tape 1's BSS page is this one's
	.else
BSS	= IMGEND
	.endif
TSTART	= [>BSS]+1
	.ifdef SYSLOAD
	.if [>BSS]+1>$3F		; stage 1's BSS page is $3F00 (the one-load
	.error "system tests too big for the one-load payload (BSS must end below $3F00)"
	.endif				; screen is never at $3C00, see display.asm)
	.endif
