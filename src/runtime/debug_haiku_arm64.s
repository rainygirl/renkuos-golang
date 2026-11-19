#include "textflag.h"

TEXT runtime·dbgw(SB),NOSPLIT,$16
	MOVB	R0, 8(RSP)
	MOVD	$2, R0
	MOVD	RSP, R1
	ADD	$8, R1
	MOVD	$1, R2
	BL	libc_write(SB)
	RET
