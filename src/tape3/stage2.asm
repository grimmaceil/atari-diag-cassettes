; A8 DIAG tape 3, stage 2. Loaded by stage 1 at S2LOAD (16K and up), entered
; at S2LOAD+6 with interrupts off; stage 1's results come over in its BSS.
;   1 ROM checksums   4 POKEY   5 joysticks   6 paddles   7 GTIA
; then the summary of all seven and the final code.
; Built with -d:S1BSS=... -d:S1TSTART=... from stage 1's label table.

	icl '../common/hw.asm'
	icl '../common/vars.asm'
	icl '../common/faults.asm'

; Stage 2 data, in T3D (see t3common.asm).
OSSUM	= T3D+$00		; 2: sums: OS, BASIC/cartridge, self-test
BASSUM	= T3D+$02
STSUM	= T3D+$04
ROMHAVE	= T3D+$06		; bit 1: BASIC/cart summed, bit 2: self-test
SUM2	= T3D+$07		; 2: the previous ROM sum
RTIME	= T3D+$09		; 2: frames left in a timed wait
NPORT	= T3D+$0B		; joystick ports on this machine (paddles: twice)
PCUR	= T3D+$14		; 8: paddle values now
PMIN	= T3D+$1C		; 8
PMAX	= T3D+$24		; 8
WMIN	= T3D+$2C		; 8: this 16-frame window, for the jitter
WMAX	= T3D+$34		; 8
PJIT	= T3D+$3C		; 8: the last window's spread
PFRM	= T3D+$44		; frame count in the window
PFAST	= T3D+$45		; nonzero: fast pot scan (SKCTL bit 2)
VOICE	= T3D+$46		; POKEY voice being played (0-3)
JX	= T3D+$47		; jshow: label being printed
JBITS	= T3D+$48		; jshow: the port's active bits

POT0	= $D200			; read: paddle values, 0-228
POTGO	= $D20B			; write: start a pot scan
RANDOM	= $D20A
STIMER	= $D209			; write: restart the POKEY timers

	opt h-
S2LOAD	= $2000
	org S2LOAD

	.byte 0
	.byte NREC
	.word S2LOAD
	.word 0

entry2	sei
	cld
	ldx #$FF
	txs
	ldx #0			; take over stage 1's results
tk_lp	lda S1BSS,x
	sta BSS,x
	inx
	bne tk_lp
	lda #0
	sta CONTVEC+1
	lda #2			; ports: 4 on the 400/800, 2 on the XL/XE
	ldx MACHINE
	bne e2_xl
	lda #4
e2_xl	sta NPORT

; ---------------------------------------------------------------------------
; Test 1: ROM checksums. Each ROM is summed twice: a sum that changes means
; a flaky ROM, socket or data bus (an item fails). The sums themselves are
; shown for the revision table (none yet, so every sum is shown raw).
;   item 1 OS, 2 BASIC/cartridge, 3 XL self-test, 4 character set
t_rom	lda #1
	sta TEST
	lda #<s_t1
	ldy #>s_t1
	jsr tpage

	lda MACHINE		; OS: $D800-$FFFF, on the XL/XE also $C000-$CFFF
	beq tr_os8
	jsr os_xl
	jsr os_xl
	jmp tr_os
tr_os8	jsr os_8
	jsr os_8
tr_os	lda #1
	jsr unstable
	lda SUM
	sta OSSUM
	lda SUM+1
	sta OSSUM+1

	lda MACHINE		; BASIC: switched in on the XL/XE, a cartridge on
	beq tr_cart		; the 400/800
	lda PORTB
	sta PBSAVE
	and #$FD
	sta PORTB
	jsr bas_sum
	jsr bas_sum
	lda PBSAVE
	sta PORTB
	jmp tr_bas
tr_cart	lda RAMTOP		; a cartridge: RAM ends at $A000 and $A000 reads
	cmp #$A1		; like a ROM, not like an empty bus
	bcs tr_st
	lda #$A0
	jsr varied
	bcc tr_st
	jsr bas_sum
	jsr bas_sum
tr_bas	lda #2
	jsr unstable
	lda SUM
	sta BASSUM
	lda SUM+1
	sta BASSUM+1
	lda #2
	ora ROMHAVE
	sta ROMHAVE

tr_st	lda MACHINE		; XL self-test ROM: PORTB bit 7 = 0, $5000-$57FF
	beq tr_ch
	lda PORTB
	sta PBSAVE
	and #$7F
	sta PORTB
	jsr st_sum
	jsr st_sum
	lda PBSAVE
	sta PORTB
	lda #3
	jsr unstable
	lda SUM
	sta STSUM
	lda SUM+1
	sta STSUM+1
	lda #4
	ora ROMHAVE
	sta ROMHAVE

tr_ch	lda CHSTAB		; the font, summed by stage 1's dprereq
	bne tr_show
	lda #8
	ora BADMASK+1
	sta BADMASK+1
tr_show	lda DISPOK
	beq tr_end
	lda #5
	jsr romsums
	PRINT 11, 0, s_romnote
tr_end	lda #<t_pok
	sta NEXTVEC
	lda #>t_pok
	sta NEXTVEC+1
	jmp tresult

; romsums: the sum lines from row A: OS, BASIC/cartridge, self-test, font.
romsums	sta CNT
	ldx #0
	jsr at
	lda #<s_os
	ldy #>s_os
	jsr puts
	lda OSSUM+1
	ldx OSSUM
	jsr hex4
	inc CNT
	lda ROMHAVE
	and #2
	beq rm_nb
	lda CNT
	ldx #0
	jsr at
	lda #<s_bas
	ldy #>s_bas
	ldx MACHINE
	bne rm_b
	lda #<s_cart
	ldy #>s_cart
rm_b	jsr puts
	lda BASSUM+1
	ldx BASSUM
	jsr hex4
	inc CNT
rm_nb	lda ROMHAVE
	and #4
	beq rm_ns
	lda CNT
	ldx #0
	jsr at
	lda #<s_selft
	ldy #>s_selft
	jsr puts
	lda STSUM+1
	ldx STSUM
	jsr hex4
	inc CNT
rm_ns	lda CNT
	jmp chinfo

; The sums: each call starts a new one and keeps the last in SUM2, so two
; calls leave both for unstable to compare.
os_8	jsr sum_new
	lda #$D8
	ldx #40
	jmp rsum
os_xl	jsr sum_new
	lda #$C0
	ldx #16
	jsr rsum
	lda #$D8
	ldx #40
	jmp rsum
bas_sum	jsr sum_new
	lda #$A0
	ldx #32
	jmp rsum
st_sum	jsr sum_new
	lda #$50
	ldx #8
	jmp rsum

; sum_new: keep the last sum in SUM2, start a new one.
sum_new	lda SUM
	sta SUM2
	lda SUM+1
	sta SUM2+1
	lda #0
	sta SUM
	sta SUM+1
	rts

; rsum: add X pages from page A to SUM.
rsum	sta PTR+1
	lda #0
	sta PTR
	tay
rs_lp	lda (PTR),y
	clc
	adc SUM
	sta SUM
	bcc rs_nc
	inc SUM+1
rs_nc	iny
	bne rs_lp
	inc PTR+1
	dex
	bne rs_lp
	rts

; unstable: if SUM2 <> SUM, item A of test 1 fails.
unstable tax
	lda SUM
	cmp SUM2
	bne un_bad
	lda SUM+1
	cmp SUM2+1
	beq un_x
un_bad	lda #0
	sec
un_sh	rol
	dex
	bne un_sh
	ora BADMASK+1
	sta BADMASK+1
un_x	rts

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

; hex4: "$" A X (A = high byte).
hex4	pha
	lda #4			; '$'
	jsr putc
	pla
	jsr puthex
	txa
	jmp puthex

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

; ---------------------------------------------------------------------------
; Test 4: POKEY.
;   item 1: timer 1's interrupt doesn't come (read in IRQST; the CPU masks it)
;   item 2: RANDOM doesn't change
;   items 3-6: voice 1-4 not heard
t_pok	lda #4
	sta TEST
	lda #<s_t4
	ldy #>s_t4
	jsr tpage
	lda #0			; timer 1: 64 kHz / 256, about 4 ms
	sta AUDCTL
	sta IRQEN
	lda #$FF
	sta AUDF1
	lda #AUD_OFF
	sta AUDC1
	lda #1
	sta IRQEN
	sta STIMER
	ldx #0			; give it ~32 ms
	ldy #1
pk_irq	lda IRQST
	lsr
	bcc pk_ok
	sta WSYNC
	dex
	bne pk_irq
	dey
	bpl pk_irq
	lda #1
	sta BADMASK+4
pk_ok	lda #0
	sta IRQEN

	lda RANDOM		; RANDOM: at least 8 changes in 16 reads
	ldx #16
	ldy #0
pk_rnd	sta WSYNC
	cmp RANDOM
	beq pk_rs
	iny
	lda RANDOM
pk_rs	dex
	bne pk_rnd
	cpy #8
	bcs pk_v
	lda #2
	ora BADMASK+4
	sta BADMASK+4

pk_v	lda DISPOK
	beq pk_v0
	PRINT 5, 0, s_pk1	; the voices, one at a time, by ear
pk_v0	lda #0
	sta VOICE
pk_vl	lda DISPOK
	beq pk_play
	lda #7
	jsr clrrow
	PRINT 7, 0, s_voice
	lda VOICE
	clc
	adc #$11
	jsr putc
	PRINT 8, 0, s_heard
pk_play	lda VOICE		; X = the voice's AUDF offset
	asl
	tax
	lda #F_LONG
	sta AUDF1,x
	lda #AUD_ON
	sta AUDC1,x
	WAITMS 1500
	lda VOICE
	asl
	tax
	lda #AUD_OFF
	sta AUDC1,x
	jsr yesno
	bcs pk_heard
	ldx VOICE		; items 3-6
	lda pkbit,x
	ora BADMASK+4
	sta BADMASK+4
pk_heard inc VOICE
	lda VOICE
	cmp #4
	bne pk_vl
	lda #<t_joy
	sta NEXTVEC
	lda #>t_joy
	sta NEXTVEC+1
	jmp tresult
pkbit	.byte 4, 8, 16, 32

; ---------------------------------------------------------------------------
; Test 5: joysticks and triggers, live: a direction or fire shows inverse
; while it is active. One already active at the start is stuck: item = port.
; START ends it.
t_joy	lda #5
	sta TEST
	lda #<s_t5
	ldy #>s_t5
	jsr tpage
	lda DISPOK
	beq jy_s0
	PRINT 5, 0, s_joy1
jy_s0	ldx #0			; stuck: whatever is active now
jy_st	jsr jread
	beq jy_sn
	lda bitn,x
	ora BADMASK+5
	sta BADMASK+5
jy_sn	inx
	cpx NPORT
	bne jy_st
	jsr waitrel
jy_lp	jsr vsync
	ldx #0
jy_port	stx CNT
	jsr jread
	jsr jshow
	ldx CNT
	inx
	cpx NPORT
	bne jy_port
	lda CONSOL
	lsr
	bcs jy_lp
	jsr waitrel
	lda #<t_pad
	sta NEXTVEC
	lda #>t_pad
	sta NEXTVEC+1
	jmp tresult

; jread: port X now: bits 0-3 up, down, left, right, bit 4 fire (1 =
; active). Ports 0-1 are PORTA, 2-3 PORTB (400/800 only). Keeps X.
jread	lda PORTA
	cpx #2
	bcc jr_a
	lda PORTB
jr_a	sta MTMP
	txa
	and #1
	beq jr_lo
	lsr MTMP		; odd port: the high nibble
	lsr MTMP
	lsr MTMP
	lsr MTMP
jr_lo	lda MTMP
	eor #$0F		; 0 = pressed
	and #$0F
	sta MTMP
	lda TRIG0,x
	and #1
	bne jr_x
	lda #$10
	ora MTMP
	sta MTMP
jr_x	lda MTMP
	rts

; jshow: port CNT's row (7+port), bits A: "STICK n  UP DOWN LEFT RIGHT
; FIRE", each active one inverse.
jshow	sta JBITS
	lda DISPOK
	beq js_x
	lda CNT
	clc
	adc #7
	ldx #0
	jsr at
	lda #<s_stick
	ldy #>s_stick
	jsr puts
	lda CNT
	clc
	adc #$11
	jsr putc
	lda #0
	sta JX
js_lp	lda #0
	sta INV
	jsr putc
	lsr JBITS
	bcc js_n
	lda #$80
	sta INV
js_n	lda JX
	asl
	tay
	lda jlabels,y
	pha
	lda jlabels+1,y
	tay
	pla
	jsr puts
	inc JX
	lda JX
	cmp #5
	bne js_lp
	lda #0
	sta INV
js_x	rts
jlabels	.word s_up, s_down, s_left, s_right, s_fire
bitn	.byte 1, 2, 4, 8, 16, 32, 64, 128

; ---------------------------------------------------------------------------
; Test 6: paddles. POTGO starts a scan; each POTn counts scanlines until its
; RC charge crosses the threshold, 228 at most.
;   open-input check: with nothing plugged in every input must read 228,
;   which proves the scan works. One that doesn't fails item = paddle.
;   live: value bar, min/max seen (a full turn reaches about 1 and 228),
;   jitter (spread over 16 frames: big with the knob still = dirty pot),
;   the paddle trigger. SELECT: fast scan (SKCTL bit 2). START ends it.
t_pad	lda #6
	sta TEST
	lda #<s_t6
	ldy #>s_t6
	jsr tpage
	lda DISPOK
	beq pd_s0
	PRINT 5, 0, s_pd1
	PRINT 6, 0, s_pd2
pd_s0	lda #0
	sta PFAST
	jsr waitrel
pd_w	jsr vsync		; START: check, SELECT: skip it
	lda CONSOL
	lsr
	bcc pd_chk
	lsr
	bcs pd_w
	jmp pd_live
pd_chk	jsr potscan		; one scan to start, one to read
	jsr potscan
	ldx #0
pd_c	lda PCUR,x
	cmp #228
	beq pd_cok
	lda bitn,x
	ora BADMASK+6
	sta BADMASK+6
pd_cok	inx
	jsr npots
	bne pd_c

pd_live	jsr waitrel
	lda DISPOK
	beq pd_l0
	lda #5
	jsr clrrow
	lda #6
	jsr clrrow
	PRINT 5, 0, s_pd3
pd_l0	ldx #7
pd_i	lda #228
	sta PMIN,x
	sta WMIN,x
	lda #0
	sta PMAX,x
	sta WMAX,x
	sta PJIT,x
	dex
	bpl pd_i
	lda #0
	sta PFRM
pd_lp	jsr potscan
	ldx #0
pd_u	lda PCUR,x		; min/max, and the window
	cmp PMIN,x
	bcs pd_u1
	sta PMIN,x
pd_u1	cmp PMAX,x
	bcc pd_u2
	sta PMAX,x
pd_u2	cmp WMIN,x
	bcs pd_u3
	sta WMIN,x
pd_u3	cmp WMAX,x
	bcc pd_u4
	sta WMAX,x
pd_u4	inx
	jsr npots
	bne pd_u
	inc PFRM		; every 16 frames: the window's spread is the jitter
	lda PFRM
	and #15
	bne pd_sh
	ldx #7
pd_j	lda WMAX,x
	sec
	sbc WMIN,x
	bcs pd_j1
	lda #0
pd_j1	sta PJIT,x
	lda #228
	sta WMIN,x
	lda #0
	sta WMAX,x
	dex
	bpl pd_j
pd_sh	jsr potshow
	lda CONSOL
	lsr
	bcc pd_end
	lsr			; SELECT: fast scan on/off
	bcs pd_lp
	lda PFAST
	eor #1
	sta PFAST
	jsr waitrel
	jmp pd_lp
pd_end	lda #3			; SKCTL back to normal
	sta SKCTL
	jsr waitrel
	lda #<t_gtia
	sta NEXTVEC
	lda #>t_gtia
	sta NEXTVEC+1
	jmp tresult

; npots: compare X with the number of paddles (twice the ports): Z set at
; the end.
npots	lda NPORT
	asl
	sta MTMP
	cpx MTMP
	rts

; potscan: wait a frame, read all eight, start the next scan.
potscan	jsr vsync
	ldx #0
ps_rd	lda POT0,x
	sta PCUR,x
	inx
	cpx #8
	bne ps_rd
	lda #3			; SKCTL bit 2: fast scan (a couple of scanlines)
	ldx PFAST
	beq ps_n
	lda #7
ps_n	sta SKCTL
	sta POTGO
	rts

; potshow: row 8+n per paddle: "P1 <bar> VAL MIN MAX JIT T".
potshow	lda DISPOK
	bne pw_go
	rts
pw_go	PRINT 7, 0, s_pdh
	lda PFAST
	beq pw_r
	PRINT 7, 0, s_fast
pw_r	ldx #0
pw_lp	stx CNT
	txa
	clc
	adc #8
	ldx #0
	jsr at
	lda #$30		; 'P'
	jsr putc
	lda CNT
	clc
	adc #$11
	jsr putc
	lda #0
	jsr putc
	ldx CNT			; the bar: value/12, up to 19 inverse spaces
	lda PCUR,x
	ldy #0
pw_div	cmp #12
	bcc pw_bar
	sbc #12
	iny
	bne pw_div
pw_bar	ldx #19
pw_b	lda #0
	cpy #0
	beq pw_sp
	lda #$80
	dey
pw_sp	jsr putc
	dex
	bne pw_b
	ldx CNT
	lda PCUR,x
	jsr put3
	ldx CNT
	lda PMIN,x
	jsr put3
	ldx CNT
	lda PMAX,x
	jsr put3
	ldx CNT
	lda PJIT,x
	jsr put3
	lda #0
	jsr putc
	ldx CNT			; the trigger: a joystick direction line
	jsr ptrig
	lda #0
	bcc pw_t
	lda #$B4		; inverse 'T'
pw_t	jsr putc
	ldx CNT
	inx
	jsr npots
	beq pw_x
	jmp pw_lp
pw_x	rts

; ptrig: C set if paddle X's trigger is pressed. Paddles 0-1 are PORTA bits
; 2-3, 2-3 bits 6-7; 4-7 the same in PORTB (400/800).
ptrig	txa
	and #3
	tay
	lda PORTA
	cpx #4
	bcc pt_a
	lda PORTB
pt_a	and ptbit,y
	clc
	bne pt_x
	sec
pt_x	rts
ptbit	.byte $04, $08, $40, $80

; put3: A as " nnn" (three digits, leading zeros).
put3	pha
	lda #0
	jsr putc
	pla
	ldx #0
p3_h	cmp #100
	bcc p3_t
	sbc #100
	inx
	bne p3_h
p3_t	pha
	txa
	clc
	adc #$10
	jsr putc
	pla
	ldx #0
p3_tl	cmp #10
	bcc p3_o
	sbc #10
	inx
	bne p3_tl
p3_o	pha
	txa
	clc
	adc #$10
	jsr putc
	pla
	clc
	adc #$10
	jmp putc

; ---------------------------------------------------------------------------
; Test 7: GTIA by eye. Eight luminance steps and sixteen hues, drawn by
; changing COLPF2 down the screen with WSYNC (no interrupts). The video
; standard is shown. Item 1: the user says the ramps look wrong (or no
; answer in 30 s).
GL_ROW	= 5			; first text row of the luminance ramp
GH_ROW	= 13			; first text row of the hue ramp
t_gtia	lda #7
	sta TEST
	lda #<s_t7
	ldy #>s_t7
	jsr tpage
	lda DISPOK
	beq gt_g
	PRINT 4, 0, s_glum
	PRINT 12, 0, s_ghue
	PRINT 21, 0, s_gq
	lda #<s_vntsc
	ldy #>s_vntsc
	ldx ISPAL
	beq gt_v
	lda #<s_vpal
	ldy #>s_vpal
gt_v	pha
	tya
	pha
	lda #3
	ldx #0
	jsr at
	pla
	tay
	pla
	jsr puts
gt_g	lda #30
	jsr settime
	jsr waitrel
gt_lp	lda VCOUNT		; luminance: 8 steps of 8 lines
	cmp #[32+GL_ROW*8]/2
	bne gt_lp
	ldx #0
gt_l	txa
	asl
	sta WSYNC
	sta COLPF2
	ldy #7
gt_l1	sta WSYNC
	dey
	bne gt_l1
	inx
	cpx #8
	bne gt_l
	sta WSYNC
	lda #C_TEXTBG
	sta COLPF2
gt_w	lda VCOUNT		; hue: 16 steps of 4 lines
	cmp #[32+GH_ROW*8]/2
	bne gt_w
	ldx #0
gt_h	txa
	asl
	asl
	asl
	asl
	ora #8
	sta WSYNC
	sta COLPF2
	ldy #3
gt_h1	sta WSYNC
	dey
	bne gt_h1
	inx
	cpx #16
	bne gt_h
	sta WSYNC
	lda #C_TEXTBG
	sta COLPF2
	lda SKSTAT		; the answer, polled once a frame
	and #4
	bne gt_c
	lda KBCODE
	and #$3F
	cmp #$2B		; Y
	beq gt_yes
	cmp #$23		; N
	beq gt_no
gt_c	lda CONSOL
	lsr
	bcc gt_yes
	lsr
	bcc gt_no
	jsr rtick
	beq gt_no
	jmp gt_lp
gt_no	lda #1
	sta BADMASK+7
gt_yes	jsr waitrel
	lda DISPOK
	beq gt_end
	lda #21
	jsr clrrow
gt_end	lda #<summary
	sta NEXTVEC
	lda #>summary
	sta NEXTVEC+1
	jmp tresult

; ---------------------------------------------------------------------------
; summary: all seven tests and the ROM sums, then the final code: every test
; with a failed item, A = test, B = item.
summary	lda DISPOK
	beq su_fin
	jsr sushow
su_fin	lda #0
	sta CONTVEC+1
	lda #7			; pass: one long flash per test
	sta NBANKS
	lda #8			; tshow, as redraw, shows the summary from here
	sta TEST
	ldx #7
su_any	lda BADMASK,x
	bne su_bad
	dex
	bne su_any
	jmp pass
su_bad	jmp report

sushow	jsr scr_on
	lda #<s_hsum
	ldy #>s_hsum
	jsr header
	lda #2
	jsr machinfo
	ldx #1
su_lp	stx CNT
	txa
	clc
	adc #3
	ldx #0
	jsr at
	lda CNT
	asl
	tax
	lda tnames-2,x
	ldy tnames-1,x
	jsr puts
	lda CNT			; status at column 18
	clc
	adc #3
	ldx #18
	jsr at
	ldx CNT
	lda BADMASK,x
	bne su_f
	lda #<s_pass
	ldy #>s_pass
	jsr puts
	jmp su_n
su_f	sta MTMP
	lda #<s_fail
	ldy #>s_fail
	jsr puts
	ldx #0
su_it	lsr MTMP
	bcc su_nx
	lda #0
	jsr putc
	txa
	clc
	adc #$11
	jsr putc
su_nx	inx
	cpx #8
	bne su_it
su_n	ldx CNT
	inx
	cpx #8
	bne su_lp
	lda #12
	jsr romsums
	PRINT 18, 0, s_items2
	PRINT 23, 0, s_toggle2
	rts

	icl '../common/report.asm'
	icl '../common/screen.asm'
	icl '../common/info.asm'
	icl 't3common.asm'

s_hpre	dta d' A8 DIAG  TAPE 3/3  ',$FF
s_hsum	dta d'SUMMARY',$FF
s_os	dta d'OS ROM        SUM ',$FF
s_bas	dta d'BASIC ROM     SUM ',$FF
s_cart	dta d'CARTRIDGE     SUM ',$FF
s_selft	dta d'SELF-TEST ROM SUM ',$FF
s_romnote dta d'NO REVISION TABLE YET: NOTE THE SUMS',$FF
s_pk1	dta d'TIMER AND RANDOM CHECKED. NOW BY EAR:',$FF
s_voice	dta d'PLAYING VOICE ',$FF
s_heard	dta d'HEARD IT? Y/START = YES, N/SELECT = NO',$FF
s_joy1	dta d'MOVE EACH STICK, PRESS FIRE. START ENDS.',$FF
s_stick	dta d'STICK ',$FF
s_up	dta d'UP',$FF
s_down	dta d'DOWN',$FF
s_left	dta d'LEFT',$FF
s_right	dta d'RIGHT',$FF
s_fire	dta d'FIRE',$FF
s_pd1	dta d'UNPLUG ALL PADDLES, THEN PRESS START',$FF
s_pd2	dta d'(SELECT SKIPS THE OPEN-INPUT CHECK)',$FF
s_pd3	dta d'TURN EACH. SELECT=FAST SCAN. START ENDS.',$FF
s_pdh	dta d'                       VAL MIN MAX JIT',$FF
s_fast	dta d'FAST SCAN'*,$FF
s_glum	dta d'LUMINANCE: 8 EVEN STEPS, BLACK TO WHITE',$FF
s_ghue	dta d'HUES: 16 DIFFERENT COLORS',$FF
s_gq	dta d'RAMPS RIGHT? Y/START=YES, N/SELECT=NO',$FF
s_vpal	dta d'VIDEO: PAL ',$FF
s_vntsc	dta d'VIDEO: NTSC',$FF
s_items2 dta d'FAIL N: ITEM N. THE CODE IS TEST, ITEM.',$FF
s_toggle2 dta d'SELECT=REPLAY  OPTION=FULL-SCREEN FLASH',$FF

PADTO	= [[*+2+$FF]/$100]*$100
	.if PADTO-*-2>0
	:[PADTO-*-2] .byte 0
	.endif
S2SUM	.word 0			; mkcas.py: sum of every byte before this
IMGEND
NREC	= [IMGEND-S2LOAD]/128
BSS	= IMGEND
	.if [>BSS]+1>$50
	.error "stage 2 too big: must stay below the XL self-test ROM at $5000"
	.endif
