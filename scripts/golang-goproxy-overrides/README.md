# Haiku/arm64 Go module overrides

A local GOPROXY-protocol directory (`go help goproxy`), bundled into
`golang_bin` and consulted before the real proxy, so that popular modules
with no `haiku` build tag just work out of the box.

## github.com/mattn/go-isatty @ v0.0.20

`gin-gonic/gin`'s default logger calls `isatty.IsTerminal`/`IsCygwinTerminal`.
Upstream go-isatty ships one real/stub implementation file per OS family
(`isatty_bsd.go`, `isatty_tcgets.go` for linux/aix/zos, `isatty_solaris.go`,
`isatty_windows.go`, `isatty_plan9.go`) plus `isatty_others.go`, a stub
returning `false` for `appengine || js || nacl || tinygo || wasm`. `haiku`
matches none of these, so both functions are `undefined` at build time --
confirmed building a real `gin.Default()` app with the vanilla module.

Fix: add `haiku` to `isatty_others.go`'s build constraint (same safe
always-`false` stub already used for the other unsupported platforms --
correct here too, since a terminal-color check over an SSH-piped session
should say "not a terminal" anyway). One line changed, patch below.

```diff
---
 isatty_others.go
+++
@@ -1,5 +1,5 @@
-//go:build (appengine || js || nacl || tinygo || wasm) && !windows
-// +build appengine js nacl tinygo wasm
+//go:build (appengine || haiku || js || nacl || tinygo || wasm) && !windows
+// +build appengine haiku js nacl tinygo wasm
 // +build !windows
```

The patched module is repackaged as a module zip at the *same* module path
and version (`v0.0.20`) under `github.com/mattn/go-isatty/@v/` here, built
with `golang.org/x/mod/zip.CreateFromDir`. `golang_bin`'s `bin/go` wrapper
prepends this directory's parent to `GOPROXY` and adds this module to
`GONOSUMDB` (content differs from the public checksum database on purpose,
so sumdb verification has to be skipped for just this one module --
`GOPROXY` resolution itself is untouched for everything else, and the real
proxy is still second in the chain for every module not overridden here).

Rebuilding the zip (if a newer go-isatty version needs the same fix):

```sh
git clone --depth 1 --branch v0.0.XX https://github.com/mattn/go-isatty.git src
# apply the same one-line patch to isatty_others.go
mkdir clean && cp src/*.go src/go.mod src/go.sum src/LICENSE src/README.md clean/
go run <a small main.go calling golang.org/x/mod/zip.CreateFromDir> \
	github.com/mattn/go-isatty v0.0.XX clean v0.0.XX.zip
cp clean/go.mod v0.0.XX.mod
echo '{"Version":"v0.0.XX","Time":"<RFC3339>"}' > v0.0.XX.info
echo v0.0.XX > list   # or add a line if other versions are kept
cp v0.0.XX.info ../@latest   # one level up from @v/
```

Verified end to end: `go clean -modcache` (so nothing is already cached
from an earlier, unpatched fetch), then a fresh `go mod init` + `go get
github.com/gin-gonic/gin` + `go build` + run + `curl` against a real
`gin.Default()` handler, using only `golang_bin`'s own `bin/go` wrapper
defaults -- no manual `replace` directive, no pre-seeded module cache.

## golang.org/x/sys @ v0.50.0

A much bigger gap than go-isatty's: the public `golang.org/x/sys` module
has **no `haiku` support in any published version, at all** -- confirmed
by cloning it directly and grepping for `haiku` across `unix/*.go`: zero
matches, in any file, at any version. Any third-party module that imports
`golang.org/x/sys/unix` directly (not through something like
`golang.org/x/term`, which already has its own safe `!<every supported
GOOS>` fallback stub and never actually reaches `x/sys/unix` on haiku)
fails outright with a wall of `undefined: unix.Sockaddr` /
`undefined: unix.Errno` / etc. errors -- this is a far larger share of
the ecosystem than gin's own go-isatty dependency.

This is not something to patch from scratch here: `korli/go`'s own
sibling fork, [korli/sys_haiku](https://github.com/korli/sys_haiku), has
carried a real `amd64`-only Haiku port of this exact module for years, on
its `master-haiku` branch (periodically rebased onto upstream
`golang.org/x/sys`'s `master`). Diffing that branch against its own
`master` gives the authoritative patch:

- New files (ported as-is, `amd64` only there): `dev_haiku.go`,
  `syscall_haiku.go`, `syscall_haiku_amd64.go`, `zerrors_haiku_amd64.go`,
  `zsyscall_haiku_amd64.go`, `ztypes_haiku_amd64.go`,
  `asm_haiku_amd64.s` (plus the `mkall.sh`/`mkerrors.sh`/`mksyscall_haiku.go`
  generator-input changes, not needed here since we ship the generated
  output, not the generator).
- The `arm64` siblings of those same files
  (`syscall_haiku_arm64.go`, `zerrors_haiku_arm64.go`,
  `zsyscall_haiku_arm64.go`, `ztypes_haiku_arm64.go`, `asm_haiku_arm64.s`)
  are this port's own extension, not korli's -- the same `src/`-tree files
  already carried in `renkuos-golang`'s own repo under
  `cmd/vendor/golang.org/x/sys/unix/` (Go's internal vendored copy of this
  same module, which this port already had to patch for arm64 to get the
  toolchain itself to build). Reused here unchanged.
- One-line `|| haiku` additions to the build constraint of 14 existing,
  OS-generic files that aliased to a shared `solaris`-shaped abstraction
  (`aliases.go`, `constants.go`, `dirent.go`, `env_unix.go`, `fdset.go`,
  `ioctl_unsigned.go`, `mmap_nomremap.go`, `pagesize_unix.go`,
  `sockcmsg_unix.go`, `sockcmsg_unix_other.go`, `syscall.go`,
  `syscall_unix.go`, `timestruct.go`) plus two files with parenthesized
  constraints handled the same way (`race0.go`, `syscall_unix_gc.go`).
  None of these contain anything haiku-specific themselves -- they are
  generic across every unix-like `GOOS` already listed, same as the
  go-isatty fix's own reasoning.

Applied to a fresh `v0.50.0` checkout of the real `golang.org/x/sys`
(rather than korli's older, `amd64`-only, pre-module-era base) by diffing
`master` against `master-haiku` for just the 14+2 build-tag lines above
(trivial -- each is `grep`-and-reinsert-alphabetically, not a real content
change) and copying this port's own already-existing `*_arm64*` files on
top unchanged. Repackaged the same way as go-isatty: a module zip at
`golang.org/x/sys/@v/v0.50.0.zip`, built with
`golang.org/x/mod/zip.CreateFromDir`, served from this same override
directory and `GONOSUMDB`-exempted.

Rebuilding (if a newer `golang.org/x/sys` release needs the same patch):

```sh
git clone --depth 1 --branch vX.Y.Z https://github.com/golang/sys.git clean
cp /path/to/renkuos-golang/src/cmd/vendor/golang.org/x/sys/unix/*haiku* clean/unix/
# re-add `|| haiku` to the 16 generic files listed above (diff
# korli/sys_haiku's master..master-haiku for the exact lines, or just
# insert "haiku" alphabetically into each //go:build line yourself --
# it's always a plain OR-list except race0.go and syscall_unix_gc.go,
# which have one extra pair of parens to insert it outside of)
go run <the same zip.CreateFromDir helper go-isatty's section above uses> \
	golang.org/x/sys vX.Y.Z clean vX.Y.Z.zip
cp clean/go.mod vX.Y.Z.mod
echo '{"Version":"vX.Y.Z","Time":"<RFC3339>"}' > vX.Y.Z.info
echo vX.Y.Z > list
cp vX.Y.Z.info ../@latest
```

Verified end to end on the real RenkuOS arm64 VM (not just cross-compiled):
built a small program against the patched tree with `GOOS=haiku
GOARCH=arm64`, copied the resulting binary to the live machine over SSH,
and ran it there. `unix.Stat` on a real path, a full
`Socket`/`Bind`/`Getsockname` round trip (exercising the `Sockaddr`
family this module's own abstraction layer depends on), and
`IoctlGetTermios` on a non-tty fd (the exact call go-isatty itself makes)
all returned correct, expected results -- confirming not just that the
package compiles, but that its syscall-dispatch path actually works
against the real kernel. Also confirmed the whole module still builds
clean end to end (`go build ./...`, every non-Windows/non-Plan9 package
in it, not just `unix`) with no other gaps.
