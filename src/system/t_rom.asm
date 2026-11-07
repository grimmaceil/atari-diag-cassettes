; Test 1: ROMs, identified by CRC32 against published tables (the scope doc,
; section 10a: atari800 sysrom.c and MAME, which agree). Not against any one
; machine's ROMs: a repaired board can carry chips of mixed revisions, so on
; the 400/800 each OS chip is named on its own.
;   item 1: the OS reads differently twice (flaky ROM, socket, data bus)
;   item 2: BASIC or the cartridge reads differently twice
;   item 3: an OS ROM matches no known revision (patched, replacement,
;           failing or mis-socketed)
;   item 4: the character set read differently twice (dprereq's sums)
;   item 5: OS chips from different revisions
; A ROM that matches is read once: a bad read would not match. One that
; doesn't is read again, to tell flaky from merely unknown.
;
; The 400/800 OS is three chips: $D800-$DFFF, $E000-$EFFF, $F000-$FFFF. The
; XL/XE OS is one 16K image, $C000-$CFFF, then $D000-$D7FF (the self-test,
; which the CPU sees at $5000-$57FF with PORTB bit 7 = 0), then $D800-$FFFF;
; the 1200XL's two 8K chips are its halves. BASIC (XL/XE: PORTB bit 1 = 0) or
; a 400/800 cartridge: $A000-$BFFF.

CRC	= $86			; 4: CRC32 being built (zero page: the inner loop)
OSCRC	= T3D+$03		; 3 x 4: 400/800 chips $D800, $E000, $F000;
				; XL/XE whole, $C000 half, $E000 half
BASCRC	= T3D+$0F		; 4
OSID	= T3D+$13		; 3: name number of each OSCRC ($FF: unknown)
BASID	= T3D+$16
ROMHAVE	= T3D+$17		; bit 1: BASIC/cartridge read, bit 2: halves read,
				; bit 3: it is a cartridge
CRCSV	= TSCR+$00		; 16: the first read, for the re-read to match
PGLEFT	= TSCR+$10		; crcpg: pages to go
RTAB	= TSCR+$11		; crcid: the table's entries left
CIENT	= TSCR+$12		; crcid: offset of the entry being compared

t_rom	lda #1
	sta TEST
	lda #<s_t1
	ldy #>s_t1
	jsr tpage
	lda DISPOK
	beq tr_rd
	PRINT 5, 0, s_rread
tr_rd	lda #0
	sta ROMHAVE

	jsr osread		; the OS
	jsr osids
	bcc tr_osok
	ldx #11			; unknown: read it again
tr_sv	lda OSCRC,x
	sta CRCSV,x
	dex
	bpl tr_sv
	jsr osread
	ldx #11
tr_cmp	lda OSCRC,x
	cmp CRCSV,x
	bne tr_flk
	dex
	bpl tr_cmp
	jsr osids
	lda #4			; the same twice: not a known revision
	bne tr_osb
tr_flk	lda #1
tr_osb	ora BADMASK+1
	sta BADMASK+1
tr_osok	jsr mixed

	jsr basread		; BASIC or the cartridge
	bcc tr_font
	lda #2
	ora ROMHAVE
	sta ROMHAVE
	jsr basname
	cmp #$FF
	bne tr_font
	ldx #3
tr_bsv	lda BASCRC,x
	sta CRCSV,x
	dex
	bpl tr_bsv
	jsr basread
	ldx #3
tr_bcm	lda BASCRC,x
	cmp CRCSV,x
	bne tr_bfl
	dex
	bpl tr_bcm
	bmi tr_font
tr_bfl	lda #2
	ora BADMASK+1
	sta BADMASK+1

tr_font	lda CHSTAB		; the font, summed twice by dprereq
	bne tr_show
	lda #8
	ora BADMASK+1
	sta BADMASK+1
tr_show	lda DISPOK
	beq tr_end
	lda #5
	jsr clrrow
	lda #5
	jsr rominfo
	PRINT 13, 0, s_rnote
tr_end	jmp tend

; osread: the OS CRCs into OSCRC.
osread	lda MACHINE
	bne or_xl
	jsr crcnew		; 400/800: each chip on its own
	lda #$D8
	ldx #8
	jsr crcpg
	ldy #0
	jsr crcput
	jsr crcnew
	lda #$E0
	ldx #16
	jsr crcpg
	ldy #4
	jsr crcput
	jsr crcnew
	lda #$F0
	ldx #16
	jsr crcpg
	ldy #8
	jmp crcput
or_xl	jsr crcnew		; XL/XE: the whole 16K image
	lda #$C0
	ldx #16
	jsr crcpg
	lda PORTB		; the self-test ROM in, for $D000-$D7FF
	sta PBSAVE
	and #$7F
	sta PORTB
	lda #$50
	ldx #8
	jsr crcpg
	lda PBSAVE
	sta PORTB
	lda #$D8
	ldx #8
	jsr crcpg
	ldy #4			; the $C000 half: the CRC so far
	jsr crcput
	lda #$E0
	ldx #32
	jsr crcpg
	ldy #0
	jsr crcput
	jsr crcnew		; the $E000 half on its own
	lda #$E0
	ldx #32
	jsr crcpg
	ldy #8
	jmp crcput

; osids: name each OSCRC. C set if any OS ROM is unknown (on the XL/XE:
; the whole image, unless both halves are known).
osids	lda MACHINE
	bne oi_xl
	ldx #0
	lda #<tab_d8
	ldy #>tab_d8
	jsr crcid
	sta OSID
	ldx #4
	lda #<tab_e0
	ldy #>tab_e0
	jsr crcid
	sta OSID+1
	ldx #8
	lda #<tab_f0
	ldy #>tab_f0
	jsr crcid
	sta OSID+2
	ldx #2
oi_any	lda OSID,x		; any unknown?
	cmp #$FF
	beq oi_unk
	dex
	bpl oi_any
	clc
	rts
oi_unk	sec
	rts
oi_xl	ldx #0
	lda #<tab_xl
	ldy #>tab_xl
	jsr crcid
	sta OSID
	lda #$FF
	sta OSID+1
	sta OSID+2
	lda OSID
	cmp #$FF
	clc
	bne oi_x		; a known image: the halves don't matter
	lda #4			; unknown: show the halves (the 1200XL's chips)
	ora ROMHAVE
	sta ROMHAVE
	ldx #4
	lda #<tab_c0h
	ldy #>tab_c0h
	jsr crcid
	sta OSID+1
	ldx #8
	lda #<tab_e0h
	ldy #>tab_e0h
	jsr crcid
	sta OSID+2
	lda OSID+1
	cmp #$FF
	beq oi_unk
	lda OSID+2
	cmp #$FF
	beq oi_unk
	clc
oi_x	rts

; mixed: item 5 if two known OS chips are from different revisions (the
; 400/800's $E000 and $F000 chips, or an XL/XE image made of two known
; halves: two chips on a 1200XL, a damaged or patched image otherwise).
mixed	ldx OSID+1
	cpx #$FF
	beq mx_x
	ldy OSID+2
	cpy #$FF
	beq mx_x
	cpx OSID+2
	beq mx_x
	lda #16
	ora BADMASK+1
	sta BADMASK+1
mx_x	rts

; basread: BASIC (XL/XE) or a cartridge (400/800) into BASCRC. C clear: no
; ROM there.
basread	lda MACHINE
	beq br_cart
	lda PORTB
	sta PBSAVE
	ora #2			; BASIC out: RAM at $A000
	sta PORTB
	ldx #15			; the 1200XL has no BASIC: RAM is there either
br_sv	lda $A000,x		; way, so $A000 reads the same with it in
	sta CRCSV,x
	dex
	bpl br_sv
	lda PBSAVE
	and #$FD
	sta PORTB
	ldx #15
br_cmp	lda $A000,x
	cmp CRCSV,x
	bne br_rom
	dex
	bpl br_cmp
	lda $A000		; the same both ways: RAM (a 1200XL), or a
	sta MTMP		; cartridge, which holds $A000-$BFFF either way.
	eor #$FF		; A write changes RAM, even RAM with bad bits,
	sta $A000		; and never changes a ROM
	lda $A000
	cmp MTMP
	php
	lda MTMP
	sta $A000		; (RAM: put it back)
	plp
	clc
	bne br_out
	lda #8
	ora ROMHAVE
	sta ROMHAVE
br_rom	jsr br_crc
	sec
br_out	lda PBSAVE		; (keeps C)
	sta PORTB
	rts
br_cart	lda RAMTOP		; RAM up to $BFFF: no cartridge
	cmp #$A1
	bcs br_no
	lda #$A0		; and the bus floats if nothing is plugged in
	jsr varied
	bcc br_no
	lda #8
	ora ROMHAVE
	sta ROMHAVE
	jsr br_crc
	sec
	rts
br_no	clc
	rts
br_crc	jsr crcnew
	lda #$A0
	ldx #32
	jsr crcpg
	ldx #3
br_put	lda CRC,x
	eor #$FF
	sta BASCRC,x
	dex
	bpl br_put
	rts

; basname: name BASCRC into BASID (A too).
basname	ldx #BASCRC-OSCRC	; crcid's X counts from OSCRC
	lda #<tab_bas
	ldy #>tab_bas
	jsr crcid
	sta BASID
	rts

; crcnew: start a CRC32 (all ones).
crcnew	lda #$FF
	sta CRC
	sta CRC+1
	sta CRC+2
	sta CRC+3
	rts

; crcput: the CRC so far (inverted, as CRC32 ends) into OSCRC+Y. The CRC
; itself carries on.
crcput	ldx #0
cu_lp	lda CRC,x
	eor #$FF
	sta OSCRC,y
	iny
	inx
	cpx #4
	bne cu_lp
	rts

; crcpg: add X pages from page A to the CRC. Reflected CRC32, polynomial
; $EDB88320, a bit at a time (no room for a 1K table in 8K): about 280
; cycles a byte, so 2.5 s for an XL/XE OS.
crcpg	sta PTR+1
	stx PGLEFT
	lda #0
	sta PTR
	tay
cp_lp	lda (PTR),y
	eor CRC
	sta CRC
	ldx #8
cb_lp	lsr CRC+3		; CRC >> 1; the bit shifted out picks the XOR
	ror CRC+2
	ror CRC+1
	ror CRC
	bcc cb_n
	lda CRC+3
	eor #$ED
	sta CRC+3
	lda CRC+2
	eor #$B8
	sta CRC+2
	lda CRC+1
	eor #$83
	sta CRC+1
	lda CRC
	eor #$20
	sta CRC
cb_n	dex
	bne cb_lp
	iny
	bne cp_lp
	inc PTR+1
	dec PGLEFT
	bne cp_lp
	rts

; crcid: look up the CRC at OSCRC+X in the table at A/Y: a count, then
; entries of the CRC32 (low byte first) and a name number. A = the name
; number, $FF if none matches.
crcid	sta PTR
	sty PTR+1
	stx MTMP
	ldy #0
	lda (PTR),y
	sta RTAB
	iny
ci_ent	sty CIENT		; compare the 4 bytes
	ldx MTMP
ci_by	lda (PTR),y
	cmp OSCRC,x
	bne ci_no
	iny
	inx
	tya
	sec
	sbc CIENT
	cmp #4
	bne ci_by
	lda (PTR),y		; a match: the name number follows
	rts
ci_no	lda CIENT
	clc
	adc #5
	tay
	dec RTAB
	bne ci_ent
	lda #$FF
	rts

; varied: C set if page A reads like a ROM (32 or more byte-to-byte changes)
; rather than an empty bus (the same byte over and over).
varied	sta PTR+1
	lda #0
	sta PTR
	tax			; changes
	tay
	lda (PTR),y
va_lp	cmp (PTR),y
	beq va_same
	inx
	lda (PTR),y
va_same	iny
	bne va_lp
	cpx #32
	rts

; rominfo: the ROM lines from row A: each OS chip (or the XL/XE image, and
; its halves if it is unknown), BASIC or the cartridge, the font.
rominfo	sta CNT
	lda MACHINE
	bne ri_xl
	ldx #0			; 400/800: three chips
	lda #<s_rd8
	ldy #>s_rd8
	jsr romline
	ldx #1
	lda #<s_re0
	ldy #>s_re0
	jsr romline
	ldx #2
	lda #<s_rf0
	ldy #>s_rf0
	jsr romline
	jmp ri_bas
ri_xl	ldx #0
	lda #<s_rxl
	ldy #>s_rxl
	jsr romline
	lda ROMHAVE
	and #4
	beq ri_bas
	ldx #1
	lda #<s_rc0
	ldy #>s_rc0
	jsr romline
	ldx #2
	lda #<s_re0
	ldy #>s_re0
	jsr romline
ri_bas	lda ROMHAVE
	and #2
	beq ri_ch
	ldx #3			; BASCRC is OSCRC+12 and BASID is OSID+3: slot 3
	lda ROMHAVE
	and #8
	beq ri_b
	lda #<s_rcart
	ldy #>s_rcart
	bne ri_bp
ri_b	lda #<s_rbas
	ldy #>s_rbas
ri_bp	jsr romline
ri_ch	lda CNT
	jmp chinfo

; romline: row CNT (then CNT+1): label A/Y, then the name of slot X (0-2:
; the OS, 3: BASIC) and its CRC32.
romline	stx MTMP
	pha
	tya
	pha
	lda CNT
	ldx #0
	jsr at
	pla
	tay
	pla
	jsr puts
	lda CNT
	ldx #11
	jsr at
	ldx MTMP
	lda OSID,x
	cmp #$FF
	bne rl_k
	lda #<s_unk
	ldy #>s_unk
	bne rl_p
rl_k	asl
	tax
	lda romnames,x
	ldy romnames+1,x
rl_p	jsr puts
	lda CNT
	ldx #29
	jsr at
	lda #4			; '$', then the CRC high byte first
	jsr putc
	lda MTMP
	asl
	asl
	clc
	adc #3
	tax
rl_hx	lda OSCRC,x
	jsr puthex
	dex
	txa
	and #3
	cmp #3
	bne rl_hx
	inc CNT
	rts

; The tables (section 10a). Name numbers index romnames.
tab_d8	.byte 1
	.dword $6A5D766E
	.byte 0
tab_e0	.byte 3
	.dword $29F64E17
	.byte 1
	.dword $D818F3E8
	.byte 2
	.dword $8E547F56
	.byte 3
tab_f0	.byte 3
	.dword $BC533F0C
	.byte 1
	.dword $C1690A9B
	.byte 2
	.dword $BE55B413
	.byte 3
tab_xl	.byte 11
	.dword $C5C11546
	.byte 4
	.dword $1A1D7B1B
	.byte 5
	.dword $643BCC98
	.byte 6
	.dword $1F9CD270
	.byte 7
	.dword $29F133F7
	.byte 8
	.dword $0D477AA1
	.byte 9
	.dword $D425A9CF
	.byte 10
	.dword $1EAF4002
	.byte 11
	.dword $0E000B99
	.byte 12
	.dword $45F47988
	.byte 13
	.dword $F0A236D3
	.byte 14
; The halves: the 1200XL's two chips (MAME), and revs 1-4 split from ROM
; files whose whole-image CRC matches the table above (section 10a).
tab_c0h	.byte 6
	.dword $0391386B
	.byte 4
	.dword $6E29EC8D
	.byte 5
	.dword $C376D2F2
	.byte 6
	.dword $F1E30A44
	.byte 7
	.dword $79E0D038
	.byte 8
	.dword $4A3AE4E5
	.byte 11
tab_e0h	.byte 6
	.dword $B502F1E7
	.byte 4
	.dword $D73CE29A
	.byte 5
	.dword $4502AF6F
	.byte 6
	.dword $397BAA67
	.byte 7
	.dword $2C8B447A
	.byte 8
	.dword $ACCF9678
	.byte 11
tab_bas	.byte 4
	.dword $4BEC4DE2
	.byte 15
	.dword $F0202FB3
	.byte 16
	.dword $7D684184
	.byte 17
	.dword $C899F4D6
	.byte 18

romnames .word n_ab, n_antsc, n_bntsc, n_apal, n_r10, n_r11, n_r1, n_r2
	.word n_r3, n_r3a, n_r3b, n_r4, n_r5, n_r59, n_r59a
	.word n_basa, n_basb, n_basc, n_basar
n_ab	dta d'REV A/B, ANY',$FF
n_antsc	dta d'REV A NTSC',$FF
n_bntsc	dta d'REV B NTSC',$FF
n_apal	dta d'REV A PAL',$FF
n_r10	dta d'REV 10 1200XL',$FF
n_r11	dta d'REV 11 1200XL',$FF
n_r1	dta d'REV 1',$FF
n_r2	dta d'REV 2',$FF
n_r3	dta d'REV 3',$FF
n_r3a	dta d'REV 3A',$FF
n_r3b	dta d'REV 3B',$FF
n_r4	dta d'REV 4',$FF
n_r5	dta d'REV 5',$FF
n_r59	dta d'REV 59 (3B?)',$FF
n_r59a	dta d'REV 59A',$FF
n_basa	dta d'BASIC REV A',$FF
n_basb	dta d'BASIC REV B',$FF
n_basc	dta d'BASIC REV C',$FF
n_basar	dta d'BASIC ARABIC',$FF
s_unk	dta d'UNKNOWN'*,$FF
s_rd8	dta d'OS $D800',$FF
s_re0	dta d'OS $E000',$FF
s_rf0	dta d'OS $F000',$FF
s_rc0	dta d'OS $C000',$FF
s_rxl	dta d'OS XL/XE',$FF
s_rbas	dta d'BASIC',$FF
s_rcart	dta d'CARTRIDGE',$FF
s_rread	dta d'READING THE ROMS, A FEW SECONDS...',$FF
s_rnote	dta d'NAMED FROM PUBLISHED CRC32 TABLES',$FF
