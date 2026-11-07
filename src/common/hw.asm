; Atari 8-bit hardware registers used by the diag tapes.
; Shadow registers are deliberately absent: interrupts are off, so the OS
; never copies shadows to hardware. Everything here writes the chips directly.

; GTIA
COLBK	= $D01A		; border/background; shown even with ANTIC DMA off
PAL	= $D014		; bits 1-3: %000 = PAL, %111 = NTSC
CONSOL	= $D01F		; read: START/SELECT/OPTION (0 = pressed); write bit 3: speaker
TRIG0	= $D010		; joystick fire, 0 = pressed
TRIG1	= $D011
COLPF1	= $D017		; GRAPHICS 0 text luminance
COLPF2	= $D018		; GRAPHICS 0 text background
HPOSP0	= $D000		; P/M horizontal positions: P0-P3 $D000-3, M0-M3 $D004-7
SIZEP0	= $D008		; player widths, P0-P3 (3 = quadruple)
SIZEM	= $D00C		; missile widths, 2 bits each
COLPM0	= $D012		; player/missile colors, P0-P3 $D012-5 (missile n: COLPMn)
PRIOR	= $D01B		; 1 = players in front of the playfield
GRACTL	= $D01D		; 3 = take players and missiles from DMA

; POKEY
AUDF1	= $D200
AUDC1	= $D201
AUDCTL	= $D208
KBCODE	= $D209
SKCTL	= $D20F		; write 3 = normal keyboard/serial operation
SKSTAT	= $D20F
IRQEN	= $D20E
IRQST	= $D20E		; read: 0 bits = interrupt pending (latched even with SEI)

; PIA
PORTA	= $D300
PORTB	= $D301
PACTL	= $D302		; bit 3: cassette motor ($34 = on, $3C = off)

; ANTIC
DMACTL	= $D400
CHACTL	= $D401		; 2 = show inverse characters
DLISTL	= $D402
DLISTH	= $D403
CHBASE	= $D409		; font page; $E0 = OS ROM font
PMBASE	= $D407		; P/M memory page (1K-aligned for double-line resolution)
WSYNC	= $D40A		; any write halts the CPU until the next horizontal blank
VCOUNT	= $D40B
NMIEN	= $D40E

; Colors (hue/lum). Hues shift a little between NTSC and PAL; these stay
; readable as green/yellow/red on both.
C_GREEN	= $C8
C_YELLOW = $1C
C_RED	= $34
C_PURPLE = $56		; last chance on the video check
C_BLACK	= $00

; POKEY pure tone, volume 8 / volume 0
AUD_ON	= $A8
AUD_OFF	= $A0

; POKEY AUDF values (AUDCTL=0, 64 kHz clock): f = 63921 / (2 * (N + 1))
F_LONG	= 72		; ~440 Hz  group A (where)
F_SHORT	= 35		; ~880 Hz  group B (which bit)
F_END	= 144		; ~220 Hz  end of list
F_J1	= 60		; ~523 Hz  pass jingle
F_J2	= 47		; ~659 Hz
F_J3	= 40		; ~784 Hz
F_SIRH	= 50		; ~627 Hz  siren
F_SIRL	= 67		; ~470 Hz
