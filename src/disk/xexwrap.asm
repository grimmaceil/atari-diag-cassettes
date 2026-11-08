; The wrapper around a diag program in an Atari binary file (.xex): the
; guard (PART=1) and the mover (PART=2). tools/mkxex.py assembles each and
; writes the file: guard at BASE + INITAD, the program image at BASE, mover
; at its end + RUNAD (Atari-diag-disk-scope.md, 4).
;
; Defines (build.py): PART, ORG (where this part loads), BASE (where the
; image loads), NEEDPG (RAM needed, in pages), NEEDK (the same in K),
; NPAGES (image pages to move, rounded up).

	opt h-
	icl '../common/hw.asm'
C_TEXTLUM = $0C		; as screen.asm (its code isn't wanted here)
C_TEXTBG = $00
RAMTOP	= $6A		; the OS's: RAM size in pages (a cartridge ends it)
MEMLO	= $02E7		; the lowest RAM DOS leaves free
COLDST	= $0244		; nonzero: the RESET key starts the machine from cold

	org ORG

	.if PART=1
; ---------------------------------------------------------------------------
; Guard: runs (INITAD) before the image loads, so a machine without the
; RAM never gets the image written into RAM that isn't there. Returns if
; the program fits; else shows one line and halts, as the tapes do: red
; border, the low tone on and off.
guard	lda RAMTOP
	cmp #NEEDPG
	bcc g_ram
	lda MEMLO+1		; DOS must end at or below BASE
	cmp #>BASE
	bcc g_ok
	bne g_dos
	lda MEMLO
	bne g_dos
g_ok	rts

g_dos	ldx #s_dos-msgs
	bne g_show
g_ram	lda RAMTOP		; the RAM found, in K: pages / 4
	lsr
	lsr
	ldx #$10-1		; tens digit (internal code '0' = $10)
g_ten	inx
	sec
	sbc #10
	bcs g_ten
	adc #10+$10		; ones digit
	ldy #0
	cpx #$10
	beq g_one		; no leading zero
	stx s_has
	iny
g_one	sta s_has,y
	lda #'K'-$20
	sta s_has+1,y
	lda #'.'-$20
	sta s_has+2,y
	ldx #s_ram-msgs

g_show	sei			; the screen: the OS's VBI is off, so write
	lda #0			; the chips directly
	sta NMIEN
	sta IRQEN
	sta DMACTL
	lda #<msgs
	stx g_lms		; this message's line in the display list
	clc
	adc g_lms
	sta g_lms
	lda #>msgs
	adc #0
	sta g_lms+1
	lda #<dlist
	sta DLISTL
	lda #>dlist
	sta DLISTL+1
	lda #$E0
	sta CHBASE
	lda #2
	sta CHACTL
	lda #C_TEXTLUM
	sta COLPF1
	lda #C_TEXTBG
	sta COLPF2
	lda #C_RED
	sta COLBK
	lda #$22
	sta DMACTL
	lda #F_END
	sta AUDF1
	lda #AUD_ON		; 0.6 s on, 0.6 s off, for good (as boot.asm)
g_tone	sta AUDC1
	ldy #37
g_wy	ldx #0
g_wx	sta WSYNC
	dex
	bne g_wx
	dey
	bne g_wy
	eor #AUD_ON^AUD_OFF
	jmp g_tone

dlist	:12 dta $70		; 96 blank lines: the line sits mid-screen
	dta $42
g_lms	dta a(0)
	dta $41, a(dlist)

; 40 columns each (one mode 2 line)
msgs
s_ram	dta d'NEEDS ',[NEEDK/10+$10],[NEEDK-NEEDK/10*10+$10],d'K RAM. THIS MACHINE HAS '
s_has	dta d'        '
	.if *-s_ram<>40
	.error 'RAM message is not 40 columns'
	.endif
s_dos	dta d'  DOS IS IN THE WAY: USE DOS 2 OR MYDOS '
	.if *-s_dos<>40
	.error 'DOS message is not 40 columns'
	.endif

	.else
; ---------------------------------------------------------------------------
; Mover: runs (RUNAD) once everything has loaded. Copies the image down to
; $0800, where it runs, and starts it at $0806, the entry the cassette boot
; uses. DOS is overwritten from here on, so RESET starts the machine again.
; No zero page or stack used (the program tests those).
mover	sei
	lda #0
	sta NMIEN
	sta IRQEN
	sta DMACTL
	tax
	ldy #NPAGES		; ascending: the target is below the source
mv_s	lda BASE,x
mv_d	sta $0800,x
	inx
	bne mv_s
	inc mv_s+2
	inc mv_d+2
	dey
	bne mv_s
	lda #1
	sta COLDST
	jmp $0806
	.endif
