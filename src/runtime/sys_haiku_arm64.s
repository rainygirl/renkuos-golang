// Copyright 2014 The Go Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.
//
// System calls and other sys.stuff for ARM64, Haiku.
// Haiku syscalls go through libroot.so, so these are
// trampolines that convert from Go to the SysV/AAPCS64
// calling convention, following the same generic
// asmsysvicall6 dispatcher design as sys_haiku_amd64.s.

#include "go_asm.h"
#include "go_tls.h"
#include "textflag.h"
#include "cgo/abi_arm64.h"
#include "tls_arm64.h"

// void libc_miniterrno(void *(*_errnop)(void));
//
// Set the TLS errno pointer in M.
//
// Called using runtime·asmcgocall from os_haiku.go's minit.
// NOT USING GO CALLING CONVENTION.
TEXT runtime·miniterrno(SB),NOSPLIT,$0
	// asmcgocall will put first argument into R0.
	MOVD	R0, R9
	BL	(R9)	// returns errno location in R0
	MOVD	g_m(g), R1
	MOVD	R0, (m_mOS+mOS_perrno)(R1)
	RET

// Call a library function with SysV/AAPCS64 calling conventions.
// The called function can take up to 6 INTEGER class arguments
// (plus overflow args read off libcall.args beyond the 6th, mirroring
// the amd64 dispatcher's design, though Haiku libroot calls used by
// this port never need more than 6).
//
// Called by runtime·asmcgocall or runtime·cgocall.
// NOT USING GO CALLING CONVENTION.
TEXT runtime·asmsysvicall6(SB),NOSPLIT,$32
	// asmcgocall will put first argument (libcall*) into R0.
	MOVD	R0, 16(RSP)
	MOVD	libcall_fn(R0), R9
	MOVD	libcall_args(R0), R10
	MOVD	libcall_n(R0), R11

	CMP	$0, g
	BEQ	skiperrno1
	MOVD	g_m(g), R12
	CMP	$0, R12
	BEQ	skiperrno1
	MOVD	(m_mOS+mOS_perrno)(R12), R13
	CMP	$0, R13
	BEQ	skiperrno1
	MOVW	$0, R14
	MOVW	R14, (R13)

skiperrno1:
	// Check libcall.n (R11), not libcall.args (R10): args is always
	// non-nil by convention even for zero-arg calls (sysvicall0 sets
	// it to the target function's own address, since it must be
	// non-nil but is otherwise unused) -- unconditionally reading up
	// to 6*8 bytes from there runs straight into the target
	// function's own machine code and can walk off the end of its
	// mapped page for a short function, faulting before the call
	// ever happens. n correctly reflects how many argument slots
	// actually exist to read.
	CMP	$0, R11
	BEQ	skipargs
	// Load up to 6 args into argument registers.
	MOVD	(0*8)(R10), R0
	MOVD	(1*8)(R10), R1
	MOVD	(2*8)(R10), R2
	MOVD	(3*8)(R10), R3
	MOVD	(4*8)(R10), R4
	MOVD	(5*8)(R10), R5
skipargs:

	// Call the libroot function.
	BL	(R9)

	// Save result.
	MOVD	16(RSP), R12
	MOVD	R0, libcall_r1(R12)
	MOVD	R1, libcall_r2(R12)

	CMP	$0, g
	BEQ	skiperrno2
	MOVD	g_m(g), R13
	CMP	$0, R13
	BEQ	skiperrno2
	MOVD	(m_mOS+mOS_perrno)(R13), R0
	CMP	$0, R0
	BEQ	skiperrno2
	MOVW	(R0), R0
	MOVD	R0, libcall_err(R12)

skiperrno2:
	RET

// uint32 tstart_sysvicall(M *newm);
TEXT runtime·tstart_sysvicall(SB),NOSPLIT,$0
	// R0 contains first arg newm
	MOVD	m_g0(R0), R1	// g

	// Make the new m's g0 the active g.
	MOVD	R0, g_m(R1)
	MOVD	R1, g
	// Also publish it in the TLS slot load_g reads (see tls_arm64.h),
	// so a signal landing before the first g switch still finds it.
	BL	runtime·save_g(SB)	// clobbers R0 and R27, not g
	MOVD	g, R1
	MOVD	g_m(g), R0

	// Layout new m scheduler stack on os stack.
	MOVD	RSP, R2
	MOVD	R2, (g_stack+stack_hi)(R1)
	SUB	$(0x100000), R2	// stack size
	MOVD	R2, (g_stack+stack_lo)(R1)
	ADD	$const_stackGuard, R2
	MOVD	R2, g_stackguard0(R1)
	MOVD	R2, g_stackguard1(R1)

	BL	runtime·mstart(SB)

	MOVD	$0, R0	// return 0 == success
	RET

// Stack frame layout for sigtramp below (offsets from RSP, no overlap).
// 0(RSP) is NOT free: on arm64 the Go assembler's prologue stores this
// function's own return address (LR) there, so the first usable slot is
// 8(RSP) -- the same reason every other arm64 port (linux, darwin,
// openbsd) starts its saved arguments at 8*1(RSP). An earlier version
// of this file copied sys_haiku_amd64.s's 0(SP)/8(SP)/16(SP) layout
// (correct on amd64, where CALL pushes the return address below SP):
// `MOVW R0, 0(RSP)` overwrote the low 32 bits of the saved LR with the
// signal number, so sigtramp could never return to Haiku's
// commpage signal handler, and the thread died in a fault loop with
// every signal blocked (sa_mask is sigset_all). That, plus the ABI
// mismatch described at the sigtrampgo call below, is why Go programs
// on haiku/arm64 never saw SIGTERM/SIGINT/SIGCHLD/SIGURG.
//   8   sig
//   16  info
//   24  ctx
//   32  tmp sigctxt.info (badsignal path only)
//   40  tmp sigctxt.ctxt (badsignal path only)
//   48  R19..R28 saved  (80 bytes)
//   128 F8..F15 saved   (64 bytes)
//   192 libcall fn/args/n/r1/r2 saved (40 bytes)
//   232 scratch[0..5] saved (48 bytes)
//   280 saved errno (8 bytes)
// total 288.

// Called by Haiku's commpage signal handler (arch_user_signal_handler)
// as handler(sig, info, ctx, userdata), and returns to it, which then
// does _kern_restore_signal_frame. We must preserve callee-saved
// registers per AAPCS64.
TEXT runtime·sigtramp(SB),NOSPLIT|TOPFRAME,$288
	// Save callee-save registers, in case this is a cgo callback
	// or we're forwarding a signal.
	SAVE_R19_TO_R28(48)
	SAVE_F8_TO_F15(128)

	// Save arguments.
	MOVW	R0, 8(RSP)	// sig
	MOVD	R1, 16(RSP)	// info
	MOVD	R2, 24(RSP)	// ctx

	// This might be called in external code context,
	// where g is not set. load_g reads g from TLS (see tls_arm64.h:
	// on haiku g is always kept in a TLS slot, not only under cgo),
	// so this does not depend on R28 still holding g, which it need
	// not when the signal interrupted a libc call.
	BL	runtime·load_g(SB)

	CMP	$0, g
	BNE	allgood
	MOVD	16(RSP), R1
	MOVD	24(RSP), R2
	MOVD	R1, 32(RSP)	// tmp sigctxt.info
	MOVD	R2, 40(RSP)	// tmp sigctxt.ctxt
	MOVWU	8(RSP), R0	// sig
	MOVD	$32(RSP), R1	// &tmp sigctxt
	// badsignal is a Go function: call its register-ABI entry point
	// directly with the arguments in R0/R1 (a plain BL from assembly
	// would bind to the ABI0 wrapper, which reads them from 8(RSP)
	// and 16(RSP) instead).
	MOVD	$runtime·badsignal<ABIInternal>(SB), R3
	BL	(R3)
	B	exit

allgood:
	// Save m->libcall and m->scratch, since we might be interrupted
	// by a signal in the middle of runtime·asmcgocall.
	MOVD	g_m(g), R19

	MOVD	(m_mOS+mOS_libcall+libcall_fn)(R19), R10
	MOVD	R10, 192(RSP)
	MOVD	(m_mOS+mOS_libcall+libcall_args)(R19), R10
	MOVD	R10, 200(RSP)
	MOVD	(m_mOS+mOS_libcall+libcall_n)(R19), R10
	MOVD	R10, 208(RSP)
	MOVD	(m_mOS+mOS_libcall+libcall_r1)(R19), R10
	MOVD	R10, 216(RSP)
	MOVD	(m_mOS+mOS_libcall+libcall_r2)(R19), R10
	MOVD	R10, 224(RSP)

	MOVD	(m_mOS+mOS_scratch+0*8)(R19), R10
	MOVD	R10, 232(RSP)
	MOVD	(m_mOS+mOS_scratch+1*8)(R19), R10
	MOVD	R10, 240(RSP)
	MOVD	(m_mOS+mOS_scratch+2*8)(R19), R10
	MOVD	R10, 248(RSP)
	MOVD	(m_mOS+mOS_scratch+3*8)(R19), R10
	MOVD	R10, 256(RSP)
	MOVD	(m_mOS+mOS_scratch+4*8)(R19), R10
	MOVD	R10, 264(RSP)
	MOVD	(m_mOS+mOS_scratch+5*8)(R19), R10
	MOVD	R10, 272(RSP)

	// Save errno; stuff we do here might reset it.
	MOVD	(m_mOS+mOS_perrno)(R19), R10
	CBZ	R10, noerrno_save
	MOVW	(R10), R10
	MOVD	R10, 280(RSP)
noerrno_save:

	// Call sigtrampgo(sig, info, ctx) through its register-ABI entry
	// point, with the arguments in R0-R2, exactly as
	// sys_linux_arm64.s/sys_darwin_arm64.s do. A plain
	// `BL runtime·sigtrampgo(SB)` binds to the ABI0 wrapper, which
	// reads its arguments from 8/16/24(RSP) -- so with the old layout
	// sigtrampgo got info as sig and ctx as info.
	MOVWU	8(RSP), R0
	MOVD	16(RSP), R1
	MOVD	24(RSP), R2
	MOVD	$runtime·sigtrampgo<ABIInternal>(SB), R3
	BL	(R3)

	BL	runtime·load_g(SB)
	MOVD	g_m(g), R19

	// Restore libcall.
	MOVD	192(RSP), R10
	MOVD	R10, (m_mOS+mOS_libcall+libcall_fn)(R19)
	MOVD	200(RSP), R10
	MOVD	R10, (m_mOS+mOS_libcall+libcall_args)(R19)
	MOVD	208(RSP), R10
	MOVD	R10, (m_mOS+mOS_libcall+libcall_n)(R19)
	MOVD	216(RSP), R10
	MOVD	R10, (m_mOS+mOS_libcall+libcall_r1)(R19)
	MOVD	224(RSP), R10
	MOVD	R10, (m_mOS+mOS_libcall+libcall_r2)(R19)

	// Restore scratch.
	MOVD	232(RSP), R10
	MOVD	R10, (m_mOS+mOS_scratch+0*8)(R19)
	MOVD	240(RSP), R10
	MOVD	R10, (m_mOS+mOS_scratch+1*8)(R19)
	MOVD	248(RSP), R10
	MOVD	R10, (m_mOS+mOS_scratch+2*8)(R19)
	MOVD	256(RSP), R10
	MOVD	R10, (m_mOS+mOS_scratch+3*8)(R19)
	MOVD	264(RSP), R10
	MOVD	R10, (m_mOS+mOS_scratch+4*8)(R19)
	MOVD	272(RSP), R10
	MOVD	R10, (m_mOS+mOS_scratch+5*8)(R19)

	// Restore errno.
	MOVD	(m_mOS+mOS_perrno)(R19), R10
	CBZ	R10, exit
	MOVD	280(RSP), R11
	MOVW	R11, (R10)

exit:
	RESTORE_R19_TO_R28(48)
	RESTORE_F8_TO_F15(128)
	RET

TEXT runtime·sigfwd(SB),NOSPLIT,$0-32
	MOVD	fn+0(FP),    R11
	MOVW	sig+8(FP),   R0
	MOVD	info+16(FP), R1
	MOVD	ctx+24(FP),  R2
	BL	(R11)
	RET

// Called from runtime·usleep (Go). Can be called on Go stack, on OS stack,
// can also be called in cgo callback path without a g->m.
TEXT runtime·usleep1(SB),NOSPLIT,$0
	MOVW	usec+0(FP), R0
	MOVD	$runtime·usleep2(SB), R9 // hoist before stack switch

	CMP	$0, g
	BEQ	usleep1_noswitch

	MOVD	g_m(g), R1
	CMP	$0, R1
	BEQ	usleep1_noswitch

	MOVD	m_g0(R1), R2
	CMP	g, R2
	BNE	usleep1_switch
	// executing on m->g0 already
	BL	(R9)
	RET

usleep1_switch:
	// Switch to m->g0 stack and back.
	MOVD	RSP, R19
	MOVD	(g_sched+gobuf_sp)(R2), R2
	MOVD	R2, RSP
	BL	(R9)
	MOVD	R19, RSP
	RET

usleep1_noswitch:
	// Not a Go-managed thread. Do not switch stack.
	BL	(R9)
	RET

// Runs on OS stack. duration (in µs units) is in R0.
TEXT usleep2<>(SB),NOSPLIT,$0
	BL	libc_usleep(SB)
	RET

// Runs on OS stack, called from runtime·osyield.
TEXT runtime·osyield1(SB),NOSPLIT,$0
	BL	libc_sched_yield(SB)
	RET

// how, new, old unix.sigprocmask args laid out contiguously on the Go
// stack (go:cgo_unsafe_args), passed as a single struct pointer in R0.
TEXT runtime·sigprocmask_trampoline(SB),NOSPLIT,$0
	MOVD	8(R0), R1	// arg2 new
	MOVD	16(R0), R2	// arg3 old
	MOVW	0(R0), R0	// arg1 how
	BL	libc_sigprocmask(SB)
	RET

// sig, act, oact args, same calling convention as sigprocmask_trampoline.
TEXT runtime·sigaction_trampoline(SB),NOSPLIT,$0
	MOVD	8(R0), R1	// arg2 act
	MOVD	16(R0), R2	// arg3 oact
	MOVW	0(R0), R0	// arg1 sig
	BL	libc_sigaction(SB)
	RET

// R0 holds &ts directly (the only thing nanotime1 passes). clockid is
// CLOCK_MONOTONIC (0), hardcoded here rather than passed, to avoid
// needing a local args struct on the caller's (budget-constrained)
// nosplit frame.
TEXT runtime·nanotime_trampoline(SB),NOSPLIT,$0
	MOVD	R0, R1	// arg2 ts
	MOVD	$0, R0	// arg1 clockid = CLOCK_MONOTONIC
	BL	libc_clock_gettime(SB)
	RET

// fd, buf, nbyte (struct{ fd uintptr; buf unsafe.Pointer; nbyte int32 })
// passed as a single struct pointer in R0. Returns the byte count on
// success, or the positive errno value on failure (same contract the
// old sysvicall3Err-based write1 had), fetched via the per-M errno
// pointer the same way asmsysvicall6 does, since this bypasses that
// dispatcher's own errno handling entirely.
TEXT runtime·write_trampoline(SB),NOSPLIT,$0
	MOVD	8(R0), R1	// arg2 buf
	MOVW	16(R0), R2	// arg3 nbyte
	MOVW	0(R0), R0	// arg1 fd
	BL	libc_write(SB)
	CMP	$0, R0
	BGE	write_ok
	CMP	$0, g
	BEQ	write_errno0
	MOVD	g_m(g), R9
	MOVD	(m_mOS+mOS_perrno)(R9), R9
	CMP	$0, R9
	BEQ	write_errno0
	MOVW	(R9), R0
	RET
write_errno0:
	MOVD	$0, R0
	RET
write_ok:
	RET

// name (int32) passed as a single struct pointer in R0 (go:cgo_unsafe_args
// keeps sysconf's own parameter stable across the call).
TEXT runtime·sysconf_trampoline(SB),NOSPLIT,$0
	MOVW	(R0), R0
	BL	libc_sysconf(SB)
	RET

TEXT runtime·closefd_trampoline(SB),NOSPLIT,$0
	MOVD	0(R0), R0
	BL	libc_close(SB)
	RET

TEXT runtime·madvise_trampoline(SB),NOSPLIT,$0
	MOVD	8(R0), R1
	MOVD	16(R0), R2
	MOVD	0(R0), R0
	BL	libc_madvise(SB)
	RET

TEXT runtime·open_trampoline(SB),NOSPLIT,$0
	MOVD	8(R0), R1
	MOVD	16(R0), R2
	MOVD	0(R0), R0
	BL	libc_open(SB)
	RET

TEXT runtime·pthread_attr_destroy_trampoline(SB),NOSPLIT,$0
	MOVD	0(R0), R0
	BL	libc_pthread_attr_destroy(SB)
	RET

TEXT runtime·pthread_attr_init_trampoline(SB),NOSPLIT,$0
	MOVD	0(R0), R0
	BL	libc_pthread_attr_init(SB)
	RET

TEXT runtime·pthread_detach_trampoline(SB),NOSPLIT,$0
	MOVD	0(R0), R0
	BL	libc_pthread_detach(SB)
	RET

TEXT runtime·pthread_attr_setstack_trampoline(SB),NOSPLIT,$0
	MOVD	8(R0), R1
	MOVD	16(R0), R2
	MOVD	0(R0), R0
	BL	libc_pthread_attr_setstack(SB)
	RET

TEXT runtime·pthread_create_trampoline(SB),NOSPLIT,$0
	MOVD	8(R0), R1
	MOVD	16(R0), R2
	MOVD	24(R0), R3
	MOVD	0(R0), R0
	BL	libc_pthread_create(SB)
	RET

TEXT runtime·sem_init_trampoline(SB),NOSPLIT,$0
	MOVD	8(R0), R1
	MOVD	16(R0), R2
	MOVD	0(R0), R0
	BL	libc_sem_init(SB)
	RET

TEXT runtime·sem_post_trampoline(SB),NOSPLIT,$0
	MOVD	0(R0), R0
	BL	libc_sem_post(SB)
	RET

TEXT runtime·setitimer_trampoline(SB),NOSPLIT,$0
	MOVD	8(R0), R1
	MOVD	16(R0), R2
	MOVD	0(R0), R0
	BL	libc_setitimer(SB)
	RET

TEXT runtime·sigaltstack_trampoline(SB),NOSPLIT,$0
	MOVD	8(R0), R1
	MOVD	0(R0), R0
	BL	libc_sigaltstack(SB)
	RET

TEXT runtime·usleep_trampoline(SB),NOSPLIT,$0
	MOVD	0(R0), R0
	BL	libc_usleep(SB)
	RET

TEXT runtime·area_for_trampoline(SB),NOSPLIT,$0
	MOVD	0(R0), R0
	BL	libc_area_for(SB)
	RET

TEXT runtime·munmap_trampoline(SB),NOSPLIT,$0
	MOVD	8(R0), R1
	MOVD	0(R0), R0
	BL	libc_munmap(SB)
	RET

// mmap's error convention is exactly -1 (MAP_FAILED) on failure, not
// "negative" -- a valid high mapped address has its sign bit set too,
// so this can't reuse the generic negative-means-error errno pattern.
// The args pointer must be saved on the stack (not a scratch register
// like R9-R15): those are caller-saved per AAPCS64 and the external
// mmap call is free to clobber them.
TEXT runtime·mmap6_trampoline(SB),NOSPLIT,$32
	MOVD	R0, 16(RSP)
	MOVD	8(R0), R1
	MOVD	16(R0), R2
	MOVD	24(R0), R3
	MOVD	32(R0), R4
	MOVD	40(R0), R5
	MOVD	0(R0), R0
	BL	libc_mmap(SB)
	MOVD	16(RSP), R10
	MOVD	R0, 48(R10)
	MOVD	$-1, R1
	CMP	R0, R1
	BNE	mmap6_ok
	CMP	$0, g
	BEQ	mmap6_errno0
	MOVD	g_m(g), R9
	MOVD	(m_mOS+mOS_perrno)(R9), R9
	CMP	$0, R9
	BEQ	mmap6_errno0
	MOVW	(R9), R1
	MOVD	R1, 56(R10)
	RET
mmap6_errno0:
	MOVD	$0, 56(R10)
	RET
mmap6_ok:
	MOVD	$0, 56(R10)
	RET


TEXT runtime·pthread_kill_trampoline(SB),NOSPLIT,$0
	MOVD	8(R0), R1
	MOVD	0(R0), R0
	BL	libc_pthread_kill(SB)
	RET

TEXT runtime·kill_trampoline(SB),NOSPLIT,$0
	MOVD	8(R0), R1
	MOVD	0(R0), R0
	BL	libc_kill(SB)
	RET

TEXT runtime·raise_trampoline(SB),NOSPLIT,$0
	MOVD	0(R0), R0
	BL	libc_raise(SB)
	RET

TEXT runtime·clock_gettime_trampoline(SB),NOSPLIT,$0
	MOVD	8(R0), R1
	MOVD	0(R0), R0
	BL	libc_clock_gettime(SB)
	RET

TEXT runtime·exit_trampoline(SB),NOSPLIT,$0
	MOVD	0(R0), R0
	BL	libc_exit(SB)
	RET

// R0 holds a *pthread to store the result in (see pthread_self in
// os2_haiku.go for why it is not returned in R0).
TEXT runtime·pthread_self_trampoline(SB),NOSPLIT,$32
	MOVD	R0, 16(RSP)
	BL	libc_pthread_self(SB)
	MOVD	16(RSP), R1
	MOVD	R0, 0(R1)
	RET

TEXT runtime·getpid_trampoline(SB),NOSPLIT,$0
	BL	libc_getpid(SB)
	RET

TEXT runtime·issetugid_trampoline(SB),NOSPLIT,$0
	BL	libc_issetugid(SB)
	RET

// Calls _kern_read(fd, pos, buf, nbyte) directly, bypassing libroot's
// read() wrapper entirely -- not just for the two MOVD-instead-of-MOVW
// width bugs that wrapper variant had (nbyte and fd are both int32 at
// offsets 16/0, so an 8-byte load pulled in 4 bytes of adjacent stack
// garbage as the high bits of the size_t count argument), but because
// read()'s own post-syscall pthread_testcancel() call reliably faults
// when invoked this early: readRandom() (read's only caller) runs from
// osinit(), which Go's own bootstrap (see the comment above schedinit
// in proc.go) calls strictly *before* minit() ever runs on this thread.
// minit() is what calls minitSignals() (sigaltstack) and only then
// pthread_self() to register the thread with the Go runtime; at the
// osinit() point none of that per-thread registration libroot's own
// pthread_self()/pthread_testcancel() silently depend on has happened
// yet, and pthread_testcancel()'s internal pthread_self() call faults
// (confirmed via serial.log: fault always inside libroot.so's
// pthread_self()+0x10, called from pthread_testcancel()+0xc, called
// from read()+0x24 -- i.e. after _kern_read itself already succeeded).
// write() never hits this because nothing calls it this early; using
// the raw kernel entry point for read sidesteps the whole class of bug
// since Go never needs POSIX cancellation semantics anyway.
TEXT runtime·read_trampoline(SB),NOSPLIT,$0
	MOVD	8(R0), R2	// arg3: buf
	MOVW	16(R0), R3	// arg4: nbyte
	MOVD	$-1, R1	// arg2: pos (current position)
	MOVW	0(R0), R0	// arg1: fd (last -- clobbers the base pointer)
	BL	libc__kern_read(SB)
	RET

// The error check below uses CMPW (32-bit compare) against exactly -1,
// not CMP (64-bit) against 0 with BGE: sem_wait's C return type is a
// plain 32-bit `int` (POSIX convention, always exactly -1 on error, see
// Haiku's RETURN_AND_SET_ERRNO_TEST_CANCEL), and libroot.so's own
// compiled epilogue returns it via a 32-bit (W-register) MOV, which per
// AAPCS64/AArch64 hardware semantics zero-extends -- not sign-extends
// -- into the upper 32 bits of X0 (confirmed by disassembly). A real
// -1 therefore arrives here as X0 == 0x00000000FFFFFFFF, a large
// *positive* 64-bit value: the old `CMP $0, R0; BGE sem_wait_ok` took
// the success branch on every single real error, silently hardcoding
// err=0 instead of fetching the actual errno. Downstream, Go's
// semasleep() truncates the stored result back to int32 (so r1 comes
// out as the correct -1), but err stayed 0 -- matching neither
// _ETIMEDOUT, _EAGAIN nor _EINTR, so semasleep's ns<0 "for { ... if
// err == _EINTR { continue } ... }" loop in lock_sema.go never knows
// it needs to retry; it just hangs waiting on something that already
// failed. CMPW's 32-bit-wide compare matches Go's own existing idiom
// for this exact hazard on darwin/openbsd arm64 (CMPW $-1, R0).
TEXT runtime·sem_wait_trampoline(SB),NOSPLIT,$32
	MOVD	R0, 16(RSP)
	MOVD	0(R0), R0
	BL	libc_sem_wait(SB)
	MOVD	16(RSP), R10
	MOVD	R0, 8(R10)
	CMPW	$-1, R0
	BNE	sem_wait_ok
	CMP	$0, g
	BEQ	sem_wait_errno0
	MOVD	g_m(g), R9
	MOVD	(m_mOS+mOS_perrno)(R9), R9
	CMP	$0, R9
	BEQ	sem_wait_errno0
	MOVW	(R9), R1
	MOVD	R1, 16(R10)
	RET
sem_wait_errno0:
	MOVD	$0, 16(R10)
	RET
sem_wait_ok:
	MOVD	$0, 16(R10)
	RET

// See sem_wait_trampoline above for why this is CMPW $-1 rather than
// CMP $0/BGE: same 32-bit-return-zero-extended-into-X0 hazard, and
// this is the path that actually proved it -- GODEBUG=asyncpreemptoff=1
// made it reproduce fast and loud ("fatal error: sem_timedwait",
// err printed as 0) because notetsleep_internal's deadline loop
// legitimately lets sem_timedwait time out (err should be
// _ETIMEDOUT) far more often once async preemption stops keeping
// every M busy with real work.
TEXT runtime·sem_timedwait_trampoline(SB),NOSPLIT,$32
	MOVD	R0, 16(RSP)
	MOVD	8(R0), R1
	MOVD	0(R0), R0
	BL	libc_sem_timedwait(SB)
	MOVD	16(RSP), R10
	MOVD	R0, 16(R10)
	CMPW	$-1, R0
	BNE	sem_timedwait_ok
	CMP	$0, g
	BEQ	sem_timedwait_errno0
	MOVD	g_m(g), R9
	MOVD	(m_mOS+mOS_perrno)(R9), R9
	CMP	$0, R9
	BEQ	sem_timedwait_errno0
	MOVW	(R9), R1
	MOVD	R1, 24(R10)
	RET
sem_timedwait_errno0:
	MOVD	$0, 24(R10)
	RET
sem_timedwait_ok:
	MOVD	$0, 24(R10)
	RET

// Same CMPW-vs-CMP/BGE fix as sem_wait_trampoline/sem_timedwait_trampoline
// above: pipe2() also returns a plain 32-bit int, -1 on error.
TEXT runtime·pipe2_trampoline(SB),NOSPLIT,$32
	MOVD	R0, 16(RSP)
	MOVD	8(R0), R1
	MOVD	0(R0), R0
	BL	libc_pipe2(SB)
	MOVD	16(RSP), R10
	MOVD	R0, 16(R10)
	CMPW	$-1, R0
	BNE	pipe2_ok
	CMP	$0, g
	BEQ	pipe2_errno0
	MOVD	g_m(g), R9
	MOVD	(m_mOS+mOS_perrno)(R9), R9
	CMP	$0, R9
	BEQ	pipe2_errno0
	MOVW	(R9), R1
	MOVD	R1, 24(R10)
	RET
pipe2_errno0:
	MOVD	$0, 24(R10)
	RET
pipe2_ok:
	MOVD	$0, 24(R10)
	RET

// Same CMPW-vs-CMP/BGE fix as sem_wait_trampoline/sem_timedwait_trampoline
// above: fcntl() also returns a plain 32-bit int, -1 on error.
TEXT runtime·fcntl_trampoline(SB),NOSPLIT,$32
	MOVD	R0, 16(RSP)
	MOVD	8(R0), R1
	MOVD	16(R0), R2
	MOVD	0(R0), R0
	BL	libc_fcntl(SB)
	MOVD	16(RSP), R10
	MOVD	R0, 24(R10)
	CMPW	$-1, R0
	BNE	fcntl_ok
	CMP	$0, g
	BEQ	fcntl_errno0
	MOVD	g_m(g), R9
	MOVD	(m_mOS+mOS_perrno)(R9), R9
	CMP	$0, R9
	BEQ	fcntl_errno0
	MOVW	(R9), R1
	MOVD	R1, 32(R10)
	RET
fcntl_errno0:
	MOVD	$0, 32(R10)
	RET
fcntl_ok:
	MOVD	$0, 32(R10)
	RET
