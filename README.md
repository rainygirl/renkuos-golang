# Go for RenkuOS/arm64

[English](README.md) | [한국어](README.ko.md)

A working Go 1.27.4 toolchain for `GOOS=haiku GOARCH=arm64`. RenkuOS's own Go
fork, [korli/go](https://github.com/korli/go) (branch `golang-1.27-haiku`,
also what HaikuPorts' `dev-lang/golang` recipe builds from), only supports
`haiku/amd64`. This port extends that work to arm64, on the same libc-call
model korli/go already uses instead of raw syscall traps (the same
convention Go's own `darwin`/`solaris` ports use) -- not a different
architecture for the port's own sake, the same approach, filled in for a
second architecture.

This repo is the arm64-specific and RenkuOS-specific runtime/syscall source
files (`src/`, every `*haiku*`-named file under the standard library plus
the shared files patched for RenkuOS -- `runtime/tls_arm64.{h,s}`, see
"Signals" below), the packaging script
that turns a built toolchain into a RenkuOS `.hpkg`, and a local Go module
proxy override that fixes a real third-party compatibility gap. It is not
a full Go source tree: apply it on top of a `korli/go` checkout (or
upstream Go, if korli/go's amd64 files aren't needed) the same way you'd
apply any platform port.

## Installing the prebuilt package

On a RenkuOS arm64 image, most users never build this at all -- the
packaged toolchain is published to this project's own pkgman repository:

```sh
pkgman add-repo https://pkgman.rainygirl.com/arm64   # once per system
pkgman install golang_bin
```

`scripts/smoke-test-golang.sh` is a quick post-install check, run on the
same machine: a goroutine/mutex program, `os/exec`, and a real
third-party module build through `bin/go`'s own `GOPROXY`/`GONOSUMDB`
defaults -- the exact three paths this package's own fixes touched.

```sh
sh scripts/smoke-test-golang.sh
```

## Building it

```sh
git clone --branch golang-1.27-haiku https://github.com/korli/go.git go-haiku-arm64
# copy this repo's src/ tree on top, file for file
cd go-haiku-arm64/src
GOOS=haiku GOARCH=arm64 GOROOT_BOOTSTRAP=/path/to/a/working/go ./make.bash
```

This produces two toolchains in one GOROOT: a host (e.g. `linux/arm64`)
cross-compiler for building `haiku/arm64` binaries from elsewhere, and a
native `bin/haiku_arm64/go` that is itself a real RenkuOS ELF binary, meant
to run *on* RenkuOS -- a self-hosting SDK, not just a cross-compile target.
`scripts/cross-arm64-golang.sh` stages the second one into an installable
`.hpkg` (see `golang_bin.recipe`); it expects to run inside the same
Docker-based build container this port's RenkuOS image itself uses, with the
built tree at `GOROOT_SRC`.

## The two runtime bugs

Both were found with real, reproducible, deterministic hangs -- not
guessed at -- and both are fixed in this tree already.

**1. A 32-bit/64-bit return-value width bug in four asm trampolines**
(`src/runtime/sys_haiku_arm64.s`: `sem_wait_trampoline`,
`sem_timedwait_trampoline`, `pipe2_trampoline`, `fcntl_trampoline`). Each
checked a libc call's return value with `CMP $0, R0; BGE ok`, but those
calls return a 32-bit C `int` (`-1` on error), and AArch64 zero-extends --
not sign-extends -- a 32-bit register write, so a real `-1` arrived in the
64-bit `R0` as `0x00000000FFFFFFFF`, a large positive value that never
took the error branch. `err` ended up hardcoded to `0`, so `semasleep()`
could never see a real timeout or signal correctly. Fixed with
`CMPW $-1, R0; BNE ok` -- the exact idiom Go's own `darwin`/`openbsd`
arm64 ports already use for this identical hazard. Confirmed against a
disassembly of `libroot.so`'s `sem_clockwait` (`mov w0, w19`, a 32-bit
write). This alone is enough to make ordinary goroutine/mutex-based
programs, compiled and run directly, work correctly and reliably.

**2. Go's own signal handling hanging `os/exec` and real builds**
(`src/runtime/signal_unix.go`, revisions up to 9; the real cause was found
and fixed in revision 10 and both workarounds below are gone -- see
"Signals"). Go installs its own SIGCHLD trap
unconditionally; a userspace signal trap landing on an M that is blocked
inside a libc call reached via `asmcgocall` (`read()`/`wait4()` on a
just-forked, already-exited child -- exactly what every
`os/exec.Cmd.Start()+Wait()` does, including `cmd/go` dispatching
`compile`/`asm`/`link`) reliably hung the M in a busy EINTR-retry spin.
Confirmed with a minimal reproducer (`exec.Command("/bin/sleep", "0")`):
~80-100% hang rate across repeated trials with Go's handler installed, 0%
with `signal.Ignore(syscall.SIGCHLD)`. Fixed by leaving SIGCHLD at its
inherited disposition on RenkuOS (`sigInstallGoHandler()` returns `false`
for it when `GOOS == "haiku"`); `os/signal.Notify(syscall.SIGCHLD)` still
re-installs it on demand for programs that ask. The identical hazard
showed up again via `sigPreempt` (`SIGURG`), which Go's async preemption
fires every 10-20ms at a running M -- a real build forks+execs dozens of
times over several seconds, giving it many chances to land during a
blocked libc call. Fixed by disabling async preemption on RenkuOS
(`const preemptMSupported = GOOS != "haiku"`, the same tradeoff every Go
program accepted by default before Go 1.14, and the same one
`os_plan9.go`/`os_wasm.go` already make for their own reasons). Cooperative
(function-call-based) preemption is unaffected. Verified end to end with
`go build std` -- the entire standard library, hundreds of packages, many
real fork/execs -- completing with exit code 0 from a clean build cache,
both cross-built and, later, self-hosted: the real, already-installed
package's own native `bin/haiku_arm64/go` building the standard library
on the actual target machine, over plain SSH (no desktop session), in
~52s. One intermittent flake was found doing this repeatedly (one failed
run out of roughly a dozen clean-cache attempts, no error text captured,
memory usage ruled out as a cause -- free memory never dropped below
~7.5 of 8 GiB during the one failing run) and is not yet root-caused;
every other attempt, including five more immediately afterward, passed.

A separate packaging gap (`pkg/include/` -- `textflag.h`, `funcdata.h`,
the `asm_*.h` headers -- never staged into the `.hpkg`, so any asm-based
package failed `-gensymabis` the moment the two bugs above stopped masking
it) is fixed in `scripts/cross-arm64-golang.sh`, not in `src/`.

## Signals

Up to revision 9, a Go program on haiku/arm64 ignored SIGTERM, SIGINT and
SIGHUP -- only `kill -9` stopped it -- and `os/signal.Notify` never
delivered anything. Every signal Go installed a handler for killed the
thread that received it, silently: `strace -T` showed the signal arrive
and that thread never make another system call. The SIGCHLD/SIGURG hangs
of bug 2 above were the same thing. Four bugs, all fixed in revision 10:

- **`sigtramp`'s frame clobbered its own return address**
  (`src/runtime/sys_haiku_arm64.s`). It was written after
  `sys_haiku_amd64.s` and saved its arguments at `0/8/16(SP)`. On amd64
  that is free space; on arm64 `0(RSP)` is where the assembler's prologue
  keeps the function's own saved LR, so `MOVW R0, 0(RSP)` replaced the low
  32 bits of the return address with the signal number and `sigtramp`
  never got back to Haiku's commpage signal handler. The frame now starts
  at `8(RSP)`, like every other arm64 port.
- **`sigtrampgo` was called through the wrong ABI** (same file). A plain
  `BL runtime·sigtrampgo(SB)` from assembly binds to the ABI0 wrapper,
  which reads its arguments from `8/16/24(RSP)` -- so `sigtrampgo` saw the
  `siginfo` pointer as the signal number. It (and `badsignal`) is now
  called through its `<ABIInternal>` entry point with the arguments in
  R0-R2, as `sys_linux_arm64.s`/`sys_darwin_arm64.s` do.
- **`ucontext_t.uc_mcontext` is at offset 48, not 40**
  (`src/runtime/defs_haiku_arm64.go`). `struct vregs` holds
  `__uint128_t fp_q[32]`, so `mcontext_t` is 16-byte aligned (checked with
  `offsetof` from the Haiku cross gcc). Every register read from a signal
  context was one slot off: `sigsp()` returned LR, `sigpc()` returned SP.
  Async preemption never found a safe point, and signal-time PCs in crash
  reports were wrong.
- **`pthread_self()` was truncated to 32 bits**
  (`src/runtime/os2_haiku.go`). It went through `libcCall`, which returns
  an `int32`, so `m.procid` was a sign-extended half pointer and the
  `pthread_kill` that sends async preemption's SIGURG faulted inside
  libroot. The trampoline now stores the full `pthread_t` through its
  argument.

`g` is also kept in TLS now, not only in R28 (`src/runtime/tls_arm64.h`,
`tls_arm64.s`): TPIDR_EL0 on Haiku points at libroot's own TLS slot array,
and `g` lives in slot 62, the slot haiku/amd64 uses. `sigtramp` loads it
from there, so a signal that interrupts libroot code (where R28 is just
another callee-saved register) still finds the right `g`, the same reason
darwin and openbsd always keep `g` in TLS.

With these fixed, both workarounds from bug 2 are removed and
`signal_unix.go` is upstream's again: Go installs its SIGCHLD handler and
async preemption is on. The startup debug output (`234567` on stderr at
every start, from leftover `dbgw` calls in `runtime/asm_arm64.s`) is gone
too; that file is upstream's again.

Checked on an arm64 RenkuOS VM: `signal.Notify` receives SIGTERM, SIGINT
and SIGTERM again in a row; without `Notify`, SIGTERM exits with status
143, SIGINT 130 and SIGHUP 129; a nil dereference is recovered as a panic;
a program receives about a thousand SIGUSR1s a second while three
goroutines compute (no wrong results); GC completes while a goroutine
spins in `for {}`; `os/exec` runs 200 children in a row five times over;
tailscaled shuts down cleanly on SIGTERM and its service script's cleanup
runs; rclone, syncthing and gh stop on SIGTERM/SIGINT. Natively, from the
installed revision 10 package: `scripts/smoke-test-golang.sh` passes, and
`go test -short os/signal sync` passes apart from
`TestNotifyContextStringer`, which expects Linux's name for SIGTERM
("terminated"; Haiku says "termination requested").

Still open: clean-cache `go build std` failed 3 times in 29 runs with
`compile: exit status 255` and no other output, with async preemption on
and off alike (the intermittent flake noted in bug 2). Its crash output,
if any, is hidden: Haiku's `issetugid()` (libbsd) always returns 1, so
the Go runtime runs every program in secure mode, which also cuts every
fatal signal report down to its first line (`SIGQUIT: quit`, no
goroutine dump).

## Third-party module compatibility (`scripts/golang-goproxy-overrides/`)

No build-tag issue in the standard library -- real gaps in the module
ecosystem instead. The packaged `golang_bin`'s `bin/go` is a wrapper (the
real binary is `bin/go-real`) that defaults `GOPROXY`/`GOSUMDB` (this
toolchain shipped with both blank) and puts a local GOPROXY-protocol
directory ahead of the real proxy, serving patched modules repackaged at
the same module path and version. See that directory's own README for
the exact patches and how to extend this to another module with the same
kind of gap.

**`github.com/mattn/go-isatty`** (which `github.com/gin-gonic/gin`'s
default logger needs) ships one terminal implementation per OS family and
has none that matches `haiku`, so `IsTerminal`/`IsCygwinTerminal` are
`undefined` at build time for any module that pulls it in. Fixed with a
one-line patch (add `haiku` to its existing "unsupported platform, return
false" stub). Verified end to end from a clean module cache: a fresh
`go mod init`, `go get github.com/gin-gonic/gin`, `go build`, run, and a
real HTTP 200 from `curl` against a `gin.Default()` handler -- no manual
`replace` directive, no pre-seeded cache.

**`golang.org/x/sys`** has no `haiku` support in any published version,
at all -- confirmed by cloning it directly and grepping every version of
`unix/*.go` for `haiku`: zero matches. Any module that imports
`golang.org/x/sys/unix` directly (not through something like
`golang.org/x/term`, which has its own safe fallback and never actually
reaches `x/sys/unix` on `haiku`) fails outright, a far larger share of
the ecosystem than go-isatty's own gap. Not patched from scratch here:
ported from `korli/go`'s own sibling fork,
[korli/sys_haiku](https://github.com/korli/sys_haiku) (its
`master-haiku` branch, carrying a real `amd64`-only Haiku port of this
module for years), plus this port's own already-existing `arm64`
extension of the same files (this repo's own
`src/cmd/vendor/golang.org/x/sys/unix/*_arm64*`, reused unchanged),
applied onto a clean `v0.50.0` checkout. Verified end to end on the real
target machine, not just cross-compiled: a small program built against
the patched tree, copied to the live machine over SSH, and run there --
`unix.Stat` on a real path, a full `Socket`/`Bind`/`Getsockname` round
trip, and `IoctlGetTermios` on a non-tty fd (the exact call go-isatty
itself makes) all returned correct results, and the whole module (`go
build ./...`, every non-Windows/non-Plan9 package in it) builds clean.

This override is keyed by exact version, though -- a real limitation,
not a hypothetical one: `github.com/shirou/gopsutil/v3` resolved to
`golang.org/x/sys v0.20.0` via its own `go.mod`, a version this override
didn't cover, and fell through to the real (unpatched) proxy; confirmed
directly that this version gap is real by building the same
`unix.Stat`-using program against both `v0.50.0` (clean) and `v0.20.0`
(`undefined: unix.Stat_t`). Now covers `v0.41.0` through `v0.50.0` (ten
versions) rather than just one, which helps but doesn't eliminate the
gap -- see `scripts/golang-goproxy-overrides/README.md` for the details
and for two real third-party modules (`fasthttp`, `gopsutil`) that
turned out not to actually exercise this path at all.

## cgo

`CGO_ENABLED=1` didn't work at all until this was found and fixed:
linking any cgo program failed with `relocation
R_AARCH64_ADR_PREL_PG_HI21 against symbol 'poll' which may bind
externally ... recompile with -fPIC`. Root cause, in
`cmd/link/internal/ld/data.go`'s `dynreloc()`: Go always sets `FlagD`
(suppress dynamic-loader-format output) when linking externally, which
cgo always does -- and that unconditionally skipped the `dynrelocsym()`
pass that rewrites a `cgo_import_dynamic` data symbol's address-of
relocation to go through the GOT. Haiku's libc-call-style port needs
that rewrite specifically: the compiler emits a plain page-relative
ADRP+ADD for taking the address of something like the runtime's own
`libc_poll` (`netpoll_haiku.go`), and relies on the linker to turn that
into GOT-relative addressing before handing the object to gcc/ld -- a
rewrite every other platform either doesn't need (syscall-based ports)
or gets some other way. The first fix attempt (skip `FlagD` for Haiku
entirely) built a full `.dynsym`/`.hash`/`.got.plt` as well, which
conflicts with producing a plain external-linkable object and crashed
the linker's own object writer (`internal error: ElfShdr relocSect`).
The fix that actually works runs only the one `Textp` relocation-rewrite
loop for Haiku when `FlagD` is set, leaving everything else `FlagD`
gates skipped exactly as before. Confirmed end to end: a cgo program
calling a real C function and converting a C string back to Go
(`C.add`, `C.CString`/`C.GoString`) builds and runs correctly, and the
existing goroutine/`os/exec`/go-isatty smoke tests plus a full `go build
std` still pass with no regression.

### g and TLS under cgo

The link fix above made cgo programs link, but every one of them still
kept the goroutine pointer `g` in the wrong place. With cgo the runtime
saves `g` at `TPIDR_EL0 + runtime.tls_g` (`runtime/tls_arm64.s`), and
`tls_g` was an ELF TLS symbol that the external linker turned into a
local-exec offset of 16. On Haiku, `TPIDR_EL0` is not an ELF thread
pointer: it addresses the per-thread TLS slot array (`tls_address()` in
libroot), and offset 16 is slot 2, `TLS_ERRNO_SLOT`. So `g` and `errno`
shared one word. Plain C calls survived (`asmcgocall` restores `g` from
the stack), but a C function that set `errno` and then called an
exported Go function, or a signal arriving in that state, loaded a
garbage `g` and the program hung.

`runtime/tls_arm64.h` now defines `TLSG_IS_VARIABLE` for haiku (as
Android does), `rt0_go` passes `&tls_g` to `_cgo_init`, and
`runtime/cgo/gcc_haiku_arm64.c` fills it with the byte offset of a slot
from `tls_allocate()`. The slot index is the same in every thread,
including threads created by C. Non-cgo programs never read `tls_g`.

### Building cgo programs

Cross, from haiku-builder (sysroot = `haiku.hpkg` + `haiku_devel.hpkg` +
`gcc_syslibs`/`gcc_syslibs_devel` extracted under `<sysroot>/boot/system`):

```sh
X=/root/renku-arm64-work/generated.arm64/cross-tools-arm64/bin
CGO_ENABLED=1 GOOS=haiku GOARCH=arm64 \
  CC="$X/aarch64-unknown-haiku-gcc --sysroot=<sysroot>" \
  CXX="$X/aarch64-unknown-haiku-g++ --sysroot=<sysroot>" go build
```

Native, on RenkuOS: there was no C compiler for arm64 at all (the
repositories have `gcc_syslibs`, not `gcc`). `scripts/cross-arm64-gcc.sh`
builds gcc 13.3 + binutils 2.41 as a Canadian cross with the image's own
cross tools and packages them as `gcc` (installs under
`/boot/system/develop/tools`, with `gcc`/`g++`/`cc`/`ld`/... in
`/boot/system/bin`; needs `haiku_devel`). With it installed, `go env
CGO_ENABLED` is 1 and a plain `go build` uses cgo.

Notes:
- `github.com/mattn/go-sqlite3` works as is (it compiles its bundled
  SQLite). With `-tags libsqlite3` it has no `#cgo haiku LDFLAGS`, so
  pass `CGO_LDFLAGS=-lsqlite3`; RENKU's `sqlite3` package ships the
  library but no `sqlite3.h`.
- C++ (Be API) code works through an `extern "C"` shim in the package
  with `#cgo LDFLAGS: -lbe -lstdc++`.

Tested on RenkuOS arm64 (QEMU, cross and native builds): a C hello, a
C-sets-errno-then-calls-Go test (hung before the TLS fix), mattn/go-sqlite3
both ways, a Be API shim (`find_directory`, `get_system_info`,
`BString`, `be_roster`), and a stress test (1000 goroutines x 20000 C
calls, Go callbacks from Go threads and from 16 C pthreads, GC
pressure) 10/10 runs.

## License

BSD 3-Clause, the same license as Go itself -- these are platform-port
source files written to sit alongside Go's own per-OS runtime/syscall
files, in the hope they're useful upstream (in korli/go, or in Go itself)
some day.

## AI disclosure

Claude (Anthropic) did this: the runtime port, both bug fixes, the
packaging, and the verification, end to end, inside an agentic coding
session. The author steered the session and approved each step; Claude
wrote, built, ran, and debugged essentially all of the code here.
