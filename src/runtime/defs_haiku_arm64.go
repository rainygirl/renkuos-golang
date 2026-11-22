// Created by hand, following the pattern of defs_haiku_amd64.go
// (itself cgo -godefs defs_haiku.go) adapted for Haiku's arm64
// struct vregs (headers/posix/arch/arm64/signal.h).

package runtime

const (
	_EINTR     = -0x7ffffff6
	_EFAULT    = -0x7fffecff
	_EAGAIN    = -0x7ffffff5
	_ENOMEM    = -0x80000000
	_ETIMEDOUT = -0x7ffffff7
	_EACCES    = -0x7ffffffe

	_PROT_NONE  = 0x0
	_PROT_READ  = 0x1
	_PROT_WRITE = 0x2
	_PROT_EXEC  = 0x4

	_MAP_ANON    = 0x8
	_MAP_PRIVATE = 0x2
	_MAP_FIXED   = 0x4

	_MADV_DONTNEED = 0x5
	_MADV_FREE     = 0x6

	_SA_SIGINFO = 0x40
	_SA_RESTART = 0x10
	_SA_ONSTACK = 0x20

	_SIGHUP    = 0x1
	_SIGINT    = 0x2
	_SIGQUIT   = 0x3
	_SIGILL    = 0x4
	_SIGTRAP   = 0x16
	_SIGABRT   = 0x6
	_SIGFPE    = 0x8
	_SIGKILL   = 0x9
	_SIGBUS    = 0x1e
	_SIGSEGV   = 0xb
	_SIGSYS    = 0x19
	_SIGPIPE   = 0x7
	_SIGALRM   = 0xe
	_SIGTERM   = 0xf
	_SIGURG    = 0x1a
	_SIGSTOP   = 0xa
	_SIGTSTP   = 0xd
	_SIGCONT   = 0xc
	_SIGCHLD   = 0x5
	_SIGTTIN   = 0x10
	_SIGTTOU   = 0x11
	_SIGXCPU   = 0x1c
	_SIGXFSZ   = 0x1d
	_SIGVTALRM = 0x1b
	_SIGPROF   = 0x18
	_SIGWINCH  = 0x14
	_SIGUSR1   = 0x12
	_SIGUSR2   = 0x13

	_FPE_INTDIV = 0x14
	_FPE_INTOVF = 0x15
	_FPE_FLTDIV = 0x16
	_FPE_FLTOVF = 0x17
	_FPE_FLTUND = 0x18
	_FPE_FLTRES = 0x19
	_FPE_FLTINV = 0x1a
	_FPE_FLTSUB = 0x1b

	_BUS_ADRALN = 0x28
	_BUS_ADRERR = 0x29
	_BUS_OBJERR = 0x2a

	_SEGV_MAPERR = 0x1e
	_SEGV_ACCERR = 0x1f

	_ITIMER_REAL    = 0x1
	_ITIMER_VIRTUAL = 0x2
	_ITIMER_PROF    = 0x3

	_PTHREAD_CREATE_DETACHED = 0x1

	_HOST_NAME_MAX = 0xff

	_O_NONBLOCK = 0x80
	_O_CLOEXEC  = 0x40
	_FD_CLOEXEC = 0x1
	_F_GETFL    = 0x8
	_F_SETFL    = 0x10
	_F_SETFD    = 0x4

	__SC_PAGESIZE         = 0x1b
	__SC_NPROCESSORS_ONLN = 0x23

	_MAXHOSTNAMELEN = 0x100

	_O_CREAT  = 0x200
	_O_WRONLY = 0x1
	_O_TRUNC  = 0x400

	_B_PAGE_SIZE = 0x1000

	_B_ERROR = -0x1
)

type semt struct {
	sem_type int32
	u        [4]byte
	sem_pad1 [2]int32
}

type sigset uint64

type stackt struct {
	ss_sp     *byte
	ss_size   uintptr
	ss_flags  int32
	pad_cgo_0 [4]byte
}

type sigaltstackt stackt

type siginfo struct {
	si_signo  int32
	si_code   int32
	si_errno  int32
	si_pid    int32
	si_uid    int32
	pad_cgo_0 [4]byte
	si_addr   uintptr
	si_status int32
	pad_cgo_1 [4]byte
	si_band   int64
	si_value  uintptr
}

type sigactiont struct {
	_funcptr  [8]byte
	sa_mask   sigset
	sa_flags  int32
	pad_cgo_0 [4]byte
	userdata  [8]byte
}

type extendedregs struct {
}

// fp_q holds the 32 128-bit NEON/FP registers (struct vregs.fp_q);
// rarely accessed by the runtime's signal paths, so a flat byte array
// is enough (matches the 512-byte size: 32 * 16 bytes).
type fpregset struct {
	fp_reg_set [512]byte
}

// mcontext mirrors Haiku's struct vregs for arm64
// (headers/posix/arch/arm64/signal.h):
//
//	struct vregs {
//	    ulong x[30]; ulong lr; ulong sp; ulong elr; ulong spsr;
//	    __uint128_t fp_q[32]; u_int fpsr; u_int fpcr;
//	};
type mcontext struct {
	x      [30]uint64
	lr     uint64
	sp     uint64
	elr    uint64
	spsr   uint64
	fp_q   fpregset
	fpsr   uint32
	fpcr   uint32
}

// uc_mcontext is at offset 48, not 40: struct vregs holds __uint128_t
// fp_q[], so mcontext_t is 16-byte aligned in C (checked with
// offsetof(ucontext_t, uc_mcontext) from the Haiku cross gcc). Without
// the padding every register read through sigctxt was off by one slot
// (sigsp() returned lr, sigpc() returned sp, ...), so async preemption
// never found a safe point and signal-time PCs were garbage.
type ucontext struct {
	uc_link     *ucontext
	uc_sigmask  sigset
	uc_stack    stackt
	_           [8]byte
	uc_mcontext mcontext
}

type stat struct {
	st_dev     uint64
	pad_cgo_0  [4]byte
	st_ino     uint64
	st_mode    uint32
	st_nlink   uint32
	st_uid     uint32
	st_gid     uint32
	st_size    int64
	st_rdev    uint32
	st_blksize int32
	st_atim    timespec
	st_mtim    timespec
	st_ctim    timespec
	st_crtim   timespec
	st_fstype  uint32
	pad_cgo_1  [4]byte
	st_blocks  int64
}

type timespec struct {
	tv_sec  int64
	tv_nsec int64
}

type timeval struct {
	tv_sec    int64
	tv_usec   int32
	pad_cgo_0 [4]byte
}

type itimerval struct {
	it_interval timeval
	it_value    timeval
}

type pthread uintptr
type pthreadattr uintptr

func (ts *timespec) set_sec(x int64) {
	ts.tv_sec = x
}

func (ts *timespec) set_nsec(x int32) {
	ts.tv_nsec = int64(x)
}

func (tv *timeval) set_usec(x int32) {
	tv.tv_usec = x
}
