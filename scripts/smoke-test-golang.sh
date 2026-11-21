#!/bin/sh
# Quick post-install smoke test for golang_bin. Run on the target RenkuOS
# arm64 machine itself (over SSH or locally), after `pkgman install
# golang_bin`:
#
#   sh smoke-test-golang.sh
#
# Exercises exactly the paths this package's own revisions had to fix,
# not a general Go test suite -- a goroutine/mutex program (the asm
# trampoline width bug), os/exec (the SIGCHLD/async-preempt hang), and a
# real third-party module build through the bin/go wrapper's own
# GOPROXY/GONOSUMDB defaults (the go-isatty and x/sys overrides) -- so a
# future regression in any of those shows up here, fast, without needing
# a full `go build std` run. Exits non-zero on the first failure.
set -e
W=${W:-/tmp/golang-smoke-$$}
rm -rf "$W"
mkdir -p "$W"
trap 'rm -rf "$W"' EXIT

echo "== go version =="
go version

echo "== goroutines + mutex + GC (the asm trampoline width bug's path) =="
cat > "$W/goroutines.go" <<'EOF'
package main

import (
	"fmt"
	"runtime"
	"sync"
)

func main() {
	var mu sync.Mutex
	var wg sync.WaitGroup
	total := 0
	for i := 0; i < 20; i++ {
		wg.Add(1)
		go func(n int) {
			defer wg.Done()
			mu.Lock()
			total += n
			mu.Unlock()
		}(i)
	}
	wg.Wait()
	runtime.GC()
	if total != 190 {
		fmt.Println("FAIL: expected 190, got", total)
		panic("goroutine/mutex test failed")
	}
	fmt.Println("goroutines ok, total =", total)
}
EOF
(cd "$W" && go run goroutines.go)

echo "== os/exec (the SIGCHLD/async-preempt hang's path) =="
cat > "$W/exectest.go" <<'EOF'
package main

import (
	"fmt"
	"os/exec"
)

func main() {
	for i := 0; i < 20; i++ {
		if err := exec.Command("/bin/true").Run(); err != nil {
			fmt.Println("FAIL:", err)
			panic("os/exec test failed")
		}
	}
	fmt.Println("os/exec ok, 20/20")
}
EOF
(cd "$W" && go run exectest.go)

echo "== third-party module via the bin/go wrapper's own GOPROXY/GONOSUMDB defaults =="
(cd "$W" && go mod init smoketest >/dev/null 2>&1)
(cd "$W" && go get github.com/mattn/go-isatty@v0.0.20 >/dev/null 2>&1)
cat > "$W/isatty_check.go" <<'EOF'
package main

import (
	"fmt"
	"os"

	"github.com/mattn/go-isatty"
)

func main() {
	fmt.Println("isatty on stdin:", isatty.IsTerminal(os.Stdin.Fd()))
}
EOF
(cd "$W" && go run isatty_check.go)

echo "== ALL GOLANG SMOKE TESTS PASSED =="
