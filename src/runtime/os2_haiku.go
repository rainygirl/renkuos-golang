// Copyright 2011 The Go Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

package runtime

import (
	"internal/abi"
	"internal/runtime/atomic"
	"unsafe"
)

//go:cgo_export_dynamic runtime.end _end
//go:cgo_export_dynamic runtime.etext _etext
//go:cgo_export_dynamic runtime.edata _edata

//go:cgo_import_dynamic libc__errnop _errnop "libroot.so"
//go:cgo_import_dynamic libc_clock_gettime clock_gettime "libroot.so"
//go:cgo_import_dynamic libc_exit _exit "libroot.so"
//go:cgo_import_dynamic libc_fstat fstat#LIBROOT_BASE "libroot.so"
//go:cgo_import_dynamic libc_getcontext getcontext "libroot.so"
//go:cgo_import_dynamic libc_kill kill "libroot.so"
//go:cgo_import_dynamic libc_madvise madvise "libroot.so"
//go:cgo_import_dynamic libc_getrlimit getrlimit "libroot.so"
//go:cgo_import_dynamic libc_malloc malloc "libroot.so"
//go:cgo_import_dynamic libc_mmap mmap "libroot.so"
//go:cgo_import_dynamic libc_munmap munmap "libroot.so"
//go:cgo_import_dynamic libc_open open "libroot.so"
//go:cgo_import_dynamic libc_pthread_attr_destroy pthread_attr_destroy "libroot.so"
//go:cgo_import_dynamic libc_pthread_attr_getstacksize pthread_attr_getstacksize "libroot.so"
//go:cgo_import_dynamic libc_pthread_attr_init pthread_attr_init "libroot.so"
//go:cgo_import_dynamic libc_pthread_detach pthread_detach "libroot.so"
//go:cgo_import_dynamic libc_pthread_attr_setstack pthread_attr_setstack "libroot.so"
//go:cgo_import_dynamic libc_pthread_create pthread_create "libroot.so"
//go:cgo_import_dynamic libc_pthread_self pthread_self "libroot.so"
//go:cgo_import_dynamic libc_pthread_kill pthread_kill "libroot.so"
//go:cgo_import_dynamic libc_raise raise "libroot.so"
//go:cgo_import_dynamic libc_read read "libroot.so"
//go:cgo_import_dynamic libc__kern_read _kern_read "libroot.so"
//go:cgo_import_dynamic libc_select select "libroot.so"
//go:cgo_import_dynamic libc_sched_yield sched_yield "libroot.so"
//go:cgo_import_dynamic libc_sem_init sem_init "libroot.so"
//go:cgo_import_dynamic libc_sem_post sem_post "libroot.so"
//go:cgo_import_dynamic libc_sem_timedwait sem_timedwait "libroot.so"
//go:cgo_import_dynamic libc_sem_wait sem_wait "libroot.so"
//go:cgo_import_dynamic libc_setitimer setitimer "libroot.so"
//go:cgo_import_dynamic libc_sigaction __sigaction "libroot.so"
//go:cgo_import_dynamic libc_sigaltstack sigaltstack "libroot.so"
//go:cgo_import_dynamic libc_sigprocmask __sigprocmask "libroot.so"
//go:cgo_import_dynamic libc_sysconf sysconf#LIBROOT_BASE "libroot.so"
//go:cgo_import_dynamic libc_usleep usleep "libroot.so"
//go:cgo_import_dynamic libc_write write "libroot.so"
//go:cgo_import_dynamic libc_pipe2 pipe2 "libroot.so"
//go:cgo_import_dynamic libc_area_for area_for "libroot.so"

//go:linkname libc__errnop libc__errnop
//go:linkname libc_clock_gettime libc_clock_gettime
//go:linkname libc_exit libc_exit
//go:linkname libc_fstat libc_fstat
//go:linkname libc_getcontext libc_getcontext
//go:linkname libc_kill libc_kill
//go:linkname libc_madvise libc_madvise
//go:linkname libc_getrlimit libc_getrlimit
//go:linkname libc_malloc libc_malloc
//go:linkname libc_mmap libc_mmap
//go:linkname libc_munmap libc_munmap
//go:linkname libc_open libc_open
//go:linkname libc_pthread_attr_destroy libc_pthread_attr_destroy
//go:linkname libc_pthread_attr_getstacksize libc_pthread_attr_getstacksize
//go:linkname libc_pthread_attr_init libc_pthread_attr_init
//go:linkname libc_pthread_detach libc_pthread_detach
//go:linkname libc_pthread_attr_setstack libc_pthread_attr_setstack
//go:linkname libc_pthread_create libc_pthread_create
//go:linkname libc_pthread_self libc_pthread_self
//go:linkname libc_pthread_kill libc_pthread_kill
//go:linkname libc_raise libc_raise
//go:linkname libc_read libc_read
//go:linkname libc__kern_read libc__kern_read
//go:linkname libc_select libc_select
//go:linkname libc_sched_yield libc_sched_yield
//go:linkname libc_sem_init libc_sem_init
//go:linkname libc_sem_post libc_sem_post
//go:linkname libc_sem_timedwait libc_sem_timedwait
//go:linkname libc_sem_wait libc_sem_wait
//go:linkname libc_setitimer libc_setitimer
//go:linkname libc_sigaction libc_sigaction
//go:linkname libc_sigaltstack libc_sigaltstack
//go:linkname libc_sigprocmask libc_sigprocmask
//go:linkname libc_sysconf libc_sysconf
//go:linkname libc_usleep libc_usleep
//go:linkname libc_write libc_write
//go:linkname libc_pipe2 libc_pipe2
//go:linkname libc_area_for libc_area_for

var (
	libc__errnop,
	libc_clock_gettime,
	libc_exit,
	libc_fstat,
	libc_getcontext,
	libc_getrlimit,
	libc_kill,
	libc_madvise,
	libc_malloc,
	libc_mmap,
	libc_munmap,
	libc_open,
	libc_pthread_attr_destroy,
	libc_pthread_attr_getstacksize,
	libc_pthread_attr_init,
	libc_pthread_detach,
	libc_pthread_attr_setstack,
	libc_pthread_create,
	libc_pthread_self,
	libc_pthread_kill,
	libc_raise,
	libc_read,
	libc__kern_read,
	libc_sched_yield,
	libc_select,
	libc_sem_init,
	libc_sem_post,
	libc_sem_timedwait,
	libc_sem_wait,
	libc_setitimer,
	libc_sigaction,
	libc_sigaltstack,
	libc_sigprocmask,
	libc_sysconf,
	libc_usleep,
	libc_write,
	libc_area_for,
	libc_pipe2 libcFunc
)

const (
	_CLOCK_REALTIME  = 0xffffffff
	_CLOCK_MONOTONIC = 0
)

var sigset_all = ^sigset(0)
var sigset_none = sigset(0)

func getCPUCount() int32 {
	n := int32(sysconf(__SC_NPROCESSORS_ONLN))
	if n < 1 {
		return 1
	}
	return n
}

func getPageSize() uintptr {
	n := int32(sysconf(__SC_PAGESIZE))
	if n <= 0 {
		return 0
	}
	return uintptr(n)
}

func osinit() {
	// Note: TLS slot 4 (TLS_USER_THREAD_SLOT) does NOT need to be set
	// up here. It looked like it did, from a kernel-level "write to
	// unmapped address" fault inside read()'s internal
	// pthread_testcancel()->pthread_self()->get_user_thread(), which
	// derefs whatever tls_get(4) returns. But Haiku's kernel itself
	// (src/system/kernel/thread.cpp's enter_userspace(), via
	// arch_thread_init_tls + a raw tls[] array it builds and copies
	// into thread->user_local_storage) already populates TLS slot 4
	// with a valid `struct user_thread*` for every thread -- including
	// the very first thread of a freshly exec'd process -- before any
	// userspace code (a normal CRT or Go's rt0_go) ever runs. A prior
	// attempt here called __allocate_pthread + tls_set(4, ...) to
	// mimic Haiku's CRT, but that overwrites the kernel's already-valid
	// user_thread* with a malloc'd pthread_thread* of a completely
	// different layout (user_thread is {pthread_t pthread; uint32
	// flags; ...}, not pthread_thread) -- which is the actual cause of
	// the fault, not a missing bootstrap step. Do not reintroduce this.

	// Call miniterrno so that we can safely make system calls
	// before calling minit on m0.
	asmcgocall(unsafe.Pointer(abi.FuncPCABI0(miniterrno)), unsafe.Pointer(&libc__errnop))

	numCPUStartup = getCPUCount()
	if physPageSize == 0 {
		physPageSize = getPageSize()
	}
	var buf [8]byte
	n := readRandom(buf[:])
	_ = n
}

func tstart_sysvicall(newm *m) uint32

// May run with m.p==nil, so write barriers are not allowed.
//
//go:nowritebarrier
func newosproc(mp *m) {
	var (
		attr pthreadattr
		oset sigset
		tid  pthread
		ret  int32
	)

	if pthread_attr_init(&attr) != 0 {
		throw("pthread_attr_init")
	}

	// This libroot.so has no pthread_attr_setdetachstate; detach the
	// thread after creation via pthread_detach instead.

	// Disable signals during create, so that the new thread starts
	// with signals disabled. It will enable them in minit.
	sigprocmask(_SIG_SETMASK, &sigset_all, &oset)
	ret = retryOnEAGAIN(func() int32 {
		return pthread_create(&tid, &attr, abi.FuncPCABI0(tstart_sysvicall), unsafe.Pointer(mp))
	})
	sigprocmask(_SIG_SETMASK, &oset, nil)
	if ret != 0 {
		print("runtime: failed to create new OS thread (have ", mcount(), " already; errno=", ret, ")\n")
		if ret == -_EAGAIN {
			println("runtime: may need to increase max user processes (ulimit -u)")
		}
		throw("newosproc")
	}
	if pthread_detach(tid) != 0 {
		throw("pthread_detach")
	}
}

func exitThread(wait *atomic.Uint32) {
	// We should never reach exitThread on Haiku because we let
	// libroot clean up threads.
	throw("exitThread")
}

var urandom_dev = []byte("/dev/random\x00")

//go:nosplit
func readRandom(r []byte) int {
	fd := open(&urandom_dev[0], 0 /* O_RDONLY */, 0)
	n := read(fd, unsafe.Pointer(&r[0]), int32(len(r)))
	closefd(fd)
	return int(n)
}

func goenvs() {
	goenvs_unix()
}

// Called to initialize a new m (including the bootstrap m).
// Called on the parent thread (main thread in case of bootstrap), can allocate memory.
func mpreinit(mp *m) {
	mp.gsignal = malg(32 * 1024)
	mp.gsignal.m = mp
}

func miniterrno()

// Called to initialize a new m (including the bootstrap m).
// Called on the new thread, cannot allocate memory.
func minit() {
	asmcgocall(unsafe.Pointer(abi.FuncPCABI0(miniterrno)), unsafe.Pointer(&libc__errnop))

	minitSignals()

	getg().m.procid = uint64(pthread_self())
}

// Called from dropm to undo the effect of an minit.
func unminit() {
	unminitSignals()
}

// Called from exitm, but not from drop, to undo the effect of thread-owned
// resources in minit, semacreate, or elsewhere. Do not take locks after calling this.
func mdestroy(mp *m) {
}

func sigtramp()

//go:nosplit
//go:nowritebarrierrec
func setsig(i uint32, fn uintptr) {
	var sa sigactiont

	sa.sa_flags = _SA_SIGINFO | _SA_ONSTACK | _SA_RESTART
	sa.sa_mask = sigset_all
	if fn == abi.FuncPCABIInternal(sighandler) { // abi.FuncPCABIInternal(sighandler) matches the callers in signal_unix.go
		fn = abi.FuncPCABI0(sigtramp)
	}
	*((*uintptr)(unsafe.Pointer(&sa._funcptr))) = fn
	sigaction(i, &sa, nil)
}

//go:nosplit
//go:nowritebarrierrec
func setsigstack(i uint32) {
	var sa sigactiont
	sigaction(i, nil, &sa)
	if sa.sa_flags&_SA_ONSTACK != 0 {
		return
	}
	sa.sa_flags |= _SA_ONSTACK
	sigaction(i, &sa, nil)
}

//go:nosplit
//go:nowritebarrierrec
func getsig(i uint32) uintptr {
	var sa sigactiont
	sigaction(i, nil, &sa)
	return *((*uintptr)(unsafe.Pointer(&sa._funcptr)))
}

// setSignalstackSP sets the ss_sp field of a stackt.
//
//go:nosplit
func setSignalstackSP(s *stackt, sp uintptr) {
	*(*uintptr)(unsafe.Pointer(&s.ss_sp)) = sp
}

//go:nosplit
//go:nowritebarrierrec
func sigaddset(mask *sigset, i int) {
	*mask |= 1 << (sigset(i) - 1)
}

func sigdelset(mask *sigset, i int) {
	*mask &^= 1 << (sigset(i) - 1)
}

//go:nosplit
func (c *sigctxt) fixsigcode(sig uint32) {
}

func setProcessCPUProfiler(hz int32) {
	setProcessCPUProfilerTimer(hz)
}

func setThreadCPUProfiler(hz int32) {
	setThreadCPUProfilerHz(hz)
}

//go:nosplit
func validSIGPROF(mp *m, c *sigctxt) bool {
	return true
}

//go:nosplit
func semacreate(mp *m) {
	if mp.waitsema != 0 {
		return
	}

	var sem *semt

	// Call libc's malloc rather than malloc. This will
	// allocate space on the C heap. We can't call malloc
	// here because it could cause a deadlock.
	mp.libcall.fn = uintptr(unsafe.Pointer(&libc_malloc))
	mp.libcall.n = 1
	mp.scratch = mscratch{}
	mp.scratch.v[0] = unsafe.Sizeof(*sem)
	mp.libcall.args = uintptr(unsafe.Pointer(&mp.scratch))
	asmcgocall(unsafe.Pointer(&asmsysvicall6x), unsafe.Pointer(&mp.libcall))
	sem = (*semt)(unsafe.Pointer(mp.libcall.r1))
	if sem_init(sem, 0, 0) != 0 {
		throw("sem_init")
	}
	mp.waitsema = uintptr(unsafe.Pointer(sem))
}

//go:nosplit
func semasleep(ns int64) int32 {
	mp := getg().m
	if ns >= 0 {
		var ts timespec

		if clock_gettime(_CLOCK_REALTIME, &ts) != 0 {
			throw("clock_gettime")
		}
		ts.tv_sec += ns / 1e9
		ts.tv_nsec += ns % 1e9
		if ts.tv_nsec >= 1e9 {
			ts.tv_sec++
			ts.tv_nsec -= 1e9
		}

		if r, err := sem_timedwait((*semt)(unsafe.Pointer(mp.waitsema)), &ts); r != 0 {
			if err == _ETIMEDOUT || err == _EAGAIN || err == _EINTR {
				return -1
			}
			println("sem_timedwait err ", err, " ts.tv_sec ", ts.tv_sec, " ts.tv_nsec ", ts.tv_nsec, " ns ", ns, " id ", mp.id)
			throw("sem_timedwait")
		}
		return 0
	}
	for {
		r1, err := sem_wait((*semt)(unsafe.Pointer(mp.waitsema)))
		if r1 == 0 {
			break
		}
		if err == _EINTR {
			continue
		}
		throw("sem_wait")
	}
	return 0
}

//go:nosplit
func semawakeup(mp *m) {
	if sem_post((*semt)(unsafe.Pointer(mp.waitsema))) != 0 {
		throw("sem_post")
	}
}





//go:nosplit
func getcontext(context *ucontext) /* int32 */ {
	sysvicall1(&libc_getcontext, uintptr(unsafe.Pointer(context)))
}



//go:nosplit
func mmap(addr unsafe.Pointer, n uintptr, prot, flags, fd int32, off uint32) (unsafe.Pointer, int) {
	p, err := doMmap(uintptr(addr), n, uintptr(prot), uintptr(flags), uintptr(fd), uintptr(off))
	if p == ^uintptr(0) {
		return nil, int(err)
	}
	return unsafe.Pointer(p), 0
}





// nanotime1 and write1 bypass the generic sysvicall dispatcher the same
// way sigaction/sigprocmask do above: they sit on the badsignal/needm
// nosplit chain (reached when a signal arrives on a non-Go thread), and
// the generic dispatcher's frame is too big to fit that chain's budget.

//go:nosplit
//go:cgo_unsafe_args
func nanotime1() int64 {
	// clockid is hardcoded to CLOCK_MONOTONIC in nanotime_trampoline
	// itself, so the only argument that needs passing is &ts -- no
	// local args struct needed. Calls asmcgocall directly rather than
	// through libcCall (skipping libcCall's profiler-traceback
	// bookkeeping, not needed for a near-instant clock read): this
	// sits on the same nosplit-budget-constrained badsignal/needm
	// chain write1 does, with no room left for libcCall's own frame.
	var ts mts
	asmcgocall(unsafe.Pointer(abi.FuncPCABI0(nanotime_trampoline)), unsafe.Pointer(&ts))
	return ts.tv_sec*1e9 + ts.tv_nsec
}
func nanotime_trampoline()



//go:nosplit
func setNonblock(fd int32) {
	flags, _ := fcntl(fd, _F_GETFL, 0)
	if flags != -1 {
		fcntl(fd, _F_SETFL, flags|_O_NONBLOCK)
	}
}





// func pthread_attr_getstack(attr *pthreadattr, addr unsafe.Pointer, size *uint64) int32 {
// 	return int32(sysvicall3(&libc_pthread_attr_getstack, uintptr(unsafe.Pointer(attr)), uintptr(addr), uintptr(unsafe.Pointer(size))))
// }































// sigaction and sigprocmask bypass the generic sysvicall3 dispatcher
// (which builds a libcall struct and goes through asmsysvicall6) and
// call a small, fixed-arity assembly trampoline instead, directly
// via libcCall. This keeps their nosplit stack frames small enough
// to fit the nosplit budget of the signal-handling call chain that
// reaches them (dieFromSignal -> unblocksig -> sigprocmask, and
// setsig -> sigaction), mirroring the darwin/openbsd approach in
// sys_libc.go.

//go:nosplit
//go:nowritebarrierrec
//go:cgo_unsafe_args
func sigaction(sig uint32, act *sigactiont, oact *sigactiont) /* int32 */ {
	libcCall(unsafe.Pointer(abi.FuncPCABI0(sigaction_trampoline)), unsafe.Pointer(&sig))
}
func sigaction_trampoline()



//go:nosplit
//go:nowritebarrierrec
//go:cgo_unsafe_args
func sigprocmask(how int32, set *sigset, oset *sigset) /* int32 */ {
	libcCall(unsafe.Pointer(abi.FuncPCABI0(sigprocmask_trampoline)), unsafe.Pointer(&how))
}
func sigprocmask_trampoline()

// sysconf bypasses the generic sysvicall1 dispatcher and calls a
// dedicated direct-BL trampoline instead: the real libroot sysconf
// (sysconf@LIBROOT_BASE, actually __sysconf_beos, which itself tail-
// branches through __sysconf@plt for any value other than one
// hardcoded legacy case) behaves correctly when reached via a direct
// BL (as every other working libc call in this port already does),
// but produced unreliable results when reached via asmsysvicall6's
// indirect BLR-through-a-loaded-function-pointer dispatch -- unlike
// every other libc call tested, which works fine either way. Root
// cause not fully isolated; the direct-call trampoline is the same
// proven-reliable mechanism write1/nanotime1/sigaction/sigprocmask
// already use, so route this one the same way rather than carry a
// mechanism known to misbehave for it.
//
//go:nosplit
//go:cgo_unsafe_args
func sysconf(name int32) int64 {
	return int64(libcCall(unsafe.Pointer(abi.FuncPCABI0(sysconf_trampoline)), unsafe.Pointer(&name)))
}
func sysconf_trampoline()

func usleep1(usec uint32)







//go:nosplit
//go:cgo_unsafe_args
func write1(fd uintptr, buf unsafe.Pointer, nbyte int32) int32 {
	// Take the address of fd itself rather than building a separate
	// local args struct: go:cgo_unsafe_args keeps fd, buf, nbyte laid
	// out contiguously on the stack in declaration order, so &fd
	// already points at a valid (fd, buf, nbyte) block. Building a
	// second copy would double the frame for no reason, and this
	// function sits on a nosplit chain (badsignal -> needm ->
	// writeErrData -> write -> write1) with little budget to spare.
	ret := libcCall(unsafe.Pointer(abi.FuncPCABI0(write_trampoline)), unsafe.Pointer(&fd))
	KeepAlive(buf)
	return ret
}
func write_trampoline()



//go:nosplit
func closeonexec(fd int32) {
	fcntl(fd, _F_SETFD, _FD_CLOEXEC)
}

func osyield1()

//go:nosplit
func osyield_no_g() {
	osyield1()
}

//go:nosplit
func osyield() {
	// Use the same lightweight osyield1 raw trampoline osyield_no_g
	// does, rather than the generic sysvicall0 dispatcher: osyield is
	// called from casgstatus's spin-wait, which is reachable from the
	// badsignal/needm/dropm nosplit chain and has no budget left for
	// sysvicall0+asmcgocall's full frame.
	osyield1()
}



// sigPerThreadSyscall is only used on linux, so we assign a bogus signal
// number.
const sigPerThreadSyscall = 1 << 31

//go:nosplit
func runPerThreadSyscall() {
	throw("runPerThreadSyscall only valid on linux")
}

//go:nowritebarrierrec
//go:nosplit
func libpreinit() {}

//go:nowritebarrierrec
//go:nosplit
func newosproc0(stacksize uintptr, fn unsafe.Pointer) {
	throw("bad newosproc0")
}


//go:nosplit
//go:cgo_unsafe_args
func closefd(fd int32) int32 {
	return libcCall(unsafe.Pointer(abi.FuncPCABI0(closefd_trampoline)), unsafe.Pointer(&fd))
}
func closefd_trampoline()

//go:nosplit
//go:cgo_unsafe_args
func exit(r int32) {
	libcCall(unsafe.Pointer(abi.FuncPCABI0(exit_trampoline)), unsafe.Pointer(&r))
}
func exit_trampoline()

//go:nosplit
//go:cgo_unsafe_args
func madvise(addr unsafe.Pointer, n uintptr, flags int32) {
	libcCall(unsafe.Pointer(abi.FuncPCABI0(madvise_trampoline)), unsafe.Pointer(&addr))
	KeepAlive(n)
}
func madvise_trampoline()

//go:nosplit
//go:cgo_unsafe_args
func open(path *byte, mode, perm int32) int32 {
	return libcCall(unsafe.Pointer(abi.FuncPCABI0(open_trampoline)), unsafe.Pointer(&path))
}
func open_trampoline()

//go:cgo_unsafe_args
func pthread_attr_destroy(attr *pthreadattr) int32 {
	return libcCall(unsafe.Pointer(abi.FuncPCABI0(pthread_attr_destroy_trampoline)), unsafe.Pointer(&attr))
}
func pthread_attr_destroy_trampoline()

//go:cgo_unsafe_args
func pthread_attr_init(attr *pthreadattr) int32 {
	return libcCall(unsafe.Pointer(abi.FuncPCABI0(pthread_attr_init_trampoline)), unsafe.Pointer(&attr))
}
func pthread_attr_init_trampoline()

//go:cgo_unsafe_args
func pthread_detach(t pthread) int32 {
	return libcCall(unsafe.Pointer(abi.FuncPCABI0(pthread_detach_trampoline)), unsafe.Pointer(&t))
}
func pthread_detach_trampoline()

//go:cgo_unsafe_args
func pthread_attr_setstack(attr *pthreadattr, addr uintptr, size uint64) int32 {
	return libcCall(unsafe.Pointer(abi.FuncPCABI0(pthread_attr_setstack_trampoline)), unsafe.Pointer(&attr))
}
func pthread_attr_setstack_trampoline()

//go:cgo_unsafe_args
func pthread_create(thread *pthread, attr *pthreadattr, fn uintptr, arg unsafe.Pointer) int32 {
	return libcCall(unsafe.Pointer(abi.FuncPCABI0(pthread_create_trampoline)), unsafe.Pointer(&thread))
}
func pthread_create_trampoline()

// pthread_t is a pointer on Haiku, but libcCall returns an int32: the
// trampoline stores the full 64-bit result through its argument instead.
// (Returning it through libcCall truncated it to 32 bits and sign-extended
// it, so m.procid was not a valid pthread_t and the pthread_kill in signalM
// -- async preemption's SIGURG -- faulted inside libroot.)
func pthread_self() pthread {
	var t pthread
	libcCall(unsafe.Pointer(abi.FuncPCABI0(pthread_self_trampoline)), unsafe.Pointer(&t))
	return t
}
func pthread_self_trampoline()

func getpid() int32 {
	return libcCall(unsafe.Pointer(abi.FuncPCABI0(getpid_trampoline)), nil)
}
func getpid_trampoline()

func issetugid() int32 {
	return libcCall(unsafe.Pointer(abi.FuncPCABI0(issetugid_trampoline)), nil)
}
func issetugid_trampoline()

func signalM(mp *m, sig int) {
	args := struct {
		tid uintptr
		sig uintptr
	}{uintptr(pthread(mp.procid)), uintptr(sig)}
	libcCall(unsafe.Pointer(abi.FuncPCABI0(pthread_kill_trampoline)), unsafe.Pointer(&args))
}
func pthread_kill_trampoline()

//go:nosplit
//go:nowritebarrierrec
func raise(sig uint32) /* int32 */ {
	libcCall(unsafe.Pointer(abi.FuncPCABI0(raise_trampoline)), unsafe.Pointer(&sig))
}
func raise_trampoline()

func raiseproc(sig uint32) /* int32 */ {
	pid := getpid()
	args := struct {
		pid uintptr
		sig uintptr
	}{uintptr(pid), uintptr(sig)}
	libcCall(unsafe.Pointer(abi.FuncPCABI0(kill_trampoline)), unsafe.Pointer(&args))
}
func kill_trampoline()

//go:nosplit
//go:cgo_unsafe_args
func read(fd int32, buf unsafe.Pointer, nbyte int32) int32 {
	// Mirrors write_trampoline's proven pattern exactly: take the
	// address of read's own first parameter (go:cgo_unsafe_args keeps
	// fd, buf, nbyte contiguous) and rely on libcCall's own int32
	// return rather than writing a result back into a struct after
	// the call returns. read's only caller (readRandom) only uses the
	// byte count, never errno, so there's no need to fetch it here.
	ret := libcCall(unsafe.Pointer(abi.FuncPCABI0(read_trampoline)), unsafe.Pointer(&fd))
	KeepAlive(buf)
	return ret
}
func read_trampoline()

//go:nosplit
func sem_init(sem *semt, pshared int32, value uint32) int32 {
	args := struct {
		sem     unsafe.Pointer
		pshared uintptr
		value   uintptr
	}{unsafe.Pointer(sem), uintptr(pshared), uintptr(value)}
	return libcCall(unsafe.Pointer(abi.FuncPCABI0(sem_init_trampoline)), unsafe.Pointer(&args))
}
func sem_init_trampoline()

//go:nosplit
//go:cgo_unsafe_args
func sem_post(sem *semt) int32 {
	return libcCall(unsafe.Pointer(abi.FuncPCABI0(sem_post_trampoline)), unsafe.Pointer(&sem))
}
func sem_post_trampoline()

//go:nosplit
func sem_wait(sem *semt) (int32, int32) {
	args := struct {
		sem    unsafe.Pointer
		result uintptr
		err    uintptr
	}{unsafe.Pointer(sem), 0, 0}
	asmcgocall(unsafe.Pointer(abi.FuncPCABI0(sem_wait_trampoline)), unsafe.Pointer(&args))
	return int32(args.result), int32(args.err)
}
func sem_wait_trampoline()

//go:nosplit
func sem_timedwait(sem *semt, timeout *timespec) (int32, int32) {
	args := struct {
		sem     unsafe.Pointer
		timeout unsafe.Pointer
		result  uintptr
		err     uintptr
	}{unsafe.Pointer(sem), unsafe.Pointer(timeout), 0, 0}
	asmcgocall(unsafe.Pointer(abi.FuncPCABI0(sem_timedwait_trampoline)), unsafe.Pointer(&args))
	return int32(args.result), int32(args.err)
}
func sem_timedwait_trampoline()

//go:nosplit
func clock_gettime(clockid uint32, tp *timespec) int32 {
	args := struct {
		clockid uintptr
		tp      unsafe.Pointer
	}{uintptr(clockid), unsafe.Pointer(tp)}
	return libcCall(unsafe.Pointer(abi.FuncPCABI0(clock_gettime_trampoline)), unsafe.Pointer(&args))
}
func clock_gettime_trampoline()

func setitimer(which int32, value *itimerval, ovalue *itimerval) /* int32 */ {
	args := struct {
		which  uintptr
		value  unsafe.Pointer
		ovalue unsafe.Pointer
	}{uintptr(which), unsafe.Pointer(value), unsafe.Pointer(ovalue)}
	libcCall(unsafe.Pointer(abi.FuncPCABI0(setitimer_trampoline)), unsafe.Pointer(&args))
}
func setitimer_trampoline()

//go:nosplit
//go:nowritebarrierrec
func sigaltstack(ss *stackt, oss *stackt) /* int32 */ {
	args := struct {
		ss  unsafe.Pointer
		oss unsafe.Pointer
	}{unsafe.Pointer(ss), unsafe.Pointer(oss)}
	libcCall(unsafe.Pointer(abi.FuncPCABI0(sigaltstack_trampoline)), unsafe.Pointer(&args))
}
func sigaltstack_trampoline()

//go:nosplit
//go:cgo_unsafe_args
func usleep_no_g(usec uint32) {
	libcCall(unsafe.Pointer(abi.FuncPCABI0(usleep_trampoline)), unsafe.Pointer(&usec))
}

//go:nosplit
//go:cgo_unsafe_args
func usleep(usec uint32) {
	libcCall(unsafe.Pointer(abi.FuncPCABI0(usleep_trampoline)), unsafe.Pointer(&usec))
}
func usleep_trampoline()

func walltime() (sec int64, nsec int32) {
	var ts mts
	args := struct {
		clockid uintptr
		tp      unsafe.Pointer
	}{uintptr(_CLOCK_REALTIME), unsafe.Pointer(&ts)}
	libcCall(unsafe.Pointer(abi.FuncPCABI0(clock_gettime_trampoline)), unsafe.Pointer(&args))
	return ts.tv_sec, int32(ts.tv_nsec)
}

//go:nosplit
func pipe2(flags int32) (r, w int32, errno int32) {
	var p [2]int32
	args := struct {
		p      unsafe.Pointer
		flags  uintptr
		result uintptr
		err    uintptr
	}{unsafe.Pointer(&p), uintptr(flags), 0, 0}
	asmcgocall(unsafe.Pointer(abi.FuncPCABI0(pipe2_trampoline)), unsafe.Pointer(&args))
	return p[0], p[1], int32(args.err)
}
func pipe2_trampoline()

func area_for(addr uintptr) {
	libcCall(unsafe.Pointer(abi.FuncPCABI0(area_for_trampoline)), unsafe.Pointer(&addr))
}
func area_for_trampoline()

//go:nosplit
func fcntl(fd, cmd, arg int32) (ret int32, errno int32) {
	args := struct {
		fd     uintptr
		cmd    uintptr
		arg    uintptr
		result uintptr
		err    uintptr
	}{uintptr(fd), uintptr(cmd), uintptr(arg), 0, 0}
	asmcgocall(unsafe.Pointer(abi.FuncPCABI0(fcntl_trampoline)), unsafe.Pointer(&args))
	return int32(args.result), int32(args.err)
}
func fcntl_trampoline()

//go:nosplit
func munmap(addr unsafe.Pointer, n uintptr) {
	args := struct {
		addr unsafe.Pointer
		n    uintptr
	}{addr, n}
	libcCall(unsafe.Pointer(abi.FuncPCABI0(munmap_trampoline)), unsafe.Pointer(&args))
}
func munmap_trampoline()

//go:nosplit
func doMmap(addr, n, prot, flags, fd, off uintptr) (uintptr, uintptr) {
	args := struct {
		addr, n, prot, flags, fd, off uintptr
		result, err                   uintptr
	}{addr, n, prot, flags, fd, off, 0, 0}
	asmcgocall(unsafe.Pointer(abi.FuncPCABI0(mmap6_trampoline)), unsafe.Pointer(&args))
	return args.result, args.err
}
func mmap6_trampoline()

