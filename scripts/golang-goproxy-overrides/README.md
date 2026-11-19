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
