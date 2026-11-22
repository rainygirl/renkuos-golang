#!/bin/bash
# Stage the Go toolchain for RENKU arm64 and package it.
#
# There is no HaikuPorts arm64 repository to depend on, and Go's own
# bootstrap (make.bash) needs an existing Go compiler to cross-build a new
# port from source -- that part of the work (porting runtime/sys_haiku_*.s,
# os2_haiku.go, the x/sys/unix vendor files, and fixing a real nosplit-stack
# budget overflow plus a read()/pthread_testcancel() runtime crash specific
# to Haiku's thread bootstrap order) happened directly against a RenkuOS/Go
# source checkout at /root/go-haiku-arm64 inside haiku-builder, not here.
# This script only stages the ALREADY-BUILT result into an .hpkg, the same
# division of labor cross-arm64-fastfetch.sh and cross-arm64-cli.sh use for
# their own upstream sources.
#
# Go's own make.bash, run with GOOS=haiku GOARCH=arm64 against an existing
# linux/arm64 bootstrap compiler, produces TWO separate toolchains in one
# GOROOT, and only one of them is what ships here:
#   - bin/go, bin/gofmt, pkg/tool/linux_arm64/* -- the HOST (linux/arm64)
#     toolchain, used right now inside the container to cross-compile
#     haiku/arm64 target binaries. Not deployable to Haiku: dynamically
#     linked against the container's own glibc/ld.so, not libroot.so.
#   - bin/haiku_arm64/go, bin/haiku_arm64/gofmt, pkg/tool/haiku_arm64/* --
#     the TARGET-NATIVE toolchain: real haiku/arm64 ELF binaries (confirmed
#     via readelf: NEEDED libroot.so, PT_INTERP set), meant to be copied
#     onto a Haiku machine and run there, where GOHOSTOS/GOHOSTARCH become
#     haiku/arm64 and this native go looks for pkg/tool/haiku_arm64/ as ITS
#     own GOTOOLDIR -- a self-hosting SDK, not just a cross-compile target.
#   This is the second one. Confirmed the distinction with `go build -x`
#   (GOTOOLDIR printed as pkg/tool/linux_arm64 when cross-building from the
#   container) rather than assumed from directory names alone.
#
# pkg/<goos>_<goarch>/*.a (precompiled std library archives) is intentionally
# near-empty on this Go version -- modern Go recompiles std from source into
# its build cache instead of shipping prebuilt .a files under GOROOT/pkg, so
# src/ (minus src/cmd, the toolchain's OWN source -- needed only to rebuild
# go itself, not to build user programs) has to ship instead, and does.
#
# Runs INSIDE haiku-builder, against the already-built /root/go-haiku-arm64
# (built by: cd /root/go-haiku-arm64/src && GOOS=haiku GOARCH=arm64
# GOROOT_BOOTSTRAP=/root/go-bootstrap ./make.bash) and the image's package
# tool:
#
#   docker cp scripts/cross-arm64-golang.sh haiku-builder:/root/
#   docker exec haiku-builder bash /root/cross-arm64-golang.sh
#   -> /root/gostage/golang_bin-<VER>-<REV>-arm64.hpkg
#
# Verified end to end before this script was written (not just "it builds"):
# a trivial Go program (fmt.Println, plus a second test exercising 20
# goroutines, sync.WaitGroup, runtime.GC, and os.ReadFile) cross-built with
# this exact toolchain ran correctly, repeatedly (10/10 clean runs), on a
# disposable isolated QEMU instance running the real renku-arm64-live.iso --
# separate from both the shared Node.js-build VM and the real install/live
# flow run-qemu-renku-arm64.sh drives, cleaned up (QMP quit, overlay deleted)
# before this script was written. Deploying the native bin/haiku_arm64/go
# itself onto a guest and self-hosting a build there was attempted but
# blocked by an unrelated, pre-existing infra limitation: the live image's
# boot volume only grows past its 300 MiB base size through a desktop-login
# launch job (renku_grow_boot, arm64-patch 0046), which a headless QEMU
# instance with no desktop session never runs, and invoking it directly over
# SSH without that session reports "the boot partition already fills" rather
# than growing it. That caveat turned out not to block verification on an
# already-installed image whose boot volume had already grown once (through
# an earlier desktop session, e.g. during Installer): confirmed later,
# against the actual installed -4 package over plain SSH (no desktop
# session involved), with GOCACHE pointed at a clean directory: `go build
# std` -- the entire standard library, hundreds of packages, many real
# fork/execs -- completed with exit code 0 in ~52s real time, using the
# package's own native bin/haiku_arm64/go (shipped as lib/go/bin/go-real)
# to build itself. A from-scratch image that only ever boots headless over
# SSH, never through a desktop session, would still hit the volume-growth
# limit; that specific case remains unverified.
set -e
VER=1.27.4
REV=${REV:-1}
GOROOT_SRC=${GOROOT_SRC:-/root/go-haiku-arm64}
W=${W:-/root/gostage}
GEN=/root/renku-arm64-work/generated.arm64
PKG=$GEN/objects/linux/arm64/release/tools/package/package

rm -rf "$W"
mkdir -p "$W/root/bin" "$W/root/lib/go/bin" "$W/root/lib/go/pkg/tool" \
         "$W/root/lib/go/haiku-goproxy" "$W/root/documentation/packages/golang_bin"
root=$W/root

cp "$GOROOT_SRC/bin/haiku_arm64/go" "$root/lib/go/bin/go-real"
cp "$GOROOT_SRC/bin/haiku_arm64/gofmt" "$root/lib/go/bin/"
# bin/go is a wrapper, not the real binary (same pattern as nodejs_bin's
# bin/node): it defaults GOPROXY/GOSUMDB (this toolchain ships with both
# blank, which breaks every module fetch with "GOPROXY list is ... no
# entries" / "missing GOSUMDB" until a user sets them by hand) and adds a
# local GOPROXY-protocol override directory ahead of the real proxy, so
# modules with no haiku build tag that this override covers work out of
# the box -- currently github.com/mattn/go-isatty (which
# github.com/gin-gonic/gin's default logger needs) and, far more broadly,
# golang.org/x/sys itself: the public module has no haiku support in any
# version, at all (confirmed: zero haiku-named files in golang.org/x/sys's
# own unix/ package), which silently breaks any third-party module that
# imports golang.org/x/sys/unix directly -- a very large share of the
# ecosystem, well beyond gin's own narrower go-isatty dependency. See
# scripts/golang-goproxy-overrides/README.md for both patches and how to
# extend this to another module with the same kind of gap. All three
# defaults here are only defaults: an already-set GOPROXY/GOSUMDB/GONOSUMDB
# from the caller's own environment is left alone.
cat > "$root/lib/go/bin/go" <<'WRAP'
#!/bin/sh
export GOPROXY="${GOPROXY:-file:///boot/system/lib/go/haiku-goproxy,https://proxy.golang.org,direct}"
export GOSUMDB="${GOSUMDB:-sum.golang.org}"
export GONOSUMDB="github.com/mattn/go-isatty,golang.org/x/sys${GONOSUMDB:+,$GONOSUMDB}"
exec /boot/system/lib/go/bin/go-real "$@"
WRAP
chmod +x "$root/lib/go/bin/go"
cp -r "$(dirname "$0")/golang-goproxy-overrides/github.com" "$root/lib/go/haiku-goproxy/github.com"
cp -r "$(dirname "$0")/golang-goproxy-overrides/golang.org" "$root/lib/go/haiku-goproxy/golang.org"
cp -r "$GOROOT_SRC/pkg/tool/haiku_arm64" "$root/lib/go/pkg/tool/haiku_arm64"
# pkg/include (textflag.h, funcdata.h, asm_*.h) was missing from every
# earlier revision of this package: the `asm` tool's `-gensymabis` step
# passes `-I $GOROOT/pkg/include` unconditionally for every assembly
# file, and a self-hosted `go build`/`go run` on a real Haiku install
# hit `#include: open .../pkg/include/textflag.h: no such file or
# directory` for every asm-based package (internal/abi, internal/cpu,
# math, sync/atomic, ...) the moment the SIGCHLD/async-preempt runtime
# hang (see golang_bin.recipe) stopped masking it by making the build
# die before ever reaching the first compile step. Confirmed missing
# with `ls /boot/system/lib/go/pkg/include/` on an installed -2 image
# (ENOENT) and confirmed fixed by staging this directory and rebuilding
# std from scratch (`go build std`) end to end on the same image.
cp -r "$GOROOT_SRC/pkg/include" "$root/lib/go/pkg/include"
cp -r "$GOROOT_SRC/src" "$root/lib/go/src"
rm -rf "$root/lib/go/src/cmd"
cp "$GOROOT_SRC/VERSION" "$root/lib/go/" 2>/dev/null || true
cp -r "$GOROOT_SRC/doc" "$root/lib/go/doc" 2>/dev/null || true
cp -r "$GOROOT_SRC/api" "$root/lib/go/api" 2>/dev/null || true

# GOROOT/bin/{go,gofmt} are the two entry points users and other tools put
# on PATH; everything else lives under lib/go. gofmt needs no wrapper, so
# it keeps the plain two-levels-up GOROOT auto-detection the rust_bin
# package here also relies on for cargo/rustc (Go resolves symlinks when
# locating its own GOROOT: os.Executable + filepath.EvalSymlinks). go
# itself is reached through the wrapper above instead, via this same
# symlink -- bin/go -> lib/go/bin/go (the wrapper) -> exec lib/go/bin/go-real.
ln -s ../lib/go/bin/go "$root/bin/go"
ln -s ../lib/go/bin/gofmt "$root/bin/gofmt"

cp "$GOROOT_SRC/LICENSE" "$root/documentation/packages/golang_bin/" 2>/dev/null || true
cp "$GOROOT_SRC/PATENTS" "$root/documentation/packages/golang_bin/" 2>/dev/null || true

cat > "$root/.PackageInfo" <<INFO
name		golang_bin
version		$VER-$REV
architecture	arm64
summary		"Go compiler, standard library and tools for Haiku ARM64"
description	"Native Go $VER toolchain for Haiku ARM64 (go, gofmt, the standard library source, and the compile/link/asm/cgo/vet/cover/fix tool binaries). Cross-built from upstream Go's source against a from-scratch RenkuOS/Go haiku/arm64 runtime port -- this image has no prior Go support of any kind, and HaikuPorts has no arm64 repository to depend on either. GOROOT is self-contained under lib/go; bin/gofmt is a plain symlink into it, bin/go is a wrapper (the real binary is lib/go/bin/go-real) that defaults GOPROXY/GOSUMDB and layers in local module overrides for github.com/mattn/go-isatty (which github.com/gin-gonic/gin needs) and golang.org/x/sys, v0.41.0-v0.50.0 (which has no haiku support in any published version at all, breaking any module that imports golang.org/x/sys/unix directly) -- see golang_bin.recipe and scripts/golang-goproxy-overrides/README.md. CGO_ENABLED=1 now works: cmd/link/internal/ld/data.go's dynreloc() unconditionally skipped the GOT relocation rewrite cgo_import_dynamic data symbols need under external linking (which cgo always uses), fixed for haiku specifically without touching anything else that skip gates. Revision 10 makes signals work: programs now stop on SIGTERM/SIGINT/SIGHUP and os/signal.Notify receives them (sigtramp's frame clobbered its own saved return address and called sigtrampgo through the wrong ABI, ucontext_t's uc_mcontext offset was 8 bytes off, and pthread_self() was truncated to 32 bits), which also lets async preemption and Go's SIGCHLD handler be turned back on."
packager	"RENKU <renku@localhost>"
vendor		"RENKU"
copyrights {
	"2009 The Go Authors"
}
licenses {
	"BSD (3-clause)"
}
provides {
	golang_bin = $VER
	cmd:go = $VER
	cmd:gofmt = $VER
}
requires {
	haiku
}
INFO

export LD_LIBRARY_PATH=$GEN/objects/linux/lib
(cd "$root" && "$PKG" create -z zlib -9 "$W/golang_bin-$VER-$REV-arm64.hpkg" >/dev/null)
"$PKG" list "$W/golang_bin-$VER-$REV-arm64.hpkg" | head -20
echo "-> $W/golang_bin-$VER-$REV-arm64.hpkg"
