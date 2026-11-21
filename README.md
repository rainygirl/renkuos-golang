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
the one shared file patched for RenkuOS -- see below), the packaging script
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
(`src/runtime/signal_unix.go`). Go installs its own SIGCHLD trap
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
