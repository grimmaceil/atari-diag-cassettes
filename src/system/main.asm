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

	icl '../common/hw.asm'
	icl '../common/vars.asm'
	icl '../common/faults.asm'

QUICKSCR = 1			; display.asm: quick screen-block test

	opt h-
LOAD	= $0800
	org LOAD

; Cassette boot header. The OS reads NREC records to LOAD, then JSRs LOAD+6.
	.byte 0
	.byte NREC
	.word LOAD
	.word init_rts

	icl '../common/boot.asm'

	jsr detect
	jsr dprereq
	jmp trun

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

	icl '../common/display.asm'

init_rts rts

; Low-RAM patterns: solid, checkerboard, walking 1, walking 0.
pats	.byte $00,$FF,$55,$AA
	.byte $01,$02,$04,$08,$10,$20,$40,$80
	.byte $FE,$FD,$FB,$F7,$EF,$DF,$BF,$7F
NPAT	= *-pats

	icl '../common/report.asm'
	icl '../common/screen.asm'
	icl '../common/info.asm'
	icl 'common.asm'

; The header bar: " A8 DIAG 400 TAPE 3 " (SETNO 0 = 400, 1 = 16K, 2 = 48K).
s_hpre	dta d' A8 DIAG '
	.if SETNO=0
	dta d'400'
	.elseif SETNO=1
	dta d'16K'
	.else
	dta d'48K'
	.endif
	dta d' TAPE ',[TAPENO+$10],d' ',$FF

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
