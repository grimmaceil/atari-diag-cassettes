; Fault injection and speed flags (mads -d:NAME=value), shared by all stages.
;   FAULT_BANK=0..9, FAULT_BIT=1..8   fake stuck bit; 0 = low RAM, 4 = under the
;                                     XL OS, 5-8 = 130XE banks, 9 = loader area
;   FAULT_EVERY=n                     burn-in: inject only every n-th pass
;   FAST=1                            skip the $55/$AA march pass

	.ifndef FAULT_BANK
FAULT_BANK = -1
FAULT_BIT = 1
	.endif
	.ifndef FAST
FAST	= 0
	.endif
FAULT_MASK = 1<<[FAULT_BIT-1]

; FAULTINJ: flip FMASK bits in A after a read, in fault builds only.
.macro FAULTINJ
	.if FAULT_BANK>0
	eor FMASK
	.endif
.endm
